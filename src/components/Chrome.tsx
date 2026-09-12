/**
 * Shared site chrome: the sticky 56px blur navbar (SPEC §5.1) and the
 * three-zone footer (SPEC §5.2) used by every route.
 */

const NAV = [
  { href: "/", label: "Catalog" },
  { href: "/about", label: "About" },
  { href: "/docs", label: "Docs" },
  { href: "/examples", label: "Examples" },
];

function currentPath(): string {
  if (typeof window === "undefined") return "/";
  const p = window.location.pathname.replace(/\/+$/, "");
  return p === "" ? "/" : p;
}

export function SiteHeader() {
  const active = currentPath();
  return (
    <nav className="sticky top-0 z-50 border-b border-white/[0.08] bg-[rgba(11,13,20,0.72)] [backdrop-filter:blur(14px)_saturate(1.4)]">
      <div className="mx-auto flex h-14 max-w-7xl items-center justify-between gap-4 px-6">
        <a href="/" className="group flex shrink-0 items-center gap-2.5 font-mono text-lg font-bold">
          <span className="flex h-9 w-9 items-center justify-center rounded-xl bg-white/5 border border-white/10 text-xl shadow-inner transition-transform group-hover:scale-105">
            🥚
          </span>
          <span>
            PotenFYR&nbsp;<span className="grad-text">Nest</span>
          </span>
        </a>

        <div className="hidden items-center gap-1 text-sm md:flex">
          {NAV.map((item) => {
            const isActive = active === item.href;
            return (
              <a
                key={item.href}
                href={item.href}
                aria-current={isActive ? "page" : undefined}
                className={`rounded-md px-2.5 py-1 font-medium transition-colors ${
                  isActive
                    ? "bg-[rgba(139,92,246,0.18)] text-white shadow-[inset_0_0_0_1px_rgba(139,92,246,0.45)]"
                    : "text-[#9aa0b4] hover:bg-white/5 hover:text-white"
                }`}
              >
                {item.label}
              </a>
            );
          })}
        </div>

        <div className="flex items-center gap-3 text-sm text-[#9aa0b4]">
          <a
            className="hidden transition-colors hover:text-white lg:inline-block"
            href="https://github.com/PotenFYR-Studios"
            target="_blank"
            rel="noopener"
          >
            GitHub
          </a>
          <a
            className="hidden transition-colors hover:text-white lg:inline-block"
            href="https://potenfyr.in"
            target="_blank"
            rel="noopener"
          >
            Website
          </a>
          <a
            className="hidden transition-colors hover:text-white lg:inline-block"
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
      </div>
    </nav>
  );
}

export function SiteFooter() {
  return (
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

          <div className="flex flex-wrap items-center justify-center gap-x-5 gap-y-2 text-xs font-mono text-[#9aa0b4]">
            <a href="/about" className="hover:text-white transition-colors">
              About
            </a>
            <a href="/docs" className="hover:text-white transition-colors">
              Docs
            </a>
            <a href="/examples" className="hover:text-white transition-colors">
              Examples
            </a>
            <a
              href="https://github.com/PotenFYR-Studios/potenfyr-nest/blob/master/LICENSE"
              target="_blank"
              rel="noopener"
              className="hover:text-white transition-colors"
            >
              License
            </a>
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
            <a href="/data/catalog.json" target="_blank" rel="noopener" className="text-[#a78bfa] hover:underline">
              data/catalog.json
            </a>
          </div>
        </div>

        <div className="mt-8 border-t border-white/[0.06] pt-6 flex flex-col sm:flex-row items-center justify-between gap-3 text-xs text-[#6a7089]">
          <span>© {new Date().getFullYear()} PotenFYR Studios. Released under Apache-2.0 with the Commons Clause.</span>
          <span>Crafted with ❤️ for Pterodactyl, Pelican & Feather Panel communities</span>
        </div>
      </div>
    </footer>
  );
}
