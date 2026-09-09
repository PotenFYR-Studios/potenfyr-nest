#!/usr/bin/env bash
#
# sync-eggs.sh — mirror every egg collection in the org into this repository.
#
# Sources, in priority order (dedupe keeps the manifest entry):
#   1. egg-sources.json "sources"  (explicit entries: repo / dir / ref)
#   2. auto-discovery: every non-archived org repo named "<something>-Eggs"
#      (case-insensitive) or exactly "Eggs"
#
# Behaviour:
#   - per-repo upstream HEAD sha tracking in .egg-sync-state.json:
#     unchanged repos are skipped entirely (no clone, no rsync, no commits)
#   - each collection syncs independently; a failing upstream is reported
#     but never blocks the others
#   - upstream deletions and renames propagate (rsync --delete)
#   - mirrors of repos removed from the org are pruned
#   - single atomic commit + push (rebase-retried) when anything changed
#
# Environment:
#   GH_TOKEN / gh auth login   GitHub credentials that can read the org
#   GH_EGGS_ORG                override org (default: egg-sources.json .org)
#   GH_EGGS_MANIFEST           override manifest path (default: egg-sources.json)
#   DRY_RUN=1                  sync only; skip commit and push

set -euo pipefail

MANIFEST="${GH_EGGS_MANIFEST:-egg-sources.json}"
STATE_FILE=".egg-sync-state.json"
ORG_DEFAULT="PotenFYR-Studios"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

log()  { printf '%s\n' "$*"; }
warn() { printf '%s\n' "$*" >&2; }

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------

for bin in gh jq rsync git; do
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

log "syncing egg mirrors for org: ${ORG}"

# ---------------------------------------------------------------------------
# 1. Resolve the source list
# ---------------------------------------------------------------------------

ENTRIES="$WORKDIR/entries.tsv"
: > "$ENTRIES"

# 1a. Explicit manifest sources first — they win on dedupe.
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

# 1d. Directories currently mirrored (used for stale-mirror pruning below).
CUR_DIRS="$WORKDIR/current_dirs.txt"
cut -f2 "$ENTRIES" | grep -v '^$' | sort -u > "$CUR_DIRS" || :

if [[ ! -s "$ENTRIES" ]]; then
  warn "error: no egg sources resolved (discovery returned nothing and manifest is empty)"
  exit 1
fi

log "sources resolved:"
cut -f1 "$ENTRIES" | sed 's/^/  - /'

# ---------------------------------------------------------------------------
# 2. Prune mirrors whose upstream repo no longer exists
# ---------------------------------------------------------------------------

while IFS= read -r d; do
  [[ -z "$d" ]] && continue
  log "pruning stale mirror: ${d}/"
  rm -rf -- "$d"
done < <(find . -mindepth 1 -maxdepth 1 -type d -iname '*eggs' -printf '%f\n' \
           | grep -v -x -i -F -f "$CUR_DIRS" || true)

# ---------------------------------------------------------------------------
# 3. Sync each source independently
# ---------------------------------------------------------------------------

updated=()
skipped=()
failed=()
declare -A last_sha=()
declare -A new_sha=()

if [[ -f "$STATE_FILE" ]]; then
  while IFS=$'\t' read -r k v; do
    [[ -n "${k:-}" ]] && last_sha["$k"]="$v"
  done < <(jq -r 'to_entries[] | [ .key, .value ] | @tsv' "$STATE_FILE")
fi

while IFS=$'\t' read -r repo dir ref; do
  [[ -z "$repo" ]] && continue
  dir="${dir:-$repo}"
  url="https://github.com/${ORG}/${repo}.git"
  refspec="${ref:-HEAD}"

  if ! remote_sha="$(git ls-remote "$url" "$refspec" | awk 'NR==1 { print $1 }')" \
     || [[ -z "$remote_sha" ]]; then
    warn "::warning::could not resolve ${ORG}/${repo} (${refspec})"
    failed+=("$repo")
    continue
  fi

  # Skip unchanged upstreams that are already mirrored.
  if [[ -d "$dir" && "${last_sha[$repo]:-}" == "$remote_sha" ]]; then
    new_sha["$repo"]="$remote_sha"
    skipped+=("$repo")
    log "skipped (unchanged): ${repo} @ ${remote_sha:0:12}"
    continue
  fi

  echo "::group::sync ${repo} -> ${dir}/ @ ${remote_sha:0:12}"
  clone="$WORKDIR/$repo"
  if ! git clone --quiet --depth 1 ${ref:+--branch "$ref"} "$url" "$clone"; then
    warn "::warning::clone failed for ${ORG}/${repo}"
    failed+=("$repo")
    echo "::endgroup::"
    continue
  fi
  mkdir -p "$dir"
  rsync -a --delete --exclude='.git' "$clone/" "$dir/"
  rm -rf "$clone"
  new_sha["$repo"]="$remote_sha"
  updated+=("$repo")
  echo "::endgroup::"
done < "$ENTRIES"

# ---------------------------------------------------------------------------
# 4. Persist the state file (only current sources keep an entry)
# ---------------------------------------------------------------------------

state_tmp="$STATE_FILE.tmp"
if (( ${#new_sha[@]} )); then
  {
    for repo in "${!new_sha[@]}"; do
      printf '%s\t%s\n' "$repo" "${new_sha[$repo]}"
    done
  } | jq -R -s 'split("\n")
              | map(select(length > 0) | split("\t") | { (.[0]): .[1] })
              | add // {}' > "$state_tmp"
else
  printf '{}\n' > "$state_tmp"
fi
mv "$state_tmp" "$STATE_FILE"

# ---------------------------------------------------------------------------
# 5. Commit and push (skipped under DRY_RUN)
# ---------------------------------------------------------------------------

if [[ "${DRY_RUN:-0}" == "1" ]]; then
  log "DRY_RUN=1 -> skipping commit and push"
  git status --short | sed 's/^/  /'
else
  git add -A .
  if ! git diff --cached --quiet; then
    if (( ${#updated[@]} )); then
      subject="sync: $(IFS=,; echo "${updated[*]}")"
    else
      subject="sync: egg mirrors"
    fi
    {
      echo "$subject"
      echo
      echo "- updated: ${updated[*]:-none}"
      echo "- skipped (unchanged): ${skipped[*]:-none}"
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
    log "mirrors already up to date; nothing to commit"
  fi
fi

# ---------------------------------------------------------------------------
# 6. Job summary + exit status
# ---------------------------------------------------------------------------

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    echo "## Egg mirror sync (${ORG})"
    echo
    echo "| result | collections |"
    echo "|---|---|"
    echo "| updated | ${updated[*]:-none} |"
    echo "| skipped (unchanged) | ${skipped[*]:-none} |"
    echo "| failed | ${failed[*]:-none} |"
  } >> "$GITHUB_STEP_SUMMARY"
fi

if (( ${#failed[@]} > 0 )); then
  warn "warning: ${#failed[@]} source(s) failed: ${failed[*]}"
  exit 1
fi

log "done: updated=${#updated[@]} skipped=${#skipped[@]} failed=0"
