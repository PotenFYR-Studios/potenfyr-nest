import { Search, LayoutGrid, ListFilter, ScanSearch, Download } from "lucide-react";
import { CodeBlock } from "../components/CodeBlock";
import { PageShell } from "./PageShell";

const CURL_EXAMPLE = `curl -sSL -o egg-database-multi.json \\
  "https://raw.githubusercontent.com/PotenFYR-Studios/Database-Eggs/main/egg-database-multi.json"`;

const DOCKER_EXAMPLE = `docker run -d --name mydb \\
  -e DATABASE_TYPE=mariadb \\
  -e DB_VERSION=latest \\
  -p 3306:3306 \\
  ghcr.io/potenfyr-studios/database-eggs:latest`;

const IMAGES: Array<[string, string, string]> = [
  ["Multi Database", "ghcr.io/potenfyr-studios/database-eggs:latest", "https://github.com/PotenFYR-Studios/Database-Eggs"],
  ["Multi Minecraft", "ghcr.io/potenfyr-studios/minecraft-eggs:latest", "https://github.com/PotenFYR-Studios/Minecraft-Eggs"],
  ["Prog-Language", "ghcr.io/potenfyr-studios/prog-language-eggs:latest", "https://github.com/PotenFYR-Studios/Prog-Language-Eggs"],
];

export default function DocsPage() {
  return (
    <PageShell
      crumbs={["Catalog", "Docs"]}
      title="Using the Nest"
      lead="Browse and inspect the multi egg catalog, install an egg on Pterodactyl, Pelican or Feather Panel, read the egg JSON format, and ship your own egg."
      toc={[
        { id: "browse", label: "Browse the catalog" },
        { id: "install", label: "Install an egg" },
        { id: "docker", label: "Run on Docker" },
        { id: "format", label: "Egg JSON format" },
        { id: "contribute", label: "Contribute an egg" },
        { id: "license", label: "License" },
      ]}
      prev={{ href: "/about", label: "About" }}
      next={{ href: "/examples", label: "Examples" }}
    >
      {/* Browse */}
      <h2 id="browse" className="doc-h2 mt-10">Browse the catalog</h2>
      <p>
        The{" "}
        <a className="doc-link" href="/">
          catalog page
        </a>{" "}
        renders every egg from the synced catalog. Controls:
      </p>
      <ul className="mt-3 list-disc space-y-2 pl-6 marker:text-[#8b5cf6]">
        <li>
          <Search className="mr-1 inline h-4 w-4 text-[#8b5cf6]" aria-hidden />
          <strong className="text-[#e8eaf2]">Search</strong> matches egg names, descriptions, variable names and env
          vars, engine names and Docker image URIs, try <code className="doc-code">redis</code> or{" "}
          <code className="doc-code">SERVER_TYPE</code>.
        </li>
        <li>
          <strong className="text-[#e8eaf2]">Category tabs</strong> filter by collection: Databases, Minecraft,
          Languages, or everything at once.
        </li>
        <li>
          <LayoutGrid className="mr-1 inline h-4 w-4 text-[#8b5cf6]" aria-hidden />
          <strong className="text-[#e8eaf2]">Grid</strong> shows a balanced three-column matrix;{" "}
          <ListFilter className="mr-1 inline h-4 w-4 text-[#8b5cf6]" aria-hidden />
          <strong className="text-[#e8eaf2]">Showcase</strong> groups full-width cards per collection.
        </li>
        <li>
          <ScanSearch className="mr-1 inline h-4 w-4 text-[#8b5cf6]" aria-hidden />
          <strong className="text-[#e8eaf2]">Inspect</strong> an egg card to open the detail modal: every variable
          with its env var and default, the Docker image list, startup command, features and sync metadata.
        </li>
        <li>
          <Download className="mr-1 inline h-4 w-4 text-[#8b5cf6]" aria-hidden />
          <strong className="text-[#e8eaf2]">Download</strong> buttons fetch the verbatim egg JSON, mirrored in this
          repository under <code className="doc-code">/eggs/&lt;Collection&gt;/</code> and linked back to the source
          repo.
        </li>
      </ul>
      <p className="mt-3">
        Star counts, descriptions and push times are refreshed live from the GitHub API; everything else comes from
        the catalog synced every 30 minutes.
      </p>

      {/* Install */}
      <h2 id="install" className="doc-h2">Install an egg in your panel</h2>
      <ol className="list-decimal space-y-2.5 pl-6 marker:font-mono marker:text-[#8b5cf6]">
        <li>
          Grab the egg JSON: download it from any card on the{" "}
          <a className="doc-link" href="/">
            catalog
          </a>
          , or pull it straight from the source repo:
          <div className="mt-3">
            <CodeBlock code={CURL_EXAMPLE} label="shell" filename="fetch the Multi Database egg" />
          </div>
        </li>
        <li>
          In your panel's admin area, open <strong className="text-[#e8eaf2]">Nests</strong>, pick (or create) a nest
          and use its <strong className="text-[#e8eaf2]">egg import</strong> option: upload the JSON file, or paste
          its raw URL:
          <code className="doc-code ml-1">
            https://raw.githubusercontent.com/PotenFYR-Studios/&lt;Collection&gt;/main/&lt;egg&gt;.json
          </code>
          . This works the same on Pterodactyl, Pelican and Feather Panel.
        </li>
        <li>
          Create a server from the imported egg and set the variables you care about, e.g.{" "}
          <code className="doc-code">DATABASE_TYPE</code> + <code className="doc-code">DB_VERSION</code>,{" "}
          <code className="doc-code">SERVER_TYPE</code>, or <code className="doc-code">LANGUAGE</code>. Anything left
          on its default stays on a sensible default (<code className="doc-code">latest</code> auto-resolves).
        </li>
        <li>
          Start the server. The image installs only what you selected, isolated inside the container; switching
          engines or major versions never deletes previous data.
        </li>
      </ol>
      <p className="mt-3">
        Every variable, default and startup option is documented in each collection's README on GitHub.
      </p>

      {/* Docker */}
      <h2 id="docker" className="doc-h2">Run the image on plain Docker</h2>
      <p>
        The same images that power the eggs are published on GHCR and can be run directly; the egg's environment
        variables drive the on-demand installer:
      </p>
      <div className="mt-4">
        <CodeBlock code={DOCKER_EXAMPLE} label="shell" filename="Multi Database, MariaDB latest" />
      </div>
      <div className="mt-4 overflow-x-auto rounded-xl border border-[rgba(139,92,246,0.16)]">
        <table className="w-full border-collapse text-left text-sm">
          <thead>
            <tr className="bg-[#1a1e32] text-[#e8eaf2]">
              <th className="px-4 py-2.5 font-semibold">Egg</th>
              <th className="px-4 py-2.5 font-semibold">Image</th>
            </tr>
          </thead>
          <tbody>
            {IMAGES.map(([name, image, url]) => (
              <tr key={image} className="border-t border-white/[0.08] transition-colors hover:bg-[rgba(139,92,246,0.06)]">
                <td className="px-4 py-2.5 align-top font-semibold text-[#e8eaf2]">{name}</td>
                <td className="px-4 py-2.5 align-top font-mono text-[12.5px] text-[#d8ccfe]">
                  <a className="doc-link" href={url} target="_blank" rel="noopener">
                    {image}
                  </a>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {/* Format */}
      <h2 id="format" className="doc-h2">The egg JSON format</h2>
      <p>
        Eggs are standard Pterodactyl egg definitions (<code className="doc-code">meta.version: PTDL_v2</code>),
        which Pelican and Feather import unchanged. The fields that matter:
      </p>
      <div className="mt-4 overflow-x-auto rounded-xl border border-[rgba(139,92,246,0.16)]">
        <table className="w-full border-collapse text-left text-sm">
          <thead>
            <tr className="bg-[#1a1e32] text-[#e8eaf2]">
              <th className="px-4 py-2.5 font-semibold">Field</th>
              <th className="px-4 py-2.5 font-semibold">Meaning</th>
            </tr>
          </thead>
          <tbody>
            {[
              ["name", "Display name of the egg."],
              ["docker_images", "Named image options; the container your server runs on."],
              ["variables[]", "Panel-facing knobs: name, env_variable, default_value (plus validation)."],
              ["startup", "The command the daemon runs to boot your selection."],
              ["config", "Daemon parsing rules: startup detection, file templates, port allocation."],
              ["features", "Panel feature flags such as eula, java_version, pid_limit."],
            ].map(([field, meaning]) => (
              <tr key={field} className="border-t border-white/[0.08] transition-colors hover:bg-[rgba(139,92,246,0.06)]">
                <td className="px-4 py-2.5 align-top font-mono text-[12.5px] text-[#d8ccfe]">{field}</td>
                <td className="px-4 py-2.5 align-top text-[#b9bfd4]">{meaning}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <p className="mt-3">
        Real annotated snippets from all three collections live on the{" "}
        <a className="doc-link" href="/examples">
          examples page
        </a>
        .
      </p>

      {/* Contribute */}
      <h2 id="contribute" className="doc-h2">Contribute an egg</h2>
      <p>
        Eggs live in the org's <code className="doc-code">*-Eggs</code> repositories; the Nest never stores
        definitions of its own. To contribute:
      </p>
      <ol className="mt-3 list-decimal space-y-2 pl-6 marker:font-mono marker:text-[#8b5cf6]">
        <li>
          Fork the collection your egg belongs to (
          <a className="doc-link" href="https://github.com/PotenFYR-Studios/Database-Eggs" target="_blank" rel="noopener">
            Database-Eggs
          </a>
          ,{" "}
          <a className="doc-link" href="https://github.com/PotenFYR-Studios/Minecraft-Eggs" target="_blank" rel="noopener">
            Minecraft-Eggs
          </a>
          ,{" "}
          <a className="doc-link" href="https://github.com/PotenFYR-Studios/Prog-Language-Eggs" target="_blank" rel="noopener">
            Prog-Language-Eggs
          </a>
          , …).
        </li>
        <li>
          Add your egg JSON anywhere in the repository: any file with a <code className="doc-code">name</code> and a{" "}
          <code className="doc-code">docker_images</code> object is picked up automatically, whatever the filename or
          folder.
        </li>
        <li>
          Open a pull request. Once merged, the next sync run (at most 30 minutes later) mirrors the JSON, rebuilds
          the catalog and redeploys this site, no changes needed in the nest repository itself.
        </li>
      </ol>
      <p className="mt-3">
        Repos outside the <code className="doc-code">*-Eggs</code> naming, or needing a pinned branch, are registered
        in <code className="doc-code">egg-sources.json</code>. For build scripts and Dockerfile conventions, see{" "}
        <a
          className="doc-link"
          href="https://github.com/PotenFYR-Studios/potenfyr-nest/blob/master/CONTRIBUTING.md"
          target="_blank"
          rel="noopener"
        >
          CONTRIBUTING.md
        </a>
        . Questions? Ask in the{" "}
        <a className="doc-link" href="https://discord.com/invite/zUaN2FPBec" target="_blank" rel="noopener">
          Support Discord
        </a>
        .
      </p>
      {/* License */}
      <h2 id="license" className="doc-h2">
        License
      </h2>
      <p>
        The nest and everything it serves are released under the Apache License 2.0 with the Commons Clause: free
        software with a single restriction. In plain terms, you can:
      </p>
      <ul className="mt-3 list-disc space-y-2 pl-6 marker:text-[#8b5cf6]">
        <li>fork, modify, run and self-host it, for any purpose, commercial use included;</li>
        <li>redistribute it, original or modified, as long as the license notices stay attached;</li>
        <li>build products, panels and services on top of it and around it.</li>
      </ul>
      <p className="mt-3">The short list of things you cannot do:</p>
      <ul className="mt-3 list-disc space-y-2 pl-6 marker:text-[#8b5cf6]">
        <li>
          sell the software itself, or charge for a product or service whose value comes entirely or substantially
          from the software's own functionality (that restriction is the Commons Clause);
        </li>
        <li>use PotenFYR names, logos or trademarks for your own projects.</li>
      </ul>
      <p className="mt-3">
        Copies and redistributions must carry the Commons Clause notice. Individual egg definitions keep their
        upstream licenses where applicable. The full text lives in the{" "}
        <a
          className="doc-link"
          href="https://github.com/PotenFYR-Studios/potenfyr-nest/blob/master/LICENSE"
          target="_blank"
          rel="noopener"
        >
          LICENSE file
        </a>
        , which is authoritative over this summary.
      </p>
    </PageShell>
  );
}
