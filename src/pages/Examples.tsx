import { CodeBlock } from "../components/CodeBlock";
import { PageShell } from "./PageShell";

/**
 * Verbatim excerpts from the real egg definitions in the org's collection
 * repositories (fields abridged; values unchanged). Full files are linked
 * under each block.
 */

const DB_EGG = `{
  "meta": {
    "version": "PTDL_v2",
    "update_url": "https://raw.githubusercontent.com/PotenFYR-Studios/Database-Eggs/main/egg-database-multi.json"
  },
  "name": "Multi Database",
  "author": "support@potenfyr.in",
  "description": "One egg. Every database. Every version. Supports 55+ SQL, NoSQL, In-Memory, Vector, Time-Series, Search, Graph and Object-Storage engines. Versions install isolated inside the container on demand from startup variables ('latest' auto-resolves). Switching engine or major version never deletes previous data - instances are kept per version until you remove them manually.",
  "docker_images": {
    "Universal Multi-Database (All Engines)": "ghcr.io/potenfyr-studios/database-eggs:latest"
  },
  "features": ["pid_limit"],
  "variables": [
    {
      "name": "Database Type",
      "env_variable": "DATABASE_TYPE",
      "default_value": "mariadb"
    },
    {
      "name": "Database Version",
      "env_variable": "DB_VERSION",
      "default_value": "latest"
    }
  ]
}`;

const MC_EGG = `{
  "meta": {
    "version": "PTDL_v2",
    "update_url": "https://raw.githubusercontent.com/PotenFYR-Studios/Minecraft-Eggs/main/egg-minecraft-multi.json"
  },
  "name": "Multi Minecraft",
  "docker_images": {
    "Universal (Auto Java)": "ghcr.io/potenfyr-studios/minecraft-eggs:latest"
  },
  "features": ["eula", "java_version", "pid_limit"],
  "variables": [
    {
      "name": "Server Type",
      "env_variable": "SERVER_TYPE",
      "default_value": "vanilla"
    }
  ]
}`;

const PROG_EGG = `{
  "meta": {
    "version": "PTDL_v2",
    "update_url": "https://raw.githubusercontent.com/PotenFYR-Studios/Prog-Language-Eggs/main/egg-programming-multi.json"
  },
  "name": "Prog-Language Eggs",
  "description": "Prog-Language Eggs - one egg for 50+ programming languages with package managers, auto-detection, memory tuning, and Dev Watch mode.",
  "docker_images": {
    "Multi-Language (50+ Languages)": "ghcr.io/potenfyr-studios/prog-language-eggs:latest"
  },
  "features": ["pid_limit"],
  "variables": [
    {
      "name": "Target Language",
      "env_variable": "LANGUAGE",
      "default_value": "auto"
    },
    {
      "name": "Execution Runner",
      "env_variable": "RUNNER",
      "default_value": "auto"
    }
  ]
}`;

const CURL_EXAMPLE = `curl -sSL -o egg-database-multi.json \\
  "https://raw.githubusercontent.com/PotenFYR-Studios/Database-Eggs/main/egg-database-multi.json"`;

interface Example {
  id: string;
  title: string;
  repo: string;
  file: string;
  chips: string[];
  code: string;
  accent: string;
}

const EXAMPLES: Example[] = [
  {
    id: "database",
    title: "Multi Database",
    repo: "Database-Eggs",
    file: "egg-database-multi.json",
    chips: ["55+ engines", "PTDL_v2", "on-demand install"],
    code: DB_EGG,
    accent: "border-sky-500/30 bg-sky-500/10 text-sky-300",
  },
  {
    id: "minecraft",
    title: "Multi Minecraft",
    repo: "Minecraft-Eggs",
    file: "egg-minecraft-multi.json",
    chips: ["18+ server types", "PTDL_v2", "auto Java"],
    code: MC_EGG,
    accent: "border-emerald-500/30 bg-emerald-500/10 text-emerald-300",
  },
  {
    id: "prog",
    title: "Prog-Language Eggs",
    repo: "Prog-Language-Eggs",
    file: "egg-programming-multi.json",
    chips: ["50+ languages", "PTDL_v2", "Dev Watch"],
    code: PROG_EGG,
    accent: "border-pink-500/30 bg-pink-500/10 text-pink-300",
  },
];

export default function ExamplesPage() {
  return (
    <PageShell
      crumbs={["Catalog", "Examples"]}
      title="Real egg definitions"
      lead="Actual multi egg JSON from the org's collection repositories, abridged to the fields that matter. Copy them, import them, or read the full files."
      toc={[
        ...EXAMPLES.map((ex) => ({ id: ex.id, label: ex.title })),
        { id: "fetch", label: "Fetch one from the shell" },
      ]}
      prev={{ href: "/docs", label: "Docs" }}
      next={null}
    >
      {EXAMPLES.map((ex) => (
        <section key={ex.id} className="mt-12 first:mt-10">
          <div className="mb-3 flex flex-wrap items-center gap-2.5">
            <h2 id={ex.id} className="doc-h2 !mt-0 border-b-0 pb-0">{ex.title}</h2>
            <span className="rounded-full border border-white/10 bg-white/5 px-2.5 py-0.5 font-mono text-xs text-[#9aa0b4]">
              {ex.repo}
            </span>
          </div>
          <div className="mb-4 flex flex-wrap gap-1.5">
            {ex.chips.map((chip) => (
              <span
                key={chip}
                className={`inline-flex items-center rounded-full border px-2.5 py-0.5 font-mono text-[11px] font-semibold ${ex.accent}`}
              >
                {chip}
              </span>
            ))}
          </div>

          <CodeBlock code={ex.code} label="egg json · excerpt" filename={ex.file} />

          <div className="mt-3 flex flex-wrap items-center gap-x-5 gap-y-2 text-[13px]">
            <a
              className="doc-link"
              href={`https://github.com/PotenFYR-Studios/${ex.repo}/blob/main/${ex.file}`}
              target="_blank"
              rel="noopener"
            >
              Full definition on GitHub →
            </a>
            <a className="doc-link" href={`/eggs/${ex.repo}/${ex.file}`} target="_blank" rel="noopener">
              Verbatim mirror →
            </a>
            <a className="doc-link" href={`https://github.com/PotenFYR-Studios/${ex.repo}`} target="_blank" rel="noopener">
              Repository →
            </a>
          </div>
        </section>
      ))}

      <h2 id="fetch" className="doc-h2">Fetch one from the shell</h2>
      <p>Every egg definition lives at a predictable raw URL, so a one-liner is all it takes:</p>
      <div className="mt-4">
        <CodeBlock code={CURL_EXAMPLE} label="shell" filename="install with curl" />
      </div>
      <p className="mt-3">
        Import the downloaded JSON in your panel under Nests → Eggs; the full flow is in the{" "}
        <a className="doc-link" href="/docs">
          docs
        </a>
        .
      </p>
    </PageShell>
  );
}
