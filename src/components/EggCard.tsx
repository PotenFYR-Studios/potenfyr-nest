import { MagicCard } from "./magicui";
import { BorderBeam } from "./magicui";
import type { Collection, Egg, LiveRepo } from "../lib/types";
import { pushedFor, starsFor } from "../lib/data";

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

function Chip({ children, href, tone = "violet" }: { children: React.ReactNode; href?: string; tone?: "violet" | "pink" | "orange" }) {
  const tones = {
    violet: "border-[rgba(139,92,246,0.3)] bg-[rgba(139,92,246,0.10)] text-[#c3b5fc]",
    pink: "border-[rgba(236,72,153,0.28)] bg-[rgba(236,72,153,0.09)] text-[#f9a8d4]",
    orange: "border-[rgba(249,115,22,0.3)] bg-[rgba(249,115,22,0.10)] text-[#fdba74]",
  } as const;
  const cls = `inline-flex max-w-full items-center truncate rounded-full border px-2.5 py-0.5 font-mono text-[11.5px] ${tones[tone]}`;
  return href ? (
    <a href={href} target="_blank" rel="noopener" className={`${cls} transition-colors hover:text-white`}>
      {children}
    </a>
  ) : (
    <span className={cls}>{children}</span>
  );
}

export function EggCard({ egg, collection, live }: { egg: Egg; collection: Collection; live: Map<string, LiveRepo> }) {
  const eggUrl = `${collection.url}/blob/${collection.default_branch || "main"}/${egg.path}`;
  const pushed = pushedFor(collection, live);
  const envSample = egg.variables.slice(0, 3).map((v) => v.env_variable).filter(Boolean);

  return (
    <MagicCard className="h-full">
      <div className="relative flex h-full flex-col gap-3 p-5">
        <div className="absolute inset-x-0 top-0 z-10">
          <BorderBeam size={90} duration={9} className="opacity-0 transition-opacity duration-300 group-hover/card:opacity-100" />
        </div>
        <div className="flex items-start justify-between gap-3">
          <h3 className="text-[17px] font-semibold tracking-tight">
            <a href={eggUrl} target="_blank" rel="noopener" title={`egg definition: ${egg.path}`} className="transition-colors hover:text-[#f9a8d4]">
              {egg.name}
            </a>
          </h3>
          <span className="shrink-0 rounded-full border border-[rgba(234,197,79,0.3)] bg-[rgba(234,197,79,0.08)] px-2.5 py-0.5 font-mono text-xs font-semibold text-[#eac54f]">
            ★ {starsFor(collection, live)}
          </span>
        </div>

        <p className="flex-1 text-sm leading-relaxed text-[#9aa0b4]">{egg.description || "No description."}</p>

        <div className="flex flex-wrap gap-1.5">
          <a
            href={`./${egg.local.replace(/^public\//, "")}`}
            download
            className="grad-bg inline-flex items-center rounded-full px-2.5 py-0.5 font-mono text-[11.5px] font-semibold text-white transition-transform hover:-translate-y-px"
            title={`download ${egg.path} (mirrored in this repo)`}
          >
            ⬇ egg.json
          </a>
          <Chip href={eggUrl}>{egg.path}</Chip>
          {egg.variables.length > 0 && <Chip tone="pink">{egg.variables.length} vars</Chip>}
          {egg.images.length > 1 && <Chip tone="pink">{egg.images.length} images</Chip>}
          {egg.features.slice(0, 2).map((f) => (
            <Chip key={f} tone="orange">
              {f}
            </Chip>
          ))}
        </div>

        <div className="flex flex-wrap gap-x-4 gap-y-1.5 border-t border-dashed border-white/10 pt-3 font-mono text-xs text-[#9aa0b4]">
          <span>
            images <b className="font-semibold text-white">{egg.images.length}</b>
          </span>
          <span>
            vars <b className="font-semibold text-white">{egg.variables.length}</b>
          </span>
          {envSample.length > 0 && (
            <span className="min-w-0 truncate" title={egg.variables.map((v) => v.env_variable).join(", ")}>
              env <b className="font-semibold text-white">{envSample.join(", ")}</b>
            </span>
          )}
          <span className="ml-auto shrink-0">
            updated <b className="font-semibold text-white">{fmtDate(pushed)}</b>
          </span>
        </div>
      </div>
    </MagicCard>
  );
}
