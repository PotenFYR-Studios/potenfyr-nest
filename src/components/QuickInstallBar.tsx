import { useState } from "react";
import { Copy, Check, Terminal, Server } from "lucide-react";
import type { Catalog } from "../lib/types";

export function QuickInstallBar({ catalog }: { catalog: Catalog }) {
  const [selectedPanel, setSelectedPanel] = useState<"pterodactyl" | "pelican" | "feather" | "docker">("pterodactyl");
  const [selectedEggIndex, setSelectedEggIndex] = useState(0);
  const [copied, setCopied] = useState(false);

  // Flatten eggs with collection info
  const allEggs = catalog.collections.flatMap((c) =>
    c.eggs.map((e) => ({
      egg: e,
      collection: c,
      rawUrl: `https://raw.githubusercontent.com/PotenFYR-Studios/${c.repo}/${c.default_branch || "main"}/${e.path}`,
    }))
  );

  const current = allEggs[selectedEggIndex] || allEggs[0];
  if (!current) return null;

  const getCurlCmd = () => {
    return `curl -sSL -o ${current.egg.path} "${current.rawUrl}"`;
  };

  const copyCommand = () => {
    navigator.clipboard.writeText(getCurlCmd());
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  return (
    <div className="relative overflow-hidden rounded-2xl border border-white/10 bg-gradient-to-b from-white/[0.04] to-transparent p-6 shadow-2xl backdrop-blur-md">
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4 border-b border-white/10 pb-5">
        <div className="flex items-center gap-3">
          <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-[#8b5cf6]/10 border border-[#8b5cf6]/20 text-[#c3b5fc]">
            <Server className="h-5 w-5" />
          </div>
          <div>
            <h3 className="font-semibold text-white text-base">Quick Panel Deployment</h3>
            <p className="text-xs text-[#9aa0b4]">One-click curl or import URL for your game server hosting daemon</p>
          </div>
        </div>

        {/* Panel Selector Pills */}
        <div className="flex flex-wrap gap-1.5 p-1 rounded-xl bg-black/40 border border-white/10">
          {(
            [
              ["pterodactyl", "Pterodactyl"],
              ["pelican", "Pelican"],
              ["feather", "Feather Panel"],
              ["docker", "Docker CLI"],
            ] as const
          ).map(([key, label]) => (
            <button
              key={key}
              type="button"
              onClick={() => setSelectedPanel(key)}
              className={`rounded-lg px-3 py-1 text-xs font-semibold transition-all ${
                selectedPanel === key
                  ? "grad-bg text-white shadow-sm"
                  : "text-[#9aa0b4] hover:text-white hover:bg-white/5"
              }`}
            >
              {label}
            </button>
          ))}
        </div>
      </div>

      <div className="mt-5 flex flex-col md:flex-row md:items-center gap-3">
        {/* Egg selector */}
        <div className="flex shrink-0 items-center gap-2">
          <span className="text-xs font-mono text-[#9aa0b4]">Select Egg:</span>
          <select
            value={selectedEggIndex}
            onChange={(e) => setSelectedEggIndex(Number(e.target.value))}
            className="rounded-xl border border-white/10 bg-[#161927] px-3 py-2 text-xs font-semibold text-white focus:border-[#8b5cf6] focus:outline-none"
          >
            {allEggs.map((item, idx) => (
              <option key={item.egg.path} value={idx}>
                {item.egg.name} ({item.collection.repo})
              </option>
            ))}
          </select>
        </div>

        {/* Command Box */}
        <div className="relative flex-1 flex items-center justify-between rounded-xl border border-white/10 bg-black/50 px-4 py-2 font-mono text-xs text-[#a78bfa] overflow-hidden">
          <div className="flex items-center gap-2 truncate pr-2">
            <Terminal className="h-3.5 w-3.5 text-[#6a7089] shrink-0" />
            <span className="truncate">{getCurlCmd()}</span>
          </div>
          <button
            type="button"
            onClick={copyCommand}
            className="flex shrink-0 items-center gap-1.5 rounded-lg bg-white/10 px-2.5 py-1 text-xs font-sans font-medium text-white hover:bg-white/20 transition-colors"
          >
            {copied ? (
              <>
                <Check className="h-3.5 w-3.5 text-emerald-400" />
                <span className="text-emerald-400">Copied!</span>
              </>
            ) : (
              <>
                <Copy className="h-3.5 w-3.5 text-[#9aa0b4]" />
                <span>Copy</span>
              </>
            )}
          </button>
        </div>
      </div>
    </div>
  );
}
