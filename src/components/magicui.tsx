import { useEffect, useRef, useState } from "react";
import { motion } from "motion/react";
import { clsx } from "clsx";

/** Magic UI · Number Ticker: counts up to `value` (rAF, no deps quirks). */
export function NumberTicker({
  value,
  className,
}: {
  value: number;
  className?: string;
}) {
  const [display, setDisplay] = useState(0);
  const prev = useRef(0);

  useEffect(() => {
    // hidden tabs and reduced-motion users get the value instantly
    if (typeof document !== "undefined" &&
        (document.hidden || window.matchMedia("(prefers-reduced-motion: reduce)").matches)) {
      prev.current = value;
      setDisplay(value);
      return;
    }
    const from = prev.current;
    const start = performance.now();
    const duration = 900;
    let raf = 0;
    const step = (t: number) => {
      const p = Math.min(1, (t - start) / duration);
      const eased = 1 - Math.pow(1 - p, 3);
      setDisplay(Math.round(from + (value - from) * eased));
      if (p < 1) raf = requestAnimationFrame(step);
      else prev.current = value;
    };
    raf = requestAnimationFrame(step);
    return () => cancelAnimationFrame(raf);
  }, [value]);

  return (
    <span className={className} aria-label={String(value)}>
      {display}
    </span>
  );
}

/** Magic UI · Marquee: seamless infinite scroller (pauses on hover). */
export function Marquee({
  children,
  reverse = false,
  pause = true,
  className,
}: {
  children: React.ReactNode;
  reverse?: boolean;
  pause?: boolean;
  className?: string;
}) {
  return (
    <div
      className={clsx(
        "group flex w-full overflow-hidden [--duration:36s] [--gap:3rem]",
        className,
      )}
    >
      {[0, 1].map((i) => (
        <div
          key={i}
          aria-hidden={i === 1}
          style={{
            animation: `marquee var(--duration) linear infinite`,
            animationDirection: reverse ? "reverse" : "normal",
            animationDelay: i === 1 ? "calc(var(--duration) / -2)" : "0s",
          }}
          className={clsx(
            "flex shrink-0 items-center justify-around [gap:var(--gap)] min-w-full",
            pause && "group-hover:[animation-play-state:paused]",
          )}
        >
          {children}
        </div>
      ))}
      <style>{`@keyframes marquee { from { transform: translateX(0); } to { transform: translateX(calc(-100% - var(--gap))); } }`}</style>
    </div>
  );
}

/** Magic UI · Border Beam: light beam travelling around a rounded border. */
export function BorderBeam({
  size = 120,
  duration = 7,
  className,
}: {
  size?: number;
  duration?: number;
  className?: string;
}) {
  return (
    <div
      className={clsx(
        "pointer-events-none absolute inset-0 rounded-[inherit] border border-transparent [mask-clip:padding-box,border-box] [mask-composite:intersect]",
        className,
      )}
      style={{
        mask: "linear-gradient(#fff 0 0) padding-box, linear-gradient(#fff 0 0)",
      }}
    >
      <motion.div
        className="absolute aspect-square bg-gradient-to-l from-transparent via-[#ec4899] to-transparent rounded-full"
        style={{
          width: size,
          offsetPath: `rect(0 auto auto 0 round ${size / 2}px)`,
        }}
        animate={{ offsetDistance: ["0%", "100%"] }}
        transition={{ repeat: Infinity, ease: "linear", duration }}
      />
    </div>
  );
}

/** Magic UI · Shine Border: animated gradient shimmer around a card. */
export function ShineBorder({
  className,
  duration = 8,
}: {
  className?: string;
  duration?: number;
}) {
  return (
    <motion.div
      aria-hidden
      className={clsx(
        "pointer-events-none absolute inset-0 rounded-[inherit] will-change-transform bg-[length:280%_100%] bg-[linear-gradient(110deg,transparent_35%,rgba(139,92,246,0.55)_46%,rgba(236,72,153,0.55)_52%,rgba(249,115,22,0.5)_58%,transparent_69%)]",
        className,
      )}
      style={{ WebkitMask: "linear-gradient(#fff 0 0) content-box, linear-gradient(#fff 0 0)", WebkitMaskComposite: "xor", maskComposite: "exclude", padding: 1 }}
      animate={{ backgroundPosition: ["0% 0%", "280% 0%"] }}
      transition={{ repeat: Infinity, ease: "linear", duration }}
    />
  );
}

/** Magic UI · Magic Card: cursor spotlight + border glow that track the mouse. */
export function MagicCard({
  children,
  className,
  gradientColor = "rgba(139,92,246,0.10)",
}: {
  children: React.ReactNode;
  className?: string;
  gradientColor?: string;
}) {
  const ref = useRef<HTMLDivElement>(null);
  const [pos, setPos] = useState({ x: -400, y: -400 });
  const [inside, setInside] = useState(false);

  return (
    <div
      ref={ref}
      onMouseMove={(e) => {
        const r = ref.current?.getBoundingClientRect();
        if (r) setPos({ x: e.clientX - r.left, y: e.clientY - r.top });
      }}
      onMouseEnter={() => setInside(true)}
      onMouseLeave={() => setInside(false)}
      className={clsx("group/card relative overflow-hidden rounded-2xl border border-line bg-panel", className)}
    >
      <div
        className="pointer-events-none absolute inset-0 opacity-0 transition-opacity duration-300 group-hover/card:opacity-100"
        style={{
          background: `radial-gradient(320px circle at ${pos.x}px ${pos.y}px, ${gradientColor}, transparent 70%)`,
          opacity: inside ? 1 : 0,
        }}
      />
      {children}
    </div>
  );
}

/** Magic UI · Dot Pattern: decorative dotted backdrop. */
export function DotPattern({ className }: { className?: string }) {
  return (
    <svg aria-hidden className={clsx("pointer-events-none absolute inset-0 h-full w-full", className)}>
      <defs>
        <pattern id="nest-dots" width="26" height="26" patternUnits="userSpaceOnUse">
          <circle cx="2" cy="2" r="1" fill="rgba(139,92,246,0.22)" />
        </pattern>
      </defs>
      <rect width="100%" height="100%" fill="url(#nest-dots)" />
    </svg>
  );
}

/** Magic UI · Meteors: streaking comets in the hero. */
export function Meteors({ number = 12 }: { number?: number }) {
  const meteors = Array.from({ length: number }, (_, i) => ({
    id: i,
    left: (i * 137) % 100,
    delay: ((i * 2.7) % 9).toFixed(1),
    dur: (5 + ((i * 1.3) % 5)).toFixed(1),
  }));
  return (
    <div aria-hidden className="pointer-events-none absolute inset-0 overflow-hidden">
      {meteors.map((m) => (
        <span
          key={m.id}
          className="absolute h-0.5 w-0.5 rotate-[215deg] rounded-full bg-brand-pink shadow-[0_0_0_1px_rgba(236,72,153,0.12)] before:content-[''] before:absolute before:top-1/2 before:h-px before:w-16 before:-translate-y-1/2 before:bg-gradient-to-r before:from-[#ec4899] before:to-transparent"
          style={{
            left: `${m.left}%`,
            top: "-8%",
            animation: `meteor ${m.dur}s linear ${m.delay}s infinite`,
          }}
        />
      ))}
      <style>{`@keyframes meteor { 0% { transform: rotate(215deg) translateX(0); opacity: 1; } 70% { opacity: 1; } 100% { transform: rotate(215deg) translateX(-620px); opacity: 0; } }`}</style>
    </div>
  );
}
