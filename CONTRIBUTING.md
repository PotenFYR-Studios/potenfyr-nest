# Contributing to PotenFYR Nest

Thanks for helping grow the nest. There are two very different ways to
contribute, and it matters which one you pick:

1. **Egg contributions** (new eggs, engine support, variable changes) happen
   in the org's `*-Eggs` repositories, **never** in this repo. The nest is a
   generated catalog; it has no egg definitions of its own.
2. **Site and pipeline contributions** (the catalog website, sync script,
   workflow, docs) happen here.

## 🥚 Contributing an egg

Eggs live in the collection repositories:

- [Database-Eggs](https://github.com/PotenFYR-Studios/Database-Eggs)
- [Minecraft-Eggs](https://github.com/PotenFYR-Studios/Minecraft-Eggs)
- [Prog-Language-Eggs](https://github.com/PotenFYR-Studios/Prog-Language-Eggs)
- [Shell-Eggs](https://github.com/PotenFYR-Studios/Shell-Eggs)

Flow:

1. Fork the collection your egg belongs to.
2. Add your egg JSON anywhere in the repository. Any `*.json` file with a
   `name` (string) and a `docker_images` (object) is picked up automatically
   as an egg definition; filename and folder don't matter.
3. Open a pull request against that collection repo.

Once merged, the next sync run (at most 30 minutes later) mirrors the JSON
into `public/eggs/`, rebuilds the catalog and redeploys
[nest.potenfyr.in](https://nest.potenfyr.in); no changes are needed in the
nest repo itself.

Egg JSON format: standard Pterodactyl `PTDL_v2` egg definitions, imported
unchanged by Pelican and Feather Panel. See real examples at
[/examples](https://nest.potenfyr.in/examples) and each collection's README
for the full variable reference.

### Testing eggs locally before a PR

Each collection repo ships runnable scripts (`Dockerfile`, `entrypoint.sh`,
`run.sh`, `tests/`). With Docker installed:

```bash
git clone https://github.com/PotenFYR-Studios/<Collection>.git
cd <Collection>
docker build -t <collection-test> .
# exercise the entrypoint the way the egg's startup command would:
docker run --rm -e DATABASE_TYPE=mariadb -e DB_VERSION=latest <collection-test>
```

Replace the env vars with the ones your egg change touches. If the repo has
a `tests/` directory, run what's in there too.

### New collections

Create an org repo named `Something-Eggs` and the sync discovers it
automatically. Repos outside that naming convention, or needing a pinned
branch, are registered in `egg-sources.json` (see the README).

## 🌐 Contributing to the site / pipeline

The site is React 19 + TypeScript + Vite 7 + Tailwind v4, built with Bun.

```bash
bun install          # install dependencies
bun run dev          # dev server on http://localhost:5173
bun run build        # typecheck (tsc -b) + production build to dist/
bun run preview      # serve the production build locally
```

Two generated files must never be edited by hand; they are overwritten by
every sync run:

- `public/data/catalog.json` and `public/eggs/**` (by `scripts/sync-eggs.sh`)
- `generated/catalog.seed.ts` (same script)

To regenerate locally after `gh auth login`:

```bash
DRY_RUN=1 bash scripts/sync-eggs.sh   # regenerate without committing
```

Per-page HTML (`/about`, `/docs`, `/examples`) is emitted by the
`multiPageEmit` plugin in `vite.config.ts`: add new routes there and a
matching page component under `src/pages/`, wired in `src/App.tsx`.

### Ground rules

- Keep the design system: deep-navy `#0b0d14` surfaces, violet/pink/orange
  gradients, Fira Code micro-labels, sticky 56px navbar, three-zone footer.
- Keep landing Magic UI effects on the landing page only.
- Respect `prefers-reduced-motion`; the site is dark-only.
- Never commit secrets, tokens or real credentials; entrypoints must not
  hardcode any.

## 📜 License

By contributing, you agree that your contributions are licensed under the
Apache License 2.0 with the Commons Clause, matching the repository
[LICENSE](LICENSE).

## 📫 Questions?

Ask in the [Support Discord](https://discord.com/invite/zUaN2FPBec) or open
a [question issue](https://github.com/PotenFYR-Studios/potenfyr-nest/issues/new?template=question.yml).
Security concerns go through [SECURITY.md](SECURITY.md) only.
