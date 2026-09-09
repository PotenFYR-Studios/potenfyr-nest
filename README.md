# potenfyr-nest

Central mirror of every egg collection published by
[PotenFYR-Studios](https://github.com/PotenFYR-Studios), kept in sync
automatically from the org.

Nothing in the collection directories is written by hand. Each top-level
directory is an exact mirror of an upstream repo (minus `.git`), refreshed
by `.github/workflows/sync.yml`.

## Collections

Auto-discovered from the org (any repo whose name ends in `-Eggs`):

- [Database-Eggs](https://github.com/PotenFYR-Studios/Database-Eggs)
- [Prog-Language-Eggs](https://github.com/PotenFYR-Studios/Prog-Language-Eggs)
- [Minecraft-Eggs](https://github.com/PotenFYR-Studios/Minecraft-Eggs)

## Adding a new collection

Create a repository in the org named `Something-Eggs` — for example:

- `SteamCMD-Eggs`
- `ReverseShell-Eggs`
- `Shell-Eggs`
- `Proxies-Eggs`

That is the whole process. The next sync run (at most 30 minutes later)
discovers the repo, mirrors it into a top-level directory of the same name,
and commits it here. No change to this repository is required.

Repos that do not follow the naming convention, or that need a pinned
branch, go into `egg-sources.json` instead.

## egg-sources.json

```json
{
  "org": "PotenFYR-Studios",
  "exclude": ["Repo-To-Ignore"],
  "sources": [
    { "repo": "Oddly-Named-Repo", "dir": "Oddly-Named-Repo-Eggs", "ref": "develop" }
  ]
}
```

- `org` — org to discover and clone from.
- `exclude` — repo names (case-insensitive) never mirrored, even if discovered.
- `sources` — explicit entries; `repo` required, `dir` defaults to the repo
  name, `ref` defaults to the upstream default branch.

## How sync works

`scripts/sync-eggs.sh`, driven by `.github/workflows/sync.yml`:

- triggers: every 30 minutes, manual dispatch, and pushes to `main`
- resolves the source list = `egg-sources.json` entries + org discovery
- skips any repo whose upstream HEAD sha is unchanged since the last sync
  (tracked in `.egg-sync-state.json`) — idle runs take seconds, commit nothing
- mirrors each source with `rsync --delete`, so upstream deletions and
  renames propagate
- syncs each collection independently: a failing upstream is reported in
  the run summary and never blocks the others
- deletes mirror directories of repos removed from the org
- commits once and pushes with a rebase retry if `main` moved mid-run

Local use (after `gh auth login`):

```bash
bash scripts/sync-eggs.sh            # sync, commit and push
DRY_RUN=1 bash scripts/sync-eggs.sh  # sync only, no commit or push
```

## Layout

```
potenfyr-nest/
├── Database-Eggs/          mirror
├── Prog-Language-Eggs/     mirror
├── Minecraft-Eggs/         mirror
├── egg-sources.json        sync configuration (org, excludes, extra sources)
├── scripts/sync-eggs.sh    sync implementation
├── .egg-sync-state.json    last-synced upstream shas (managed by the script)
└── .github/workflows/sync.yml
```
