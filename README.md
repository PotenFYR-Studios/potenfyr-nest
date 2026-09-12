<!-- markdownlint-disable -->
<div align="center">

<img src="https://capsule-render.vercel.app/api?type=waving&color=0:8b5cf6,50:ec4899,100:f97316&height=220&section=header&text=PotenFYR%20Nest&fontSize=52&fontColor=ffffff&fontAlignY=34&animation=twinkling" width="100%" alt="PotenFYR Nest banner"/>

[![Typing SVG](https://readme-typing-svg.demolab.com?font=Fira+Code&weight=600&size=20&pause=1200&color=8B5CF6&center=true&vCenter=true&width=800&lines=One+multi+egg+does+the+work+of+dozens;Every+database.+50%2B+languages.+Every+Minecraft+type.;Synced+from+the+org+every+30+minutes;Download+the+JSON+and+drop+it+into+your+panel.)](https://github.com/PotenFYR-Studios)

[![Sync](https://img.shields.io/github/actions/workflow/status/PotenFYR-Studios/potenfyr-nest/sync.yml?style=for-the-badge&logo=githubactions&label=Auto-Sync&labelColor=1c1e26&color=2ea043)](https://github.com/PotenFYR-Studios/potenfyr-nest/actions/workflows/sync.yml)
[![Live Site](https://img.shields.io/website?url=https%3A%2F%2Fnest.potenfyr.in%2F&style=for-the-badge&logo=githubpages&label=Live%20Site&labelColor=1c1e26&color=8b5cf6)](https://nest.potenfyr.in/)
[![Discord](https://img.shields.io/badge/Discord-Join%20us-5865F2?style=for-the-badge&logo=discord&logoColor=white&labelColor=1c1e26)](https://discord.com/invite/zUaN2FPBec)
[![Modrinth](https://img.shields.io/badge/Modrinth-potenfyr-1bd96a?style=for-the-badge&logo=modrinth&logoColor=white&labelColor=1c1e26)](https://modrinth.com/organization/potenfyr)
[![License](https://img.shields.io/badge/License-Apache--2.0%20%2B%20Commons%20Clause-f97316?style=for-the-badge&logo=apache&logoColor=white&labelColor=1c1e26)](LICENSE)
[![View](https://komarev.com/ghpvc/?username=PotenFYR-Studios-potenfyr-nest&color=ec4899&style=for-the-badge&label=VIEW&labelColor=1c1e26)](https://github.com/PotenFYR-Studios/potenfyr-nest)

</div>

# 🥚 PotenFYR Nest

**One nest for every multi egg.** This repository is the official catalog and
website hub of [PotenFYR-Studios](https://github.com/PotenFYR-Studios). Our
egg collections follow one philosophy: **a single egg does the work of
dozens**. Instead of shipping a separate egg per engine, each multi egg
carries every engine in one image and installs the one you pick on demand.

> 💡 **Everything here syncs itself.** A GitHub Actions workflow rediscovers
> every `*-Eggs` repo in the org every 30 minutes, mirrors each egg JSON into
> [`public/eggs/`](public/eggs), rebuilds
> [`public/data/catalog.json`](public/data/catalog.json), refreshes this
> README and redeploys the [live site](https://nest.potenfyr.in/).
> The site also pulls stars and push times **live from the GitHub API** on
> every page load. New eggs appear everywhere automatically, with zero edits
> to this repository.

<!-- NEST:START:stats -->
> 🥚 **4** collections · **4** eggs · **127** variables: generated `2026-09-12T21:16:05Z`, refreshed by every sync run.
<!-- NEST:END:stats -->

## 🪄 Why multi eggs?

One egg per engine does not scale: you end up maintaining dozens of images.
A multi egg gives you one download, one variable set and one update path:

- **Every database, one egg** · MariaDB, MySQL, PostgreSQL, MongoDB, Redis,
  ClickHouse, Elasticsearch, and 50+ more SQL, NoSQL, in-memory, vector,
  search, graph and object-storage engines, installed isolated inside the
  container on demand.
- **50+ languages, one egg** · a full hosting platform image that installs,
  updates, compiles and runs 50+ programming languages per container.
- **Every Minecraft type, one egg** · Vanilla, Paper, Spigot, Purpur, Folia,
  Fabric, Forge, NeoForge, Quilt, Velocity, BungeeCord, Bedrock and more,
  every version, every loader.

## 🖥️ Runs on your panel

Built for **Pterodactyl**, **Pelican** and **Feather Panel**, and compatible
with Wisp, PufferPanel, Jexactyl, Emerald, plain Docker, Kubernetes, Fly.io,
Railway and Render.

### 📦 Collections

Auto-discovered from the org (any repo whose name ends in `-Eggs`):

<!-- NEST:START:catalog -->
| 🗂️ Collection | About | Stars | Last push |
|:---|:---|:---:|:---:|
| [Database-Eggs](https://github.com/PotenFYR-Studios/Database-Eggs) | One egg. Every database. Every version. Every panel. Production-ready multi-database eggs for Pterodactyl, Pelican, Feather, Wisp, and Docker. | [![Stars](https://img.shields.io/github/stars/PotenFYR-Studios/Database-Eggs?style=flat-square&logo=github&labelColor=1c1e26&color=eac54f)](https://github.com/PotenFYR-Studios/Database-Eggs/stargazers) | [![Last push](https://img.shields.io/github/last-commit/PotenFYR-Studios/Database-Eggs?style=flat-square&logo=git&labelColor=1c1e26&color=2ea043)](https://github.com/PotenFYR-Studios/Database-Eggs/commits) |
| [Minecraft-Eggs](https://github.com/PotenFYR-Studios/Minecraft-Eggs) | Universal Minecraft egg for Pterodactyl, Pelican, and Feather Panel. Supports Vanilla, Paper, Purpur, Fabric, Forge, NeoForge, Velocity, Bedrock, and all 18+ server types. | [![Stars](https://img.shields.io/github/stars/PotenFYR-Studios/Minecraft-Eggs?style=flat-square&logo=github&labelColor=1c1e26&color=eac54f)](https://github.com/PotenFYR-Studios/Minecraft-Eggs/stargazers) | [![Last push](https://img.shields.io/github/last-commit/PotenFYR-Studios/Minecraft-Eggs?style=flat-square&logo=git&labelColor=1c1e26&color=2ea043)](https://github.com/PotenFYR-Studios/Minecraft-Eggs/commits) |
| [Prog-Language-Eggs](https://github.com/PotenFYR-Studios/Prog-Language-Eggs) | One egg. One image. Every language. A production-grade hosting platform that installs, updates, compiles and runs 50+ programming languages inside your container - across Pterodactyl, Pelican, Feather Panel, PufferPanel, Jexactyl, Wisp, Emerald, Kubernetes, Fly.io, Railway, Render | [![Stars](https://img.shields.io/github/stars/PotenFYR-Studios/Prog-Language-Eggs?style=flat-square&logo=github&labelColor=1c1e26&color=eac54f)](https://github.com/PotenFYR-Studios/Prog-Language-Eggs/stargazers) | [![Last push](https://img.shields.io/github/last-commit/PotenFYR-Studios/Prog-Language-Eggs?style=flat-square&logo=git&labelColor=1c1e26&color=2ea043)](https://github.com/PotenFYR-Studios/Prog-Language-Eggs/commits) |
| [Shell-Eggs](https://github.com/PotenFYR-Studios/Shell-Eggs) | Host any shell - incoming, tunneled, reversed, encrypted, covert, web or debug - from one panel egg. Credentials are the only mandatory input. Everything else is optional. | [![Stars](https://img.shields.io/github/stars/PotenFYR-Studios/Shell-Eggs?style=flat-square&logo=github&labelColor=1c1e26&color=eac54f)](https://github.com/PotenFYR-Studios/Shell-Eggs/stargazers) | [![Last push](https://img.shields.io/github/last-commit/PotenFYR-Studios/Shell-Eggs?style=flat-square&logo=git&labelColor=1c1e26&color=2ea043)](https://github.com/PotenFYR-Studios/Shell-Eggs/commits) |
<!-- NEST:END:catalog -->

Each egg row links its definition and there is always a **⬇ egg.json**
download on the site card. Verbatim copies live in
[`public/eggs/<Collection>/`](public/eggs).

## 🌐 Website

**https://nest.potenfyr.in**: the root of this repo **is** the site:
React 19 + TypeScript + Vite, styled with Tailwind v4 and
[Magic UI](https://magicui.design) components (Magic Card, Border Beam,
Number Ticker, Marquee, Meteors, Dot Pattern, Shine Border), built with Bun
and deployed to GitHub Pages by the sync workflow.

- prerendered catalog and JSON-LD ship in the initial HTML (SEO + AI search)
- live stars, descriptions and push times from the GitHub API on every visit
- search across eggs, variables and engines; per-collection filters
- one-click `egg.json` download per card, straight from this repo
- `/about` · `/docs` · `/examples` pages with per-route SEO meta and JSON-LD
- relative asset paths only, so a future custom domain needs no code change

## 🚀 Getting started

```bash
bun install                # install dependencies
bun run dev                # dev server on http://localhost:5173
bun run build              # typecheck + production build to dist/
bun run preview            # serve the production build locally
```

## 🔄 How sync works

`scripts/sync-eggs.sh`, driven by `.github/workflows/sync.yml`:

- triggers: every 30 minutes, manual dispatch, pushes to `master`
- resolves the source list: `egg-sources.json` entries + org discovery
- fetches each collection's metadata and a shallow clone (read-only,
  upstream repos are never written to)
- mirrors every egg definition verbatim into `public/eggs/<Repo>/`
- rebuilds `public/data/catalog.json` and `generated/catalog.seed.ts`
- refreshes the `NEST:START/END` blocks in this README
- each collection syncs independently; a failing upstream never blocks the rest
- output is deterministic: unchanged upstreams commit nothing, and Pages
  redeploys only when the catalog actually changed

Local use (after `gh auth login`):

```bash
bash scripts/sync-eggs.sh            # regenerate everything, commit and push
DRY_RUN=1 bash scripts/sync-eggs.sh  # regenerate only, no commit or push
```

## ➕ Adding a new egg or collection

Create a repository in the org named `Something-Eggs`, for example
`SteamCMD-Eggs`, `Shell-Eggs` or `Proxies-Eggs`. That is the whole process.
The next sync run (at most 30 minutes later) discovers the repo, mirrors its
egg JSON, updates the catalog, README and site. Any `*.json` file containing
a `name` and a `docker_images` object is picked up as an egg definition,
whatever the filename or folder.

To improve an existing egg, open a pull request in its `*-Eggs` collection,
see [CONTRIBUTING.md](CONTRIBUTING.md) for the full flow, local test commands
and conventions.

Repos that do not follow the naming convention, or that need a pinned
branch, go into `egg-sources.json` instead.

## ⚙️ egg-sources.json

```json
{
  "org": "PotenFYR-Studios",
  "exclude": ["Repo-To-Ignore"],
  "sources": [
    { "repo": "Oddly-Named-Repo", "dir": "Oddly-Named-Repo-Eggs", "ref": "develop" }
  ]
}
```

- `org` · org to discover and harvest from
- `exclude` · repo names (case-insensitive) never cataloged
- `sources` · explicit entries; `repo` required, `dir` defaults to the repo
  name, `ref` defaults to the upstream default branch

## 🗂️ Layout

```
potenfyr-nest/
├── index.html                     site shell (SEO meta, OG tags)
├── src/                           React 19 + TypeScript app
│   ├── App.tsx                    path router (/ · /about · /docs · /examples)
│   ├── pages/                     Landing (catalog UI), About, Docs, Examples
│   ├── components/Chrome.tsx      sticky 56px navbar + three-zone footer
│   ├── components/EggCard.tsx     egg card (download + upstream links)
│   ├── components/StructuredData.tsx  JSON-LD (Organization, WebSite, apps, FAQ)
│   └── lib/                       data access, live GitHub refresh, types
├── public/
│   ├── CNAME                      nest.potenfyr.in (GitHub Pages)
│   ├── data/catalog.json          auto-generated catalog
│   ├── eggs/<Repo>/*.json         verbatim egg definitions (mirrored)
│   ├── og.png                     social preview card
│   └── robots.txt · llms.txt · sitemap.xml
├── generated/catalog.seed.ts      typed seed module (bundled at build)
├── scripts/
│   ├── sync-eggs.sh               catalog + mirror + README generator
│   ├── generate-og.py             OG image generator
│   └── prerender.mjs              bakes catalog + JSON-LD into dist HTML
├── egg-sources.json               sync configuration
└── .github/workflows/sync.yml     30-minute sync + Bun build + Pages deploy
```

## 🔍 SEO

Search and AI-answer engines are first-class here:

- full meta, Open Graph and Twitter card set with a generated 1200x630
  preview (`public/og.png`, regenerate with `python3 scripts/generate-og.py`)
- JSON-LD: Organization, WebSite, SoftwareApplication per egg, FAQPage, plus
  per-route AboutPage/WebPage/ItemList and breadcrumbs on every page
- prerendered HTML so crawlers read the full catalog without JavaScript
- `robots.txt` explicitly welcoming search and AI crawlers, `llms.txt` for
  attribution-friendly AI retrieval, `sitemap.xml`, canonical URLs
- semantic HTML landmarks and FAQ content matched to real search intent

## 🤝 Contributing

Egg contributions happen in the `*-Eggs` repositories (the nest picks them
up automatically). For site changes, sync-script changes and conventions,
read [CONTRIBUTING.md](CONTRIBUTING.md). Security concerns go through
[SECURITY.md](SECURITY.md): please do not open public issues for
vulnerabilities.

## 📜 Licensing

This repository is licensed under the **Apache License 2.0 with the
Commons Clause** (free to fork, modify and use, and to build around; not to
sell as a product). Egg definitions keep their upstream licenses where
applicable. See each repository's
[LICENSE](https://github.com/PotenFYR-Studios/potenfyr-nest/blob/master/LICENSE)
for details; **the LICENSE file is authoritative**, not this summary.

[![Commit activity](https://img.shields.io/github/commit-activity/m/PotenFYR-Studios/potenfyr-nest?style=flat-square&logo=git&labelColor=1c1e26&color=2ea043)](https://github.com/PotenFYR-Studios/potenfyr-nest/commits/master)
[![Last commit](https://img.shields.io/github/last-commit/PotenFYR-Studios/potenfyr-nest/master?style=flat-square&logo=git&labelColor=1c1e26&color=8b5cf6)](https://github.com/PotenFYR-Studios/potenfyr-nest/commits/master)

---

## 🌍 PotenFYR Studios Community

Contributions make the open-source community such an amazing place to learn, inspire and create. Any contributions you make are **greatly appreciated** - see [CONTRIBUTING.md](CONTRIBUTING.md) and the [good first issues](https://github.com/PotenFYR-Studios/potenfyr-nest/labels/good%20first%20issue). Security concerns: please use [SECURITY.md](SECURITY.md) (private vulnerability reporting), not public issues.

<a href="https://github.com/PotenFYR-Studios/potenfyr-nest/graphs/contributors">
  <img src="https://contrib.rocks/image?repo=PotenFYR-Studios/potenfyr-nest" alt="potenfyr-nest contributors" />
</a>
<a href="https://github.com/PotenFYR-Studios/potenfyr-nest/stargazers">
  <img src="https://img.shields.io/github/stars/PotenFYR-Studios/potenfyr-nest?style=social&label=Stars" alt="Live star count" />
</a>
<a href="https://github.com/PotenFYR-Studios/potenfyr-nest/network/members">
  <img src="https://img.shields.io/github/forks/PotenFYR-Studios/potenfyr-nest?style=social&label=Forks" alt="Live fork count" />
</a>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/PotenFYR-Studios/FYRwall/output/github-snake-dark.svg" />
  <source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/PotenFYR-Studios/FYRwall/output/github-snake.svg" />
  <img alt="Contribution snake animation" src="https://raw.githubusercontent.com/PotenFYR-Studios/FYRwall/output/github-snake.svg" width="100%" />
</picture>

---

## ⭐ Star History

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=potenfyr-studios/authcore,potenfyr-studios/statfyr,potenfyr-studios/discord-botlists,potenfyr-studios/shell-eggs,potenfyr-studios/prog-language-eggs,potenfyr-studios/minecraft-eggs,potenfyr-studios/database-eggs,potenfyr-studios/apicordon,potenfyr-studios/ojaj,potenfyr-studios/fyrwall,potenfyr-studios/echoingdeaths&type=Date&theme=dark" />
  <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=potenfyr-studios/authcore,potenfyr-studios/statfyr,potenfyr-studios/discord-botlists,potenfyr-studios/shell-eggs,potenfyr-studios/prog-language-eggs,potenfyr-studios/minecraft-eggs,potenfyr-studios/database-eggs,potenfyr-studios/apicordon,potenfyr-studios/ojaj,potenfyr-studios/fyrwall,potenfyr-studios/echoingdeaths&type=Date" />
  <img alt="Star history chart for all PotenFYR Studios public repositories" src="https://api.star-history.com/svg?repos=potenfyr-studios/authcore,potenfyr-studios/statfyr,potenfyr-studios/discord-botlists,potenfyr-studios/shell-eggs,potenfyr-studios/prog-language-eggs,potenfyr-studios/minecraft-eggs,potenfyr-studios/database-eggs,potenfyr-studios/apicordon,potenfyr-studios/ojaj,potenfyr-studios/fyrwall,potenfyr-studios/echoingdeaths&type=Date" width="80%" />
</picture>

Every public PotenFYR Studios repository on one live chart, served by [star-history.com](https://star-history.com).

---

<div align="center">

### 📫 Connect With Us

[![GitHub](https://img.shields.io/badge/GitHub-PotenFYR--Studios-181717?style=for-the-badge&logo=github&labelColor=1c1e26)](https://github.com/PotenFYR-Studios)
[![Website](https://img.shields.io/badge/Website-potenfyr.in-8b5cf6?style=for-the-badge&logo=googlechrome&logoColor=white&labelColor=1c1e26)](https://potenfyr.in)
[![Community](https://img.shields.io/badge/Community-Discord-5865F2?style=for-the-badge&logo=discord&logoColor=white&labelColor=1c1e26)](https://discord.com/invite/zUaN2FPBec)
[![Support](https://img.shields.io/badge/Support-Server-5865F2?style=for-the-badge&logo=discord&logoColor=white&labelColor=1c1e26)](https://discord.com/invite/PRJASTKqwD)
[![Modrinth](https://img.shields.io/badge/Modrinth-Organization-1bd96a?style=for-the-badge&logo=modrinth&logoColor=white&labelColor=1c1e26)](https://modrinth.com/organization/potenfyr)

<sub>🥚 Every multi egg. One nest. Synced every 30 minutes by [GitHub Actions](https://github.com/PotenFYR-Studios/potenfyr-nest/actions/workflows/sync.yml).</sub>

<img src="https://capsule-render.vercel.app/api?type=waving&color=0:f97316,50:ec4899,100:8b5cf6&height=120&section=footer&text=Made%20with%20%E2%9D%A4%EF%B8%8F%20by%20PotenFYR%20Studios&fontSize=22&fontColor=ffffff&animation=twinkling" width="100%" alt="footer"/>

</div>
<!-- markdownlint-enable -->
