import { useState } from "react";
import { MagicCard, BorderBeam } from "./magicui";
import type { Collection, Egg, LiveRepo } from "../lib/types";
import { pushedFor, starsFor } from "../lib/data";
import { Download, Sliders, Copy, Check, HardDrive, Cpu, Terminal, Sparkles } from "lucide-react";

export function relTime(iso: string) {
  if (!iso) return "";
  const s = (Date.now() - new Date(iso).getTime()) / 1000;
  if (Number.isNaN(s) || s < 0) return "";
  const units: Array<[number, string]> = [
    [86400, "d"],
    [3600, "h"],
    [60, "m"],
  ];
  for (const [sec, label] of units) {
    if (s >= sec) return `${Math.floor(s / sec)}${label} ago`;
  }
  return "just now";
}

export function fmtDate(iso: string) {
  if (!iso) return "";
  const d = new Date(iso);
  return Number.isNaN(d.getTime())
    ? ""
    : d.toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" });
}

interface EggCardProps {
  egg: Egg;
  collection: Collection;
  live: Map<string, LiveRepo>;
  onInspect: (egg: Egg, collection: Collection) => void;
  mode?: "grid" | "showcase";
}

export function EggCard({ egg, collection, live, onInspect, mode = "grid" }: EggCardProps) {
  const [copied, setCopied] = useState(false);
  const eggUrl = `${collection.url}/blob/${collection.default_branch || "main"}/${egg.path}`;
  const downloadUrl = `./${egg.local.replace(/^public\//, "")}`;
  const pushed = pushedFor(collection, live);

  // Category Theme Detection
  const isDb = egg.name.toLowerCase().includes("database") || collection.repo.includes("Database");
  const isMc = egg.name.toLowerCase().includes("minecraft") || collection.repo.includes("Minecraft");

  const theme = isDb
    ? {
        icon: "🗄️",
        tag: "Universal Database",
        accent: "from-sky-500 to-indigo-500",
        beamColorFrom: "#0ea5e9",
        beamColorTo: "#6366f1",
        cardGlow: "rgba(14, 165, 233, 0.12)",
        highlightBadge: "border-sky-500/30 bg-sky-500/10 text-sky-300",
        featureTag: "55+ Database Engines",
      }
    : isMc
    ? {
        icon: "⚔️",
        tag: "Universal Minecraft",
        accent: "from-emerald-500 to-lime-500",
        beamColorFrom: "#10b981",
        beamColorTo: "#84cc16",
        cardGlow: "rgba(16, 185, 129, 0.12)",
        highlightBadge: "border-emerald-500/30 bg-emerald-500/10 text-emerald-300",
        featureTag: "18+ Server Engines",
      }
    : {
        icon: "⚡",
        tag: "Universal Runtime",
        accent: "from-pink-500 to-amber-500",
        beamColorFrom: "#ec4899",
        beamColorTo: "#f59e0b",
        cardGlow: "rgba(236, 72, 153, 0.12)",
        highlightBadge: "border-pink-500/30 bg-pink-500/10 text-pink-300",
        featureTag: "50+ Runtimes & Dev Watch",
      };

  const copyEggLink = () => {
    const rawUrl = `https://raw.githubusercontent.com/PotenFYR-Studios/${collection.repo}/${collection.default_branch || "main"}/${egg.path}`;
    navigator.clipboard.writeText(rawUrl);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  const primaryImage = egg.images[0]?.name || "Universal Docker Image";

  if (mode === "showcase") {
    return (
      <MagicCard className="w-full" gradientColor={theme.cardGlow}>
        <div className="relative flex flex-col lg:flex-row gap-6 p-6 lg:p-8">
          <BorderBeam size={160} duration={8} colorFrom={theme.beamColorFrom} colorTo={theme.beamColorTo} />

          {/* Left Column: Icon & Core Details */}
          <div className="flex-1 flex flex-col justify-between">
            <div>
              <div className="flex items-center gap-3 mb-3">
                <div className="flex h-12 w-12 items-center justify-center rounded-2xl bg-white/5 border border-white/10 text-2xl shadow-inner">
                  {theme.icon}
                </div>
                <div>
                  <span className={`inline-flex items-center gap-1 rounded-full border px-2.5 py-0.5 font-mono text-[11px] font-semibold ${theme.highlightBadge}`}>
                    <Sparkles className="h-3 w-3" />
                    {theme.featureTag}
                  </span>
                  <div className="font-mono text-xs text-[#9aa0b4] mt-0.5">{collection.repo}</div>
                </div>
                <span className="ml-auto rounded-full border border-yellow-500/30 bg-yellow-500/10 px-3 py-1 font-mono text-xs font-semibold text-yellow-300">
                  ★ {starsFor(collection, live)}
                </span>
              </div>

              <h3 className="text-2xl font-bold tracking-tight text-white mb-2">
                <a href={eggUrl} target="_blank" rel="noopener" className="hover:text-white/90 transition-colors">
                  {egg.name}
                </a>
              </h3>

              <p className="text-sm leading-relaxed text-[#9aa0b4] mb-6">
                {egg.description}
              </p>
            </div>

            {/* Micro spec matrix */}
            <div className="grid grid-cols-2 sm:grid-cols-4 gap-3 border-t border-white/10 pt-4">
              <div className="rounded-xl border border-white/5 bg-black/30 p-3">
                <div className="flex items-center gap-1.5 text-xs text-[#9aa0b4] mb-1">
                  <Cpu className="h-3.5 w-3.5 text-[#8b5cf6]" />
                  <span>Variables</span>
                </div>
                <div className="font-mono text-lg font-bold text-white">{egg.variables.length}</div>
              </div>
              <div className="rounded-xl border border-white/5 bg-black/30 p-3">
                <div className="flex items-center gap-1.5 text-xs text-[#9aa0b4] mb-1">
                  <HardDrive className="h-3.5 w-3.5 text-sky-400" />
                  <span>Images</span>
                </div>
                <div className="font-mono text-lg font-bold text-white">{egg.images.length}</div>
              </div>
              <div className="rounded-xl border border-white/5 bg-black/30 p-3">
                <div className="flex items-center gap-1.5 text-xs text-[#9aa0b4] mb-1">
                  <Terminal className="h-3.5 w-3.5 text-emerald-400" />
                  <span>Features</span>
                </div>
                <div className="font-mono text-sm font-semibold text-white truncate">
                  {egg.features.join(", ") || "Standard"}
                </div>
              </div>
              <div className="rounded-xl border border-white/5 bg-black/30 p-3">
                <div className="flex items-center gap-1.5 text-xs text-[#9aa0b4] mb-1">
                  <span>Updated</span>
                </div>
                <div className="font-mono text-sm font-semibold text-white truncate">
                  {relTime(pushed) || fmtDate(pushed)}
                </div>
              </div>
            </div>
          </div>

          {/* Right Column: Actions & Quick Links */}
          <div className="lg:w-80 flex flex-col justify-between border-t lg:border-t-0 lg:border-l border-white/10 pt-6 lg:pt-0 lg:pl-6">
            <div>
              <div className="text-xs font-mono uppercase tracking-wider text-[#9aa0b4] mb-3">
                Docker Registry URI
              </div>
              <div className="rounded-xl border border-white/10 bg-black/40 p-3 font-mono text-xs text-[#c3b5fc] break-all mb-4">
                {egg.images[0]?.uri || "ghcr.io/potenfyr-studios"}
              </div>

              <div className="text-xs font-mono uppercase tracking-wider text-[#9aa0b4] mb-2">
                Sample Environment Keys
              </div>
              <div className="flex flex-wrap gap-1.5 mb-6">
                {egg.variables.slice(0, 4).map((v) => (
                  <span key={v.env_variable} className="rounded-md border border-white/10 bg-white/5 px-2 py-0.5 font-mono text-[11px] text-[#e8eaf2]">
                    {v.env_variable}
                  </span>
                ))}
                {egg.variables.length > 4 && (
                  <span className="rounded-md border border-white/10 bg-white/5 px-2 py-0.5 font-mono text-[11px] text-[#9aa0b4]">
                    +{egg.variables.length - 4} more
                  </span>
                )}
              </div>
            </div>

            <div className="flex flex-col gap-2">
              <button
                type="button"
                onClick={() => onInspect(egg, collection)}
                className="flex items-center justify-center gap-2 rounded-xl bg-white/10 px-4 py-2.5 text-sm font-semibold text-white hover:bg-white/15 transition-all"
              >
                <Sliders className="h-4 w-4 text-[#a78bfa]" />
                <span>Inspect All Variables & Startup</span>
              </button>
              <div className="grid grid-cols-2 gap-2">
                <a
                  href={downloadUrl}
                  download
                  className="grad-bg flex items-center justify-center gap-1.5 rounded-xl px-3 py-2 text-xs font-semibold text-white hover:opacity-95 transition-transform hover:-translate-y-px"
                >
                  <Download className="h-3.5 w-3.5" />
                  <span>egg.json</span>
                </a>
                <button
                  type="button"
                  onClick={copyEggLink}
                  className="flex items-center justify-center gap-1.5 rounded-xl border border-white/10 bg-white/5 px-3 py-2 text-xs font-semibold text-white hover:bg-white/10"
                >
                  {copied ? <Check className="h-3.5 w-3.5 text-emerald-400" /> : <Copy className="h-3.5 w-3.5" />}
                  <span>{copied ? "Copied!" : "Raw URL"}</span>
                </button>
              </div>
            </div>
          </div>
        </div>
      </MagicCard>
    );
  }

  // ================= GRID MODE (Perfect Equal Heights & Alignments) =================
  return (
    <MagicCard className="h-full flex flex-col" gradientColor={theme.cardGlow}>
      <div className="relative flex flex-1 flex-col justify-between p-6">
        <BorderBeam size={110} duration={8} colorFrom={theme.beamColorFrom} colorTo={theme.beamColorTo} />

        {/* 1. Header: Icon, Tags, Stars */}
        <div>
          <div className="flex items-center justify-between gap-2 mb-3.5">
            <div className="flex items-center gap-2.5">
              <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-white/5 border border-white/10 text-xl shadow-inner">
                {theme.icon}
              </div>
              <div>
                <span className={`inline-flex items-center gap-1 rounded-full border px-2 py-0.5 font-mono text-[10.5px] font-semibold ${theme.highlightBadge}`}>
                  {theme.tag}
                </span>
                <div className="font-mono text-[11px] text-[#9aa0b4]">{collection.repo}</div>
              </div>
            </div>
            <span className="shrink-0 rounded-full border border-yellow-500/30 bg-yellow-500/10 px-2.5 py-0.5 font-mono text-xs font-semibold text-yellow-300">
              ★ {starsFor(collection, live)}
            </span>
          </div>

          {/* 2. Title */}
          <h3 className="text-xl font-bold tracking-tight text-white mb-2">
            <a href={eggUrl} target="_blank" rel="noopener" className="hover:text-[#ec4899] transition-colors">
              {egg.name}
            </a>
          </h3>

          {/* 3. Description (Strictly clamped to 2 lines for uniform card baseline) */}
          <p className="line-clamp-2 min-h-[40px] text-sm leading-relaxed text-[#9aa0b4] mb-4">
            {egg.description}
          </p>

          {/* 4. Specs Grid (Uniform 2x2 cards) */}
          <div className="grid grid-cols-2 gap-2 mb-4">
            <div className="rounded-xl border border-white/5 bg-black/30 p-2.5">
              <div className="flex items-center gap-1.5 text-[11px] text-[#9aa0b4] mb-0.5">
                <Cpu className="h-3 w-3 text-[#8b5cf6]" />
                <span>Variables</span>
              </div>
              <div className="font-mono text-sm font-bold text-white">{egg.variables.length} configured</div>
            </div>
            <div className="rounded-xl border border-white/5 bg-black/30 p-2.5">
              <div className="flex items-center gap-1.5 text-[11px] text-[#9aa0b4] mb-0.5">
                <HardDrive className="h-3 w-3 text-sky-400" />
                <span>Docker Engine</span>
              </div>
              <div className="font-mono text-sm font-bold text-white truncate" title={primaryImage}>
                {primaryImage}
              </div>
            </div>
          </div>

          {/* 5. Key Variables Sample Pills */}
          <div className="mb-5">
            <div className="text-[11px] font-mono text-[#9aa0b4] mb-1.5">Environment Keys:</div>
            <div className="flex flex-wrap gap-1">
              {egg.variables.slice(0, 3).map((v) => (
                <span
                  key={v.env_variable}
                  className="truncate max-w-[140px] rounded-md border border-white/10 bg-white/5 px-2 py-0.5 font-mono text-[10.5px] text-[#c3b5fc]"
                  title={v.env_variable}
                >
                  {v.env_variable}
                </span>
              ))}
              {egg.variables.length > 3 && (
                <span className="rounded-md border border-white/10 bg-white/5 px-1.5 py-0.5 font-mono text-[10.5px] text-[#9aa0b4]">
                  +{egg.variables.length - 3}
                </span>
              )}
            </div>
          </div>
        </div>

        {/* 6. Footer & Fixed Action Buttons (Always Aligned to Bottom) */}
        <div className="border-t border-white/10 pt-4 mt-auto">
          <div className="flex items-center justify-between text-xs font-mono text-[#9aa0b4] mb-3">
            <span>Features: <b className="text-white">{egg.features.join(", ") || "Standard"}</b></span>
            <span>{relTime(pushed) || fmtDate(pushed)}</span>
          </div>

          <div className="grid grid-cols-2 gap-2">
            <button
              type="button"
              onClick={() => onInspect(egg, collection)}
              className="flex items-center justify-center gap-1.5 rounded-xl border border-white/10 bg-white/5 px-3 py-2 text-xs font-semibold text-white hover:bg-white/10 transition-colors"
            >
              <Sliders className="h-3.5 w-3.5 text-[#a78bfa]" />
              <span>Inspect</span>
            </button>
            <a
              href={downloadUrl}
              download
              className="grad-bg flex items-center justify-center gap-1.5 rounded-xl px-3 py-2 text-xs font-semibold text-white hover:opacity-95 transition-transform hover:-translate-y-px"
            >
              <Download className="h-3.5 w-3.5" />
              <span>egg.json</span>
            </a>
          </div>
        </div>
      </div>
    </MagicCard>
  );
}
