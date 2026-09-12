import { useState } from "react";
import type { ReactNode } from "react";
import { SiteHeader, SiteFooter } from "../components/Chrome";
import { DotPattern } from "../components/magicui";

export type TocItem = { id: string; label: string };
export type PageLink = { href: string; label: string };

/** Right-rail "on this page" list with a minimal client-side section filter. */
function TocRail({ items }: { items: TocItem[] }) {
  const [query, setQuery] = useState("");
  const visible = items.filter((item) =>
    item.label.toLowerCase().includes(query.trim().toLowerCase()),
  );
  return (
    <aside className="hidden w-60 shrink-0 xl:block">
      <div className="sticky top-20">
        <p className="mb-3 font-mono text-[11px] font-semibold uppercase tracking-wider text-[#6a7089]">
          On this page
        </p>
        <input
          type="search"
          value={query}
          onChange={(event) => setQuery(event.target.value)}
          placeholder="Filter sections"
          aria-label="Filter sections"
          className="mb-3 w-full rounded-md border border-white/10 bg-white/5 px-2.5 py-1.5 font-mono text-xs text-[#e8eaf2] placeholder:text-[#6a7089] focus:border-[rgba(139,92,246,0.45)] focus:outline-none"
        />
        <ul className="space-y-0.5 border-l border-white/[0.08] text-[13px]">
          {visible.map((item) => (
            <li key={item.id}>
              <a
                href={`#${item.id}`}
                className="block border-l-2 border-transparent py-1 pl-3 text-[#9aa0b4] transition-colors hover:border-[#8b5cf6] hover:text-white"
              >
                {item.label}
              </a>
            </li>
          ))}
          {visible.length === 0 && (
            <li className="py-1 pl-3 text-[#6a7089]">No matching sections</li>
          )}
        </ul>
      </div>
    </aside>
  );
}

/** Bottom-of-page prev/next pagination (ordered by the header nav). */
function Pager({ prev, next }: { prev?: PageLink | null; next?: PageLink | null }) {
  if (!prev && !next) return null;
  return (
    <nav
      aria-label="Page pagination"
      className="mt-16 grid gap-4 border-t border-white/[0.08] pt-6 text-sm sm:grid-cols-2"
    >
      <div>
        {prev && (
          <a href={prev.href} className="group block">
            <span className="font-mono text-[11px] uppercase tracking-wider text-[#6a7089]">Previous</span>
            <span className="block font-semibold text-[#c4b5fd] transition-colors group-hover:text-[#f9a8d4]">
              {prev.label}
            </span>
          </a>
        )}
      </div>
      <div className="sm:text-right">
        {next && (
          <a href={next.href} className="group block">
            <span className="font-mono text-[11px] uppercase tracking-wider text-[#6a7089]">Next</span>
            <span className="block font-semibold text-[#c4b5fd] transition-colors group-hover:text-[#f9a8d4]">
              {next.label}
            </span>
          </a>
        )}
      </div>
    </nav>
  );
}

/**
 * Shared layout for the sub pages: sticky header, breadcrumb eyebrow +
 * gradient h1 head section with the dot-pattern backdrop, and a max-w-6xl
 * content area whose article column pairs with an optional TOC rail.
 */
export function PageShell({
  crumbs,
  title,
  lead,
  children,
  toc,
  prev,
  next,
}: {
  crumbs: string[];
  title: string;
  lead: string;
  children: ReactNode;
  toc?: TocItem[];
  prev?: PageLink | null;
  next?: PageLink | null;
}) {
  return (
    <div className="min-h-screen bg-[#0b0d14] text-[#e8eaf2]">
      <SiteHeader />
      <header className="relative overflow-hidden border-b border-white/[0.08]">
        <DotPattern className="[mask-image:radial-gradient(750px_circle_at_50%_0,white,transparent)]" />
        <div className="relative mx-auto max-w-6xl px-6 pb-12 pt-14">
          <p className="doc-eyebrow mb-3">
            {crumbs.map((crumb, index) => (
              <span key={crumb}>
                {index > 0 && <span className="mx-1.5 text-[#6a7089]">/</span>}
                {index === 0 ? (
                  <a href="/" className="transition-colors hover:text-white">
                    {crumb}
                  </a>
                ) : (
                  crumb
                )}
              </span>
            ))}
          </p>
          <h1 className="grad-text-canonical mb-4 text-balance text-4xl font-extrabold leading-[1.08] tracking-tight sm:text-5xl">
            {title}
          </h1>
          <p className="max-w-2xl text-lg leading-relaxed text-[#9aa0b4]">{lead}</p>
        </div>
      </header>
      <main className="mx-auto max-w-6xl px-6 pb-24">
        <div className="flex gap-10">
          <div className="doc-prose min-w-0 flex-1">{children}</div>
          {toc && toc.length >= 3 ? <TocRail items={toc} /> : null}
        </div>
        <Pager prev={prev} next={next} />
      </main>
      <SiteFooter />
    </div>
  );
}
