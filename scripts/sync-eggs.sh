#!/usr/bin/env bash
#
# sync-eggs.sh: build the egg catalog for this repository.
#
# The egg collection repos stay the single source of truth: nothing is
# mirrored here anymore. This script discovers every `*-Eggs` repo in the
# org, reads the egg JSON definitions inside them, and generates:
#
#   docs/data/catalog.json   machine-readable catalog (the website consumes it)
#   README.md                refreshes the <!-- NEST:START:* --> blocks
#
# Sources, in priority order (dedupe keeps the manifest entry):
#   1. egg-sources.json "sources"  (explicit entries: repo / dir / ref)
#   2. auto-discovery: every non-archived org repo named "<something>-Eggs"
#      (case-insensitive) or exactly "Eggs"
#
# Behaviour:
#   - read-only against upstream (metadata API + shallow clone); never pushes there
#   - each collection is harvested independently; a failing upstream is
#     reported but never blocks the others
#   - writes three artifacts:
#       public/data/catalog.json      machine-readable catalog (live fetch)
#       public/eggs/<Repo>/*.json     verbatim egg definitions (import in the
#                                     panel or reference from the site)
#       generated/catalog.seed.ts     typed seed module bundled into the site
#   - README.md marker blocks are refreshed every run
#   - commit step is a no-op when nothing changed (deterministic output)
#
# Environment:
#   GH_TOKEN / gh auth login   GitHub credentials that can read the org
#   GH_EGGS_ORG                override org (default: egg-sources.json .org)
#   GH_EGGS_MANIFEST           override manifest path (default: egg-sources.json)
#   GH_EGGS_CATALOG_DIR        where catalog.json is written (default: docs/data)
#   GH_EGGS_README             README path to refresh (default: README.md)
#   DRY_RUN=1                  generate only; skip commit and push

set -euo pipefail

MANIFEST="${GH_EGGS_MANIFEST:-egg-sources.json}"
CATALOG_DIR="${GH_EGGS_CATALOG_DIR:-public/data}"
EGGS_DIR="${GH_EGGS_EGGS_DIR:-public/eggs}"
SEED_FILE="${GH_EGGS_SEED_FILE:-generated/catalog.seed.ts}"
README_FILE="${GH_EGGS_README:-README.md}"
ORG_DEFAULT="PotenFYR-Studios"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

log()  { printf '%s\n' "$*"; }
warn() { printf '%s\n' "$*" >&2; }

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------

for bin in gh jq git; do
  command -v "$bin" >/dev/null || { warn "error: $bin is required"; exit 1; }
done

if [[ -z "${GH_TOKEN:-}" ]] && ! gh auth status >/dev/null 2>&1; then
  warn "error: gh is not authenticated (set GH_TOKEN or run 'gh auth login')"
  exit 1
fi

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  warn "error: not inside a git work tree"
  exit 1
}

if [[ -f "$MANIFEST" ]]; then
  ORG="$(jq -r '.org // empty' "$MANIFEST")"
else
  ORG=""
fi
ORG="${GH_EGGS_ORG:-${ORG:-$ORG_DEFAULT}}"

log "building egg catalog for org: ${ORG}"

# ---------------------------------------------------------------------------
# 1. Resolve the source list
# ---------------------------------------------------------------------------

ENTRIES="$WORKDIR/entries.tsv"
: > "$ENTRIES"

# 1a. Explicit manifest sources first: they win on dedupe.
if [[ -f "$MANIFEST" ]]; then
  jq -r '.sources // [] | .[] | [ .repo, (.dir // ""), (.ref // "") ] | @tsv' \
    "$MANIFEST" >> "$ENTRIES"
fi

# 1b. Org discovery: non-archived repos named *-Eggs (or exactly Eggs).
discovered="$(gh api --paginate "orgs/${ORG}/repos?per_page=100" \
  --jq '.[]
        | select(.archived | not)
        | select((.name | ascii_downcase | endswith("-eggs"))
                 or (.name | ascii_downcase == "eggs"))
        | .name' 2>/dev/null | sort -u || true)"

while IFS= read -r name; do
  [[ -z "$name" ]] && continue
  printf '%s\t%s\t%s\n' "$name" "$name" "" >> "$ENTRIES"
done <<< "$discovered"

# Dedupe by repo, keeping the first occurrence (manifest beats discovery).
awk -F'\t' '!seen[$1]++' "$ENTRIES" > "$ENTRIES.tmp" && mv "$ENTRIES.tmp" "$ENTRIES"

# 1c. Drop excluded repos (case-insensitive match on repo name).
if [[ -f "$MANIFEST" ]]; then
  jq -r '.exclude // [] | .[]' "$MANIFEST" > "$WORKDIR/exclude.txt" 2>/dev/null || :
  if [[ -s "$WORKDIR/exclude.txt" ]]; then
    awk -F'\t' 'NR==FNR { ex[tolower($1)]; next }
                !((tolower($1)) in ex)' \
      "$WORKDIR/exclude.txt" "$ENTRIES" > "$ENTRIES.tmp"
    mv "$ENTRIES.tmp" "$ENTRIES"
  fi
fi

if [[ ! -s "$ENTRIES" ]]; then
  warn "error: no egg sources resolved (discovery returned nothing and manifest is empty)"
  exit 1
fi

log "sources resolved:"
cut -f1 "$ENTRIES" | sed 's/^/  - /'

# ---------------------------------------------------------------------------
# 2. Harvest every collection (independently; failures never block the rest)
# ---------------------------------------------------------------------------

COLLECTIONS="$WORKDIR/collections.ndjson"
: > "$COLLECTIONS"
failed=()

while IFS=$'\t' read -r repo dir ref; do
  [[ -z "$repo" ]] && continue
  refspec="${ref:-HEAD}"

  echo "::group::harvest ${repo}"
  if ! meta="$(gh api "repos/${ORG}/${repo}" \
        --jq '{repo:.name,
               url:.html_url,
               description:(.description // ""),
               topics:(.topics // []),
               language:(.language // ""),
               stars:.stargazers_count,
               forks:.forks_count,
               open_issues:.open_issues_count,
               license:(.license.spdx_id // ""),
               default_branch:(.default_branch // "main"),
               pushed_at:(.pushed_at // ""),
               homepage:(.homepage // "")}' 2>/dev/null)"; then
    warn "::warning::metadata fetch failed for ${ORG}/${repo}"
    failed+=("$repo")
    echo "::endgroup::"
    continue
  fi

  sha="$(git ls-remote "https://github.com/${ORG}/${repo}.git" "$refspec" \
          | awk 'NR==1 { print $1 }')"
  if [[ -z "${sha:-}" ]]; then
    warn "::warning::could not resolve ${ORG}/${repo} (${refspec})"
    failed+=("$repo")
    echo "::endgroup::"
    continue
  fi

  clone="$WORKDIR/$repo"
  if ! git clone --quiet --depth 1 ${ref:+--branch "$ref"} \
        "https://github.com/${ORG}/${repo}.git" "$clone" 2>/dev/null; then
    warn "::warning::clone failed for ${ORG}/${repo}"
    failed+=("$repo")
    echo "::endgroup::"
    continue
  fi

  # A JSON file counts as an egg definition when it has both a name and
  # docker_images (any filename, any depth): future repos need no changes here.
  eggs="$WORKDIR/eggs.ndjson"
  : > "$eggs"
  mkdir -p "$EGGS_DIR/$repo"
  find "$EGGS_DIR/$repo" -type f -name '*.json' -delete 2>/dev/null || :
  while IFS= read -r -d '' f; do
    rel="${f#"$clone"/}"
    jq -e '(.name | type) == "string" and (.docker_images | type) == "object"' "$f" >/dev/null 2>&1 || continue
    # verbatim copy for the repo's public/eggs mirror
    safe_rel="${rel//\//__}"
    cp "$f" "$EGGS_DIR/$repo/$safe_rel"
    jq -c --arg path "$rel" --arg local "$EGGS_DIR/$repo/$safe_rel" '
      select((.name | type) == "string" and (.docker_images | type) == "object")
      | {
          path: $path,
          local: $local,
          name: .name,
          description: ((.description // "") | gsub("[\\n\\r\\t]+"; " ") |
                        if length > 220 then .[0:217] + "..." else . end),
          author: (.author // ""),
          exported_at: (.exported_at // ""),
          images: [ .docker_images | to_entries[] | { name: .key, uri: .value } ],
          variables: [ .variables[]? | {
              name: (.name // ""),
              env_variable: (.env_variable // ""),
              default_value: ((.default_value // "") | tostring)
          } ],
          features: (.features // []),
          startup: ((.startup // "") | if length > 160 then .[0:157] + "..." else . end)
        }' "$f" >> "$eggs" || warn "::warning::unparsable egg json skipped: ${repo}/${rel}"
  done < <(find "$clone" -type f -name '*.json' -not -path '*/.git/*' -print0 | sort -z)

  jq -cn --argjson meta "$meta" --arg sha "$sha" \
        --slurpfile eggs "$eggs" \
        '$meta + { upstream_sha: $sha, eggs: ($eggs // []) }' \
        >> "$COLLECTIONS"

  egg_count="$(jq -s 'length' "$eggs")"
  log "harvested ${repo}: ${egg_count} egg(s)"
  rm -rf "$clone"
  echo "::endgroup::"
done < "$ENTRIES"

# ---------------------------------------------------------------------------
# 3. Emit public/data/catalog.json
# ---------------------------------------------------------------------------

mkdir -p "$CATALOG_DIR"
# Deterministic "generated_at": the newest upstream push across collections.
# Identical upstreams -> identical catalog -> no commit, no Pages redeploy.
generated_at="$(jq -s -r '[.[].pushed_at | select(length > 0)] | max // "1970-01-01T00:00:00Z"' "$COLLECTIONS")"

jq -s --arg org "$ORG" --arg generated_at "$generated_at" '
  {
    org: $org,
    generated_at: $generated_at,
    counts: {
      collections: length,
      eggs: ([.[].eggs | length] | add // 0),
      variables: ([.[].eggs[].variables | length] | add // 0),
      images:    ([.[].eggs[].images    | length] | add // 0)
    },
    collections: .
  }' "$COLLECTIONS" > "$CATALOG_DIR/catalog.json"

total_collections="$(jq '.counts.collections' "$CATALOG_DIR/catalog.json")"
total_eggs="$(jq '.counts.eggs' "$CATALOG_DIR/catalog.json")"
total_vars="$(jq '.counts.variables' "$CATALOG_DIR/catalog.json")"

# Prune public/eggs mirrors whose upstream repo no longer exists.
mkdir -p "$EGGS_DIR"
while IFS= read -r d; do
  [[ -z "$d" ]] && continue
  log "pruning stale egg mirror: ${EGGS_DIR}/${d}/"
  rm -rf -- "$EGGS_DIR/$d"
done < <(cd "$EGGS_DIR" && ls -d */ 2>/dev/null | tr -d '/' \
           | grep -v -x -i -F -f <(cut -f2 "$ENTRIES" | grep -v '^$') || true)

# Emit the typed seed module the site imports at build time, so the full
# catalog ships inside the initial HTML (SEO) without a fetch round-trip.
seed_dir="$(dirname "$SEED_FILE")"
mkdir -p "$seed_dir"
{
  printf '// AUTO-GENERATED by scripts/sync-eggs.sh. Do not edit.\n'
  printf '// Source of truth: the org'"'"'s *-Eggs repositories.\n'
  printf 'import type { Catalog } from "../src/lib/types";\n\n'
  printf 'export const catalogSeed: Catalog = %s;\n' \
    "$(jq -c . "$CATALOG_DIR/catalog.json")"
} > "$SEED_FILE"
log "seed module written: ${SEED_FILE}"
log "catalog written: ${CATALOG_DIR}/catalog.json (${total_collections} collections, ${total_eggs} eggs, ${total_vars} variables)"

# ---------------------------------------------------------------------------
# 4. Refresh the README marker blocks (left untouched if markers are missing)
# ---------------------------------------------------------------------------

refresh_block() {
  local file="$1" start="$2" end="$3" insert_file="$4"
  if ! grep -qF "$start" "$file"; then
    warn "warning: ${start} not found in ${file}; block skipped"
    return 0
  fi
  awk -v s="$start" -v e="$end" '
    NR == FNR { ins = ins $0 ORS; next }
    index($0, s) { print; printf "%s", ins; skip = 1; next }
    index($0, e) { skip = 0 }
    !skip { print }
  ' "$insert_file" "$file" > "$file.tmp"
  mv "$file.tmp" "$file"
}

STATS_BLOCK="$WORKDIR/readme-stats.md"
TABLE_BLOCK="$WORKDIR/readme-table.md"

{
  printf '> 🥚 **%s** collections · **%s** eggs · **%s** variables: generated `%s`, refreshed by every sync run.\n' \
    "$total_collections" "$total_eggs" "$total_vars" "$generated_at"
} > "$STATS_BLOCK"

{
  printf '| 🗂️ Collection | About | Stars | Last push |\n'
  printf '|:---|:---|:---:|:---:|\n'
  jq -r '.collections[] |
    "| [\(.repo)](\(.url)) | \(.description | gsub("\\|"; "/")) | [![Stars](https://img.shields.io/github/stars/'"$ORG"'/\(.repo)?style=flat-square&logo=github&labelColor=1c1e26&color=eac54f)](\(.url)/stargazers) | [![Last push](https://img.shields.io/github/last-commit/'"$ORG"'/\(.repo)?style=flat-square&logo=git&labelColor=1c1e26&color=2ea043)](\(.url)/commits) |"' \
    "$CATALOG_DIR/catalog.json"
} > "$TABLE_BLOCK"

if [[ -f "$README_FILE" ]]; then
  refresh_block "$README_FILE" '<!-- NEST:START:stats -->'   '<!-- NEST:END:stats -->'   "$STATS_BLOCK"
  refresh_block "$README_FILE" '<!-- NEST:START:catalog -->' '<!-- NEST:END:catalog -->' "$TABLE_BLOCK"
fi

# ---------------------------------------------------------------------------
# 5. Commit and push (skipped under DRY_RUN)
# ---------------------------------------------------------------------------

if [[ "${DRY_RUN:-0}" == "1" ]]; then
  log "DRY_RUN=1 -> skipping commit and push"
  git status --short | sed 's/^/  /'
else
  git add -A .
  if ! git diff --cached --quiet; then
    subject="catalog: sync egg catalog and site data"
    {
      echo "$subject"
      echo
      echo "- collections: ${total_collections}, eggs: ${total_eggs}, variables: ${total_vars}"
      echo "- failed: ${failed[*]:-none}"
    } > "$WORKDIR/commit-msg.txt"
    git commit --quiet --file="$WORKDIR/commit-msg.txt"

    push_ok=0
    for attempt in 1 2 3; do
      if git push --quiet origin HEAD 2>/dev/null; then
        push_ok=1
        break
      fi
      log "push failed (attempt ${attempt}/3); rebasing on upstream and retrying..."
      git fetch --quiet origin
      git rebase --quiet '@{upstream}'
    done
    if (( ! push_ok )); then
      warn "error: push failed after 3 attempts"
      exit 1
    fi
    log "pushed: $subject"
  else
    log "catalog already up to date; nothing to commit"
  fi
fi

# ---------------------------------------------------------------------------
# 6. Job summary + exit status
# ---------------------------------------------------------------------------

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    echo "## Egg catalog sync (${ORG})"
    echo
    echo "| result | value |"
    echo "|---|---|"
    echo "| collections | ${total_collections} |"
    echo "| eggs | ${total_eggs} |"
    echo "| variables | ${total_vars} |"
    echo "| failed | ${failed[*]:-none} |"
  } >> "$GITHUB_STEP_SUMMARY"
fi

if (( ${#failed[@]} > 0 )); then
  warn "warning: ${#failed[@]} source(s) failed: ${failed[*]}"
  exit 1
fi

log "done: collections=${total_collections} eggs=${total_eggs} failed=0"
