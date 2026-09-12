import { Blocks, Cpu, Database, Gamepad2, Layers, Package, Terminal } from "lucide-react";
import { catalogSeed } from "../lib/data";
import { PageShell } from "./PageShell";

const COLLECTION_ICONS: Record<string, typeof Database> = {
  "Database-Eggs": Database,
  "Minecraft-Eggs": Gamepad2,
  "Prog-Language-Eggs": Terminal,
  "Shell-Eggs": Blocks,
};

export default function AboutPage() {
  const { counts, generated_at } = catalogSeed;
  const generated = generated_at
    ? new Date(generated_at).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" })
    : "";

  return (
    <PageShell
      crumbs={["Catalog", "About"]}
      title="Every Multi Egg. One Nest."
      lead="The official catalog of PotenFYR Studios multi eggs: how it works, what it indexes, and how it stays current without anyone touching this repository."
      toc={[
        { id: "what", label: "What is the Nest?" },
        { id: "philosophy", label: "The multi-egg philosophy" },
        { id: "sync", label: "How the sync works" },
        { id: "collections", label: "Collections today" },
        { id: "studio", label: "PotenFYR Studios" },
      ]}
      prev={{ href: "/", label: "Catalog" }}
      next={{ href: "/docs", label: "Docs" }}
    >
      {/* What is the Nest */}
      <h2 id="what" className="doc-h2 mt-10">What is the Nest?</h2>
      <p>
        PotenFYR Nest is the official catalog of every multi egg published by{" "}
        <a className="doc-link" href="https://github.com/PotenFYR-Studios" target="_blank" rel="noopener">
          PotenFYR Studios
        </a>
        . It indexes each egg definition in the org's <code className="doc-code">*-Eggs</code> repositories, mirrors
        the verbatim JSON for direct download, and renders the whole collection as a searchable site at{" "}
        <a className="doc-link" href="https://nest.potenfyr.in" target="_blank" rel="noopener">
          nest.potenfyr.in
        </a>
        . Nothing on this page is hand-curated: the catalog is regenerated from the egg repositories themselves.
      </p>

      <div className="mt-6 grid grid-cols-2 gap-3.5 sm:grid-cols-4">
        {[
          { icon: Package, label: "collections", value: counts.collections, color: "text-violet-400" },
          { icon: Blocks, label: "multi eggs", value: counts.eggs, color: "text-pink-400" },
          { icon: Cpu, label: "variables", value: counts.variables, color: "text-sky-400" },
          { icon: Layers, label: "docker images", value: counts.images, color: "text-emerald-400" },
        ].map(({ icon: Icon, label, value, color }) => (
          <div
            key={label}
            className="rounded-2xl border border-white/10 bg-white/[0.02] p-4 text-center backdrop-blur-md"
          >
            <div className="mb-1 flex justify-center">
              <Icon className={`h-5 w-5 ${color}`} />
            </div>
            <div className="grad-text-canonical font-mono text-3xl font-extrabold">{value}</div>
            <span className="text-[11.5px] font-medium uppercase tracking-[1.4px] text-[#9aa0b4]">{label}</span>
          </div>
        ))}
      </div>

      {/* Multi-egg philosophy */}
      <h2 id="philosophy" className="doc-h2">The multi-egg philosophy</h2>
      <p>
        One egg per engine does not scale: you end up maintaining dozens of images and imports. A multi egg ships
        many engines or runtimes in a single Docker image and installs the one you pick on demand, so you get one
        download, one variable set and one update path:
      </p>
      <ul className="mt-3 list-disc space-y-2 pl-6 marker:text-[#8b5cf6]">
        <li>
          <strong className="text-[#e8eaf2]">Every database, one egg</strong>: MariaDB, MySQL, PostgreSQL, MongoDB,
          Redis, ClickHouse, Elasticsearch and 50+ more SQL, NoSQL, in-memory, vector, search, graph and
          object-storage engines, installed isolated inside the container on demand.
        </li>
        <li>
          <strong className="text-[#e8eaf2]">50+ languages, one egg</strong>: a full hosting platform image that
          installs, updates, compiles and runs 50+ programming languages per container.
        </li>
        <li>
          <strong className="text-[#e8eaf2]">Every Minecraft type, one egg</strong>: Vanilla, Paper, Spigot, Purpur,
          Folia, Fabric, Forge, NeoForge, Quilt, Velocity, BungeeCord, Bedrock and more, every version, every loader.
        </li>
      </ul>
      <p className="mt-3">
        The eggs target <strong className="text-[#e8eaf2]">Pterodactyl</strong>,{" "}
        <strong className="text-[#e8eaf2]">Pelican</strong> and <strong className="text-[#e8eaf2]">Feather Panel</strong>{" "}
        first, and run anywhere Docker runs: Wisp, PufferPanel, Jexactyl, Emerald, Kubernetes, Fly.io, Railway and
        Render. See the{" "}
        <a className="doc-link" href="/docs">
          docs
        </a>{" "}
        for install steps.
      </p>

      {/* Sync pipeline */}
      <h2 id="sync" className="doc-h2">How the sync works</h2>
      <p>
        The catalog is rebuilt by{" "}
        <a
          className="doc-link"
          href="https://github.com/PotenFYR-Studios/potenfyr-nest/blob/master/.github/workflows/sync.yml"
          target="_blank"
          rel="noopener"
        >
          <code className="doc-code">sync.yml</code>
        </a>
        , which runs <code className="doc-code">scripts/sync-eggs.sh</code> every 30 minutes (plus on every push to
        <code className="doc-code"> master</code> and on manual dispatch):
      </p>
      <ol className="mt-3 list-decimal space-y-2.5 pl-6 marker:font-mono marker:text-[#8b5cf6]">
        <li>
          <strong className="text-[#e8eaf2]">Discover sources.</strong> Every non-archived org repository named{" "}
          <code className="doc-code">*-Eggs</code> (or exactly <code className="doc-code">Eggs</code>) is discovered
          through the GitHub API; explicit entries in <code className="doc-code">egg-sources.json</code> override
          discovery and support pinned branches.
        </li>
        <li>
          <strong className="text-[#e8eaf2]">Harvest each collection.</strong> Per repository: one metadata API call
          and a shallow clone, strictly read-only, upstream is never written to. Any JSON file with a{" "}
          <code className="doc-code">name</code> and a <code className="doc-code">docker_images</code> object counts
          as an egg definition. Each collection syncs independently; a failing upstream is reported but never blocks
          the rest.
        </li>
        <li>
          <strong className="text-[#e8eaf2]">Write artifacts.</strong> Verbatim egg JSON into{" "}
          <code className="doc-code">public/eggs/&lt;Repo&gt;/</code>, the machine-readable catalog into{" "}
          <a className="doc-link" href="/data/catalog.json" target="_blank" rel="noopener">
            public/data/catalog.json
          </a>
          , and a typed seed module (<code className="doc-code">generated/catalog.seed.ts</code>) bundled into the
          site build.
        </li>
        <li>
          <strong className="text-[#e8eaf2]">Commit only on change.</strong> The catalog's timestamp is the newest
          upstream push, so identical upstreams produce byte-identical output: nothing is committed and Pages is not
          redeployed unless the catalog actually changed.
        </li>
        <li>
          <strong className="text-[#e8eaf2]">Build and deploy.</strong> Bun installs dependencies,{" "}
          <code className="doc-code">vite build</code> compiles the site,{" "}
          <code className="doc-code">scripts/prerender.mjs</code> bakes the catalog and JSON-LD into the initial HTML
          for crawlers, and the workflow deploys to GitHub Pages.
        </li>
        <li>
          <strong className="text-[#e8eaf2]">Stay live in the browser.</strong> On every page load the site fetches
          the synced catalog and then merges fresh org metadata (stars, descriptions, push times) from the GitHub
          API, re-pulling every five minutes while the page stays open.
        </li>
      </ol>
      <p className="mt-3">
        Last sync reflected upstream as of <span className="font-mono text-[#d8ccfe]">{generated}</span>.
      </p>

      {/* Collections */}
      <h2 id="collections" className="doc-h2">Collections today</h2>
      <p>Auto-discovered from the org: the table below renders straight from the generated catalog:</p>
      <div className="mt-4 overflow-x-auto rounded-xl border border-[rgba(139,92,246,0.16)]">
        <table className="w-full border-collapse text-left text-sm">
          <thead>
            <tr className="bg-[#1a1e32] text-[#e8eaf2]">
              <th className="px-4 py-2.5 font-semibold">Collection</th>
              <th className="px-4 py-2.5 font-semibold">About</th>
              <th className="px-4 py-2.5 text-center font-semibold">Eggs</th>
            </tr>
          </thead>
          <tbody>
            {catalogSeed.collections.map((c) => {
              const Icon = COLLECTION_ICONS[c.repo] ?? Blocks;
              return (
                <tr key={c.repo} className="border-t border-white/[0.08] transition-colors hover:bg-[rgba(139,92,246,0.06)]">
                  <td className="px-4 py-2.5 align-top">
                    <a
                      className="doc-link flex items-center gap-2 whitespace-nowrap font-mono"
                      href={c.url}
                      target="_blank"
                      rel="noopener"
                    >
                      <Icon className="h-4 w-4 shrink-0 text-[#8b5cf6]" />
                      {c.repo}
                    </a>
                  </td>
                  <td className="px-4 py-2.5 align-top text-[#b9bfd4]">{c.description}</td>
                  <td className="px-4 py-2.5 text-center align-top font-mono text-[#d8ccfe]">{c.eggs.length}</td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>

      {/* PotenFYR Studios */}
      <h2 id="studio" className="doc-h2">PotenFYR Studios</h2>
      <p>
        The Nest is maintained by PotenFYR Studios, the studio behind the multi eggs, AuthCore and a growing fleet of
        hosting and Minecraft tooling. Eggs and tools are published open source on{" "}
        <a className="doc-link" href="https://github.com/PotenFYR-Studios" target="_blank" rel="noopener">
          GitHub
        </a>{" "}
        and{" "}
        <a className="doc-link" href="https://modrinth.com/organization/potenfyr" target="_blank" rel="noopener">
          Modrinth
        </a>
        .
      </p>
      <div className="mt-5 flex flex-wrap gap-3">
        <a
          className="grad-bg inline-flex items-center gap-2 rounded-full px-5 py-2.5 text-sm font-bold text-white shadow-[0_4px_24px_rgba(236,72,153,0.35)] transition-transform hover:-translate-y-0.5"
          href="https://potenfyr.in"
          target="_blank"
          rel="noopener"
        >
          Visit potenfyr.in
        </a>
        <a
          className="inline-flex items-center gap-2 rounded-full border border-white/[0.08] bg-white/[0.03] px-5 py-2.5 text-sm font-bold text-[#e8eaf2] transition-transform hover:-translate-y-0.5 hover:bg-white/[0.07]"
          href="/docs"
        >
          Read the docs
        </a>
        <a
          className="inline-flex items-center gap-2 rounded-full border border-white/[0.08] bg-white/[0.03] px-5 py-2.5 text-sm font-bold text-[#e8eaf2] transition-transform hover:-translate-y-0.5 hover:bg-white/[0.07]"
          href="https://discord.com/invite/zUaN2FPBec"
          target="_blank"
          rel="noopener"
        >
          Join the Discord
        </a>
      </div>
    </PageShell>
  );
}
