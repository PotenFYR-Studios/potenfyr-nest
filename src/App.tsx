import { useEffect, useMemo, useState } from "react";
import { motion } from "motion/react";
import { Search, Star, Gamepad2, ExternalLink } from "lucide-react";
import { useNestData } from "./lib/useNestData";
import { catalogSeed, describeFor, eggHay, pushedFor } from "./lib/data";
import type { Collection } from "./lib/types";
import { DotPattern, Marquee, Meteors, NumberTicker, ShineBorder } from "./components/magicui";
import { EggCard, fmtDate, relTime } from "./components/EggCard";
import { StructuredData } from "./components/StructuredData";

const PANELS = ["pterodactyl", "pelican", "feather", "wisp", "pufferpanel", "jexactyl", "emerald", "docker"];

export default function App() {
  const { catalog: fetched, error, live, liveState } = useNestData();
  const catalog = fetched ?? catalogSeed;
  const [query, setQuery] = useState("");
  const [tab, setTab] = useState<string>("all");

  useEffect(() => {
    document.title = fetched
      ? "PotenFYR Nest · Every Multi Egg. One Nest."
      : document.title;
  }, [fetched]);

  const visible = useMemo(() => {
    return catalog.collections.filter((c) => {
      if (tab !== "all" && c.repo !== tab) return false;
      if (!query) return true;
      const q = query.toLowerCase();
      return c.eggs.some((e) => eggHay(c, e).includes(q));
    });
  }, [catalog, tab, query]);

  return (
    <div className="min-h-screen">
      <StructuredData />
      {/* ================= HERO ================= */}
      <header className="relative overflow-hidden border-b border-line">
        <div
          aria-hidden
          className="pointer-events-none absolute inset-0"
          style={{
            background:
              "radial-gradient(1000px 420px at 15% -10%, rgba(139,92,246,0.22), transparent 60%), radial-gradient(900px 380px at 85% -20%, rgba(249,115,22,0.14), transparent 60%), linear-gradient(180deg, #0b0d14, #0d0f16)",
          }}
        />
        <DotPattern className="[mask-image:radial-gradient(600px_circle_at_50%_0,white,transparent)]" />
        <Meteors number={10} />

        <nav className="relative mx-auto flex max-w-6xl items-center justify-between gap-4 px-6 py-5">
          <a href="./" className="font-mono text-lg font-semibold">
            🥚 PotenFYR&nbsp;<span className="text-[#ec4899]">Nest</span>
          </a>
          <div className="flex flex-wrap items-center gap-4 text-sm text-[#9aa0b4]">
            <a className="transition-colors hover:text-white" href="https://github.com/PotenFYR-Studios" target="_blank" rel="noopener">
              GitHub
            </a>
            <a className="transition-colors hover:text-white" href="https://potenfyr.in" target="_blank" rel="noopener">
              Website
            </a>
            <a className="transition-colors hover:text-white" href="https://discord.com/invite/zUaN2FPBec" target="_blank" rel="noopener">
              Discord
            </a>
            <a
              className="grad-bg rounded-full px-4 py-2 text-[13.5px] font-semibold text-white shadow-[0_4px_24px_rgba(236,72,153,0.35)] transition-transform hover:-translate-y-px"
              href="https://github.com/PotenFYR-Studios/potenfyr-nest"
              target="_blank"
              rel="noopener"
            >
              ★ Star the nest
            </a>
          </div>
        </nav>

        <div className="relative mx-auto max-w-6xl px-6 pb-14 pt-10 text-center">
          <motion.p
            initial={{ opacity: 0, y: 12 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.5 }}
            className="mb-4 font-mono text-xs uppercase tracking-[3px] text-[#9aa0b4]"
          >
            PotenFYR Studios · Egg Catalog
          </motion.p>
          <motion.h1
            initial={{ opacity: 0, y: 16 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.6, delay: 0.08 }}
            className="mx-auto mb-5 max-w-3xl text-balance text-5xl font-extrabold leading-[1.05] tracking-tight md:text-6xl"
          >
            Every <span className="grad-text">Multi Egg.</span> One Nest.
          </motion.h1>
          <motion.p
            initial={{ opacity: 0, y: 16 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.6, delay: 0.16 }}
            className="mx-auto mb-9 max-w-2xl text-lg text-[#9aa0b4]"
          >
            Production-ready eggs for <b className="text-white">Pterodactyl</b>, <b className="text-white">Pelican</b> and{" "}
            <b className="text-white">Feather</b>. One egg covers every database, 50+ languages and every Minecraft server
            type. Auto-synced from the org, every 30 minutes.
          </motion.p>

          <div className="mx-auto grid max-w-3xl grid-cols-2 gap-3.5 sm:grid-cols-4">
            <Stat label="collections" value={catalog.counts.collections} />
            <Stat label="multi eggs" value={catalog.counts.eggs} />
            <Stat label="variables" value={catalog.counts.variables} />
            <Stat label="docker images" value={catalog.counts.images} />
          </div>

          <p className="mt-6 flex items-center justify-center gap-2 font-mono text-xs text-[#9aa0b4]">
            <span className="relative flex h-2 w-2">
              <span className={`absolute inline-flex h-full w-full rounded-full ${liveState === "fallback" ? "bg-[#f97316]" : "bg-[#2ea043]"} opacity-60 ${liveState !== "fallback" ? "animate-ping" : ""}`} />
              <span className={`relative inline-flex h-2 w-2 rounded-full ${liveState === "fallback" ? "bg-[#f97316]" : "bg-[#2ea043]"}`} />
            </span>
            {liveState === "live" && "live: stars & push times fetched fresh from the GitHub API"}
            {liveState === "fallback" && "showing synced data (GitHub API rate-limited this visit)"}
            {liveState === "pending" && "loading live GitHub data…"}
            <span className="mx-1 opacity-40">|</span>
            catalog synced {fmtDate(catalog.generated_at)}
          </p>
        </div>
      </header>

      {/* ================= PANEL MARQUEE ================= */}
      <div className="border-b border-line bg-bg2 py-4" aria-label="Supported panels">
        <Marquee>
          {PANELS.map((p) => (
            <span key={p} className="flex items-center gap-2 font-mono text-sm uppercase tracking-widest text-[#6a7089]">
              <Gamepad2 className="h-4 w-4 text-[#8b5cf6]" aria-hidden />
              {p}
            </span>
          ))}
        </Marquee>
      </div>

      {/* ================= CATALOG ================= */}
      <main className="mx-auto max-w-6xl px-6 pb-24 pt-10">
        <div className="mb-9 flex flex-wrap items-center gap-3.5">
          <label className="relative flex-1 basis-80">
            <span className="sr-only">Search eggs</span>
            <Search className="pointer-events-none absolute left-4 top-1/2 h-4 w-4 -translate-y-1/2 text-[#6a7089]" aria-hidden />
            <input
              id="egg-search"
              type="search"
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder="Search eggs, variables, engines…"
              autoComplete="off"
              spellCheck={false}
              className="w-full rounded-xl border border-line bg-panel py-3 pl-11 pr-4 text-[15px] text-white outline-none transition-shadow placeholder:text-[#6a7089] focus:border-[#8b5cf6] focus:shadow-[0_0_0_3px_rgba(139,92,246,0.18)]"
            />
          </label>
          <div className="flex flex-wrap gap-2" role="tablist" aria-label="Filter by collection">
            <TabButton active={tab === "all"} onClick={() => setTab("all")}>
              All
            </TabButton>
            {catalog.collections.map((c) => (
              <TabButton key={c.repo} active={tab === c.repo} onClick={() => setTab(c.repo)}>
                {c.repo.replace(/-Eggs$/, "")}
              </TabButton>
            ))}
          </div>
        </div>

        {error && (
          <p className="mb-8 rounded-xl border border-[rgba(249,115,22,0.3)] bg-[rgba(249,115,22,0.08)] p-4 font-mono text-sm text-[#fdba74]">
            catalog unavailable: {error} (the sync workflow may not have run yet)
          </p>
        )}

        <div className="flex flex-col gap-14">
          {visible.map((c) => (
            <CollectionSection key={c.repo} c={c} live={live} />
          ))}
        </div>

        {visible.length === 0 && !error && (
          <p className="py-16 text-center text-[#9aa0b4]">No eggs match your search.</p>
        )}

        {/* ================= FAQ (AI-search friendly Q&A) ================= */}
        <Faq />
      </main>

      {/* ================= FOOTER ================= */}
      <footer className="border-t border-line bg-bg2">
        <div className="mx-auto max-w-6xl px-6 py-10 text-center">
          <p className="text-sm text-[#9aa0b4]">
            <b className="text-white">🥚 PotenFYR Nest</b> · the catalog of every multi egg by PotenFYR Studios. Synced
            every 30 minutes by GitHub Actions; stars and push times refresh live on every visit.
          </p>
          <p className="mt-2 flex flex-wrap items-center justify-center gap-x-2 text-sm">
            {[
              ["GitHub", "https://github.com/PotenFYR-Studios"],
              ["potenfyr.in", "https://potenfyr.in"],
              ["Modrinth", "https://modrinth.com/organization/potenfyr"],
              ["Support Discord", "https://discord.com/invite/PRJASTKqwD"],
              ["catalog.json", "./data/catalog.json"],
            ].map(([label, href], i) => (
              <span key={label}>
                {i > 0 && <span className="mr-2 text-[#6a7089]">·</span>}
                <a href={href} target="_blank" rel="noopener" className="text-[#8b5cf6] hover:underline">
                  {label}
                </a>
              </span>
            ))}
          </p>
          <p className="mt-3 text-xs text-[#6a7089]">Made with ❤️ by PotenFYR Studios</p>
        </div>
      </footer>
    </div>
  );
}

function Stat({ label, value }: { label: string; value: number }) {
  return (
    <div className="rounded-2xl border border-line bg-white/[0.03] px-6 py-4 backdrop-blur">
      <NumberTicker value={value} className="grad-text block font-mono text-[28px] font-semibold" />
      <span className="text-[12.5px] uppercase tracking-[1.4px] text-[#9aa0b4]">{label}</span>
    </div>
  );
}

function TabButton({ active, onClick, children }: { active: boolean; onClick: () => void; children: React.ReactNode }) {
  return (
    <button
      type="button"
      role="tab"
      aria-selected={active}
      onClick={onClick}
      className={`rounded-full border px-3.5 py-2 text-[13px] font-semibold transition-all ${
        active ? "grad-bg border-transparent text-white" : "border-line bg-transparent text-[#9aa0b4] hover:border-[#8b5cf6] hover:text-white"
      }`}
    >
      {children}
    </button>
  );
}

function CollectionSection({ c, live }: { c: Collection; live: Map<string, import("./lib/types").LiveRepo> }) {
  const stars = live.get(c.repo)?.stars ?? c.stars;
  const pushed = pushedFor(c, live);
  const desc = describeFor(c, live);
  return (
    <motion.section
      initial={{ opacity: 0, y: 18 }}
      whileInView={{ opacity: 1, y: 0 }}
      viewport={{ once: true, margin: "-60px" }}
      transition={{ duration: 0.45 }}
      aria-label={c.repo}
    >
      <div className="mb-5 flex flex-wrap items-baseline gap-x-4 gap-y-2">
        <h2 className="text-2xl font-bold tracking-tight">
          <a href={c.url} target="_blank" rel="noopener" className="transition-colors hover:text-[#ec4899]">
            {c.repo}
            <ExternalLink className="ml-2 inline h-4 w-4 text-[#6a7089]" aria-hidden />
          </a>
        </h2>
        <Badge>
          <Star className="mr-1 inline h-3.5 w-3.5 text-[#eac54f]" aria-hidden /> {stars}
        </Badge>
        <Badge>
          pushed {relTime(pushed) || fmtDate(pushed)}
        </Badge>
        {c.license && c.license !== "" && <Badge>{c.license} license</Badge>}
      </div>
      {desc && <p className="mb-5 max-w-3xl text-[14.5px] text-[#9aa0b4]">{desc}</p>}
      <div className="grid grid-cols-1 gap-[18px] sm:grid-cols-2 lg:grid-cols-3">
        {c.eggs.map((e) => (
          <div key={e.path} className="group/card">
            <EggCard egg={e} collection={c} live={live} />
          </div>
        ))}
      </div>
    </motion.section>
  );
}

function Badge({ children }: { children: React.ReactNode }) {
  return (
    <span className="rounded-full border border-line px-2.5 py-0.5 font-mono text-xs text-[#9aa0b4]">{children}</span>
  );
}

const FAQS: Array<[string, string]> = [
  [
    "What is PotenFYR Nest?",
    "PotenFYR Nest is the official egg catalog of PotenFYR Studios. It indexes every multi egg the studio publishes for hosting panels and links each egg definition back to its source repository. The catalog and this page are rebuilt automatically every 30 minutes.",
  ],
  [
    "What is a multi egg?",
    "A multi egg is a single Pterodactyl, Pelican or Feather egg that ships many engines or runtimes in one image and installs what you pick on demand. One egg covers every database (MariaDB, PostgreSQL, MongoDB, Redis and 50+ more), one covers 50+ programming languages, and one covers every Minecraft server type.",
  ],
  [
    "Which panels are supported?",
    "The multi eggs target Pterodactyl, Pelican and Feather Panel first, and are built to run anywhere Docker runs, including Wisp, PufferPanel, Jexactyl, Emerald, Kubernetes, Fly.io, Railway and Render.",
  ],
  [
    "How do I install an egg?",
    "Open an egg card on this page, download the JSON definition from its source repository, and import it in your panel under Nests → Eggs. Each egg's README in its repository documents every variable and startup option.",
  ],
  [
    "Is the catalog up to date?",
    "Yes. A GitHub Actions workflow rediscovers every *-Eggs repository in the org every 30 minutes, rebuilds catalog.json and redeploys this site. Star counts and push times are additionally fetched live from the GitHub API on every page load.",
  ],
  [
    "Can I contribute an egg?",
    "Yes. Open a pull request in the relevant *-Eggs repository on GitHub. Any JSON file with a name and docker_images object is picked up automatically by the catalog sync, no changes needed in the nest repo itself.",
  ],
];

function Faq() {
  return (
    <section aria-labelledby="faq-heading" className="mt-20">
      <h2 id="faq-heading" className="mb-2 text-2xl font-bold tracking-tight">
        Frequently asked questions
      </h2>
      <p className="mb-6 text-[14.5px] text-[#9aa0b4]">
        Everything about the nest, multi eggs and the panels they run on.
      </p>
      <div className="grid gap-3 md:grid-cols-2">
        {FAQS.map(([q, a]) => (
          <div key={q} className="relative">
            <ShineBorder duration={10} className="rounded-2xl" />
            <div className="relative h-full rounded-2xl border border-line bg-panel p-5">
              <h3 className="mb-2 font-semibold text-white">{q}</h3>
              <p className="text-sm leading-relaxed text-[#9aa0b4]">{a}</p>
            </div>
          </div>
        ))}
      </div>
    </section>
  );
}
