import { useEffect, useMemo, useState } from "react";
import { motion } from "motion/react";
import {
  Search,
  Gamepad2,
  ExternalLink,
  Layers,
  LayoutGrid,
  ListFilter,
  Sparkles,
  Database,
  Terminal,
  Blocks,
  Cpu,
  Package,
} from "lucide-react";
import { useNestData } from "./lib/useNestData";
import { catalogSeed, describeFor, eggHay, starsFor } from "./lib/data";
import type { Collection, Egg } from "./lib/types";
import {
  DotPattern,
  Marquee,
  Meteors,
  NumberTicker,
  GlowOrb,
  AccordionItem,
} from "./components/magicui";
import { EggCard, fmtDate } from "./components/EggCard";
import { EggDetailModal } from "./components/EggDetailModal";
import { QuickInstallBar } from "./components/QuickInstallBar";
import { StructuredData } from "./components/StructuredData";

const PANELS = [
  "pterodactyl",
  "pelican",
  "feather panel",
  "wisp",
  "pufferpanel",
  "jexactyl",
  "emerald",
  "docker",
  "kubernetes",
  "railway",
];

const CATEGORIES = [
  { id: "all", label: "All Multi Eggs", icon: Blocks },
  { id: "Database-Eggs", label: "Databases", icon: Database },
  { id: "Minecraft-Eggs", label: "Minecraft", icon: Gamepad2 },
  { id: "Prog-Language-Eggs", label: "Languages", icon: Terminal },
];

export default function App() {
  const { catalog: fetched, error, live, liveState } = useNestData();
  const catalog = fetched ?? catalogSeed;
  const [query, setQuery] = useState("");
  const [tab, setTab] = useState<string>("all");
  const [viewMode, setViewMode] = useState<"grid" | "showcase">("grid");
  const [inspectTarget, setInspectTarget] = useState<{ egg: Egg; collection: Collection } | null>(null);
  const [openFaqIndex, setOpenFaqIndex] = useState<number | null>(0);

  useEffect(() => {
    document.title = fetched
      ? "PotenFYR Nest · Every Multi Egg. One Nest."
      : document.title;
  }, [fetched]);

  // Filtered collections
  const visibleCollections = useMemo(() => {
    return catalog.collections.filter((c) => {
      if (tab !== "all" && c.repo !== tab) return false;
      if (!query) return true;
      const q = query.toLowerCase();
      return c.eggs.some((e) => eggHay(c, e).includes(q));
    });
  }, [catalog, tab, query]);

  // Flattened eggs for the unified Grid Matrix view
  const allEggsList = useMemo(() => {
    return visibleCollections.flatMap((c) =>
      c.eggs
        .filter((e) => {
          if (!query) return true;
          return eggHay(c, e).includes(query.toLowerCase());
        })
        .map((e) => ({
          egg: e,
          collection: c,
        }))
    );
  }, [visibleCollections, query]);

  return (
    <div className="min-h-screen bg-[#0b0d14] text-[#e8eaf2] selection:bg-pink-500/30 selection:text-white">
      <StructuredData />

      {/* Modal Inspector */}
      {inspectTarget && (
        <EggDetailModal
          egg={inspectTarget.egg}
          collection={inspectTarget.collection}
          live={live}
          onClose={() => setInspectTarget(null)}
        />
      )}

      {/* ================= HERO ================= */}
      <header className="relative overflow-hidden border-b border-white/[0.08]">
        {/* Ambient atmospheric glow orbs */}
        <GlowOrb color="rgba(139, 92, 246, 0.18)" size={550} className="-left-20 -top-32" />
        <GlowOrb color="rgba(236, 72, 153, 0.15)" size={500} className="-right-20 -top-20" />
        <GlowOrb color="rgba(6, 182, 212, 0.12)" size={420} className="left-1/3 top-1/2" />

        <DotPattern className="[mask-image:radial-gradient(750px_circle_at_50%_0,white,transparent)]" />
        <Meteors number={16} />

        {/* Top Nav */}
        <nav className="relative mx-auto flex max-w-7xl items-center justify-between gap-4 px-6 py-5">
          <a href="./" className="group flex items-center gap-2.5 font-mono text-lg font-bold">
            <span className="flex h-9 w-9 items-center justify-center rounded-xl bg-white/5 border border-white/10 text-xl shadow-inner transition-transform group-hover:scale-105">
              🥚
            </span>
            <span>
              PotenFYR&nbsp;<span className="grad-text">Nest</span>
            </span>
          </a>

          <div className="flex flex-wrap items-center gap-4 text-sm text-[#9aa0b4]">
            <a
              className="hidden sm:inline-block transition-colors hover:text-white"
              href="https://github.com/PotenFYR-Studios"
              target="_blank"
              rel="noopener"
            >
              GitHub
            </a>
            <a
              className="hidden sm:inline-block transition-colors hover:text-white"
              href="https://potenfyr.in"
              target="_blank"
              rel="noopener"
            >
              Website
            </a>
            <a
              className="hidden sm:inline-block transition-colors hover:text-white"
              href="https://discord.com/invite/zUaN2FPBec"
              target="_blank"
              rel="noopener"
            >
              Discord
            </a>
            <a
              className="grad-bg flex items-center gap-1.5 rounded-full px-4 py-2 text-xs font-bold text-white shadow-[0_4px_24px_rgba(236,72,153,0.35)] transition-transform hover:-translate-y-0.5"
              href="https://github.com/PotenFYR-Studios/potenfyr-nest"
              target="_blank"
              rel="noopener"
            >
              ★ Star the nest
            </a>
          </div>
        </nav>

        {/* Hero Headline & Stats */}
        <div className="relative mx-auto max-w-5xl px-6 pb-16 pt-12 text-center">
          <motion.div
            initial={{ opacity: 0, y: 12 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.5 }}
            className="mb-4 inline-flex items-center gap-2 rounded-full border border-white/10 bg-white/[0.03] px-3.5 py-1 text-xs font-mono text-[#9aa0b4] backdrop-blur-md"
          >
            <Sparkles className="h-3.5 w-3.5 text-[#ec4899]" />
            <span>PotenFYR Studios · Official Multi-Egg Catalog</span>
          </motion.div>

          <motion.h1
            initial={{ opacity: 0, y: 16 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.6, delay: 0.08 }}
            className="mx-auto mb-5 max-w-4xl text-balance text-5xl font-extrabold leading-[1.08] tracking-tight sm:text-6xl md:text-7xl"
          >
            Every <span className="grad-text">Multi Egg.</span> One Nest.
          </motion.h1>

          <motion.p
            initial={{ opacity: 0, y: 16 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.6, delay: 0.16 }}
            className="mx-auto mb-10 max-w-2xl text-lg leading-relaxed text-[#9aa0b4]"
          >
            Universal, production-ready eggs for <b className="text-white">Pterodactyl</b>,{" "}
            <b className="text-white">Pelican</b>, and <b className="text-white">Feather Panel</b>. One egg runs 55+ databases, 50+ programming languages, or every Minecraft server type.
          </motion.p>

          {/* Stats Bar */}
          <div className="mx-auto grid max-w-3xl grid-cols-2 gap-3.5 sm:grid-cols-4">
            <Stat
              icon={Package}
              label="collections"
              value={catalog.counts.collections}
              color="text-violet-400"
            />
            <Stat
              icon={Blocks}
              label="multi eggs"
              value={catalog.counts.eggs}
              color="text-pink-400"
            />
            <Stat
              icon={Cpu}
              label="variables"
              value={catalog.counts.variables}
              color="text-sky-400"
            />
            <Stat
              icon={Layers}
              label="docker images"
              value={catalog.counts.images}
              color="text-emerald-400"
            />
          </div>

          {/* Live Status Indicator */}
          <div className="mt-8 flex items-center justify-center gap-2 font-mono text-xs text-[#9aa0b4]">
            <span className="relative flex h-2 w-2">
              <span
                className={`absolute inline-flex h-full w-full rounded-full ${
                  liveState === "fallback" ? "bg-amber-500" : "bg-emerald-500"
                } opacity-75 ${liveState !== "fallback" ? "animate-ping" : ""}`}
              />
              <span
                className={`relative inline-flex h-2 w-2 rounded-full ${
                  liveState === "fallback" ? "bg-amber-500" : "bg-emerald-500"
                }`}
              />
            </span>
            <span>
              {liveState === "live" && "Live: GitHub metadata synchronized in real-time"}
              {liveState === "fallback" && "Showing synced catalog snapshot"}
              {liveState === "pending" && "Connecting to live GitHub API…"}
            </span>
            <span className="opacity-30">|</span>
            <span>Auto-synced {fmtDate(catalog.generated_at)}</span>
          </div>
        </div>
      </header>

      {/* ================= PANEL MARQUEE ================= */}
      <div className="border-b border-white/[0.08] bg-[#0d101a] py-3.5" aria-label="Supported panels">
        <Marquee>
          {PANELS.map((p) => (
            <span key={p} className="flex items-center gap-2 font-mono text-xs uppercase tracking-widest text-[#6a7089]">
              <Gamepad2 className="h-3.5 w-3.5 text-[#8b5cf6]" aria-hidden />
              {p}
            </span>
          ))}
        </Marquee>
      </div>

      {/* ================= MAIN CONTENT ================= */}
      <main className="mx-auto max-w-7xl px-6 pb-24 pt-10">
        {/* Quick Panel Deployment Bar */}
        <section className="mb-10">
          <QuickInstallBar catalog={catalog} />
        </section>

        {/* Filter, Search & View Controls */}
        <div className="mb-8 flex flex-col gap-4 md:flex-row md:items-center md:justify-between">
          {/* Search bar */}
          <label className="relative flex-1 max-w-md">
            <span className="sr-only">Search eggs</span>
            <Search className="pointer-events-none absolute left-4 top-1/2 h-4 w-4 -translate-y-1/2 text-[#6a7089]" aria-hidden />
            <input
              id="egg-search"
              type="search"
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder="Search eggs, variables, engines, docker images…"
              autoComplete="off"
              spellCheck={false}
              className="w-full rounded-xl border border-white/10 bg-[#151828] py-2.5 pl-11 pr-4 text-sm text-white placeholder:text-[#6a7089] outline-none transition-shadow focus:border-[#8b5cf6] focus:shadow-[0_0_0_3px_rgba(139,92,246,0.18)]"
            />
          </label>

          {/* Category Tabs & View Switcher */}
          <div className="flex flex-wrap items-center gap-2.5">
            <div className="flex flex-wrap gap-1.5 rounded-xl border border-white/10 bg-[#151828] p-1" role="tablist">
              {CATEGORIES.map((cat) => {
                const Icon = cat.icon;
                const active = tab === cat.id;
                const count =
                  cat.id === "all"
                    ? catalog.counts.eggs
                    : catalog.collections.find((c) => c.repo === cat.id)?.eggs.length || 0;
                return (
                  <button
                    key={cat.id}
                    type="button"
                    role="tab"
                    aria-selected={active}
                    onClick={() => setTab(cat.id)}
                    className={`flex items-center gap-1.5 rounded-lg px-3 py-1.5 text-xs font-semibold transition-all ${
                      active
                        ? "grad-bg text-white shadow-sm"
                        : "text-[#9aa0b4] hover:bg-white/5 hover:text-white"
                    }`}
                  >
                    <Icon className="h-3.5 w-3.5" />
                    <span>{cat.label}</span>
                    <span className="rounded-full bg-black/30 px-1.5 py-0.2 font-mono text-[10px]">
                      {count}
                    </span>
                  </button>
                );
              })}
            </div>

            {/* Grid / Showcase Toggle */}
            <div className="hidden sm:flex items-center rounded-xl border border-white/10 bg-[#151828] p-1">
              <button
                type="button"
                onClick={() => setViewMode("grid")}
                className={`flex items-center gap-1 rounded-lg px-2.5 py-1.5 text-xs font-semibold transition-all ${
                  viewMode === "grid"
                    ? "bg-white/10 text-white"
                    : "text-[#9aa0b4] hover:text-white"
                }`}
                title="Balanced 3-column Matrix"
              >
                <LayoutGrid className="h-3.5 w-3.5" />
                <span>Grid</span>
              </button>
              <button
                type="button"
                onClick={() => setViewMode("showcase")}
                className={`flex items-center gap-1 rounded-lg px-2.5 py-1.5 text-xs font-semibold transition-all ${
                  viewMode === "showcase"
                    ? "bg-white/10 text-white"
                    : "text-[#9aa0b4] hover:text-white"
                }`}
                title="Full-Width Showcase"
              >
                <ListFilter className="h-3.5 w-3.5" />
                <span>Showcase</span>
              </button>
            </div>
          </div>
        </div>

        {/* Error notification if sync is pending */}
        {error && (
          <div className="mb-8 rounded-xl border border-amber-500/30 bg-amber-500/10 p-4 font-mono text-sm text-amber-200">
            Catalog sync note: {error}
          </div>
        )}

        {/* Results summary */}
        <div className="mb-6 flex items-center justify-between text-xs font-mono text-[#9aa0b4]">
          <span>
            Showing <b className="text-white">{allEggsList.length}</b> multi egg{allEggsList.length === 1 ? "" : "s"}
          </span>
          {query && (
            <button
              type="button"
              onClick={() => setQuery("")}
              className="text-[#ec4899] hover:underline"
            >
              Clear search
            </button>
          )}
        </div>

        {/* ================= EGGS CATALOG DISPLAY ================= */}
        {viewMode === "grid" ? (
          /* UNIFIED 3-COLUMN BALANCED MATRIX (Zero empty slots, equal heights, perfect baselines) */
          <div className="grid grid-cols-1 gap-6 md:grid-cols-2 lg:grid-cols-3">
            {allEggsList.map(({ egg, collection }) => (
              <div key={`${collection.repo}-${egg.path}`} className="h-full">
                <EggCard
                  egg={egg}
                  collection={collection}
                  live={live}
                  onInspect={(e, c) => setInspectTarget({ egg: e, collection: c })}
                  mode="grid"
                />
              </div>
            ))}
          </div>
        ) : (
          /* SHOWCASE MODE (Full-width dual-column cards) */
          <div className="flex flex-col gap-8">
            {visibleCollections.map((c) => (
              <div key={c.repo} className="space-y-4">
                <div className="flex items-center justify-between">
                  <div className="flex items-center gap-2">
                    <h2 className="text-xl font-bold text-white tracking-tight">{c.repo}</h2>
                    <span className="rounded-full border border-white/10 bg-white/5 px-2.5 py-0.5 font-mono text-xs text-[#9aa0b4]">
                      ★ {starsFor(c, live)}
                    </span>
                  </div>
                  <a
                    href={c.url}
                    target="_blank"
                    rel="noopener"
                    className="inline-flex items-center gap-1 font-mono text-xs text-[#8b5cf6] hover:underline"
                  >
                    <span>repository</span>
                    <ExternalLink className="h-3 w-3" />
                  </a>
                </div>
                <p className="text-sm text-[#9aa0b4]">{describeFor(c, live)}</p>
                <div className="space-y-4">
                  {c.eggs.map((e) => (
                    <EggCard
                      key={e.path}
                      egg={e}
                      collection={c}
                      live={live}
                      onInspect={(eggItem, colItem) => setInspectTarget({ egg: eggItem, collection: colItem })}
                      mode="showcase"
                    />
                  ))}
                </div>
              </div>
            ))}
          </div>
        )}

        {/* Empty state */}
        {allEggsList.length === 0 && (
          <div className="py-20 text-center">
            <div className="mx-auto mb-3 flex h-12 w-12 items-center justify-center rounded-2xl bg-white/5 text-2xl">
              🔍
            </div>
            <h3 className="text-lg font-semibold text-white">No eggs match your search</h3>
            <p className="mt-1 text-sm text-[#9aa0b4]">Try clearing your search query or selecting "All Multi Eggs".</p>
          </div>
        )}

        {/* ================= FAQ ACCORDION ================= */}
        <section aria-labelledby="faq-heading" className="mt-24 border-t border-white/10 pt-16">
          <div className="text-center max-w-2xl mx-auto mb-10">
            <h2 id="faq-heading" className="text-3xl font-bold tracking-tight text-white mb-2">
              Frequently Asked Questions
            </h2>
            <p className="text-sm text-[#9aa0b4]">
              Everything you need to know about multi eggs, installation, panel compatibility, and automated sync.
            </p>
          </div>

          <div className="grid gap-3.5 max-w-4xl mx-auto">
            {FAQS.map(([question, answer], index) => (
              <AccordionItem
                key={question}
                title={question}
                isOpen={openFaqIndex === index}
                onToggle={() => setOpenFaqIndex(openFaqIndex === index ? null : index)}
              >
                {answer}
              </AccordionItem>
            ))}
          </div>
        </section>
      </main>

      {/* ================= FOOTER ================= */}
      <footer className="border-t border-white/10 bg-[#0e111d]">
        <div className="mx-auto max-w-7xl px-6 py-12">
          <div className="flex flex-col md:flex-row items-center justify-between gap-6 text-center md:text-left">
            <div>
              <div className="font-mono text-base font-bold text-white flex items-center justify-center md:justify-start gap-2">
                <span>🥚</span>
                <span>PotenFYR Nest</span>
              </div>
              <p className="mt-1 text-xs text-[#9aa0b4] max-w-md">
                Official Multi Egg Catalog for game server hosting panels. Automated GitHub sync every 30 minutes.
              </p>
            </div>

            <div className="flex flex-wrap items-center justify-center gap-6 text-xs font-mono text-[#9aa0b4]">
              <a href="https://github.com/PotenFYR-Studios" target="_blank" rel="noopener" className="hover:text-white transition-colors">
                GitHub Org
              </a>
              <a href="https://potenfyr.in" target="_blank" rel="noopener" className="hover:text-white transition-colors">
                potenfyr.in
              </a>
              <a href="https://discord.com/invite/zUaN2FPBec" target="_blank" rel="noopener" className="hover:text-white transition-colors">
                Support Discord
              </a>
              <a href="https://modrinth.com/organization/potenfyr" target="_blank" rel="noopener" className="hover:text-white transition-colors">
                Modrinth
              </a>
              <a href="./data/catalog.json" target="_blank" rel="noopener" className="text-[#a78bfa] hover:underline">
                data/catalog.json
              </a>
            </div>
          </div>

          <div className="mt-8 border-t border-white/[0.06] pt-6 flex flex-col sm:flex-row items-center justify-between gap-3 text-xs text-[#6a7089]">
            <span>© {new Date().getFullYear()} PotenFYR Studios. Released under MIT License.</span>
            <span>Crafted with ❤️ for Pterodactyl, Pelican & Feather Panel communities</span>
          </div>
        </div>
      </footer>
    </div>
  );
}

function Stat({
  label,
  value,
  icon: Icon,
  color,
}: {
  label: string;
  value: number;
  icon: React.ElementType;
  color: string;
}) {
  return (
    <div className="rounded-2xl border border-white/10 bg-white/[0.02] p-4 text-center backdrop-blur-md transition-transform hover:-translate-y-0.5">
      <div className="flex justify-center mb-1">
        <Icon className={`h-5 w-5 ${color}`} />
      </div>
      <NumberTicker value={value} className="grad-text block font-mono text-3xl font-extrabold" />
      <span className="text-[11.5px] uppercase tracking-[1.4px] text-[#9aa0b4] font-medium">{label}</span>
    </div>
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
    "Which hosting panels are supported?",
    "The multi eggs target Pterodactyl, Pelican and Feather Panel first, and are built to run anywhere Docker runs, including Wisp, PufferPanel, Jexactyl, Emerald, Kubernetes, Fly.io, Railway and Render.",
  ],
  [
    "How do I install an egg?",
    "Open an egg card on this page, download the JSON definition from its source repository or copy the curl snippet, and import it in your panel under Nests → Eggs. Each egg's README in its repository documents every variable and startup option.",
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
