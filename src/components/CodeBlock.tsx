import { useRef, useState } from "react";
import { Check, Copy } from "lucide-react";

/**
 * Code / JSON block with the house copy button (SPEC §5.8): hidden until
 * hover or keyboard focus, flips to an emerald "Copied!" for ~1.4s.
 */
export function CodeBlock({
  code,
  label,
  filename,
}: {
  code: string;
  /** Optional mono chip shown above the code (e.g. language or origin). */
  label?: string;
  /** Optional filename shown in the label row (right side). */
  filename?: string;
}) {
  const [copied, setCopied] = useState(false);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);

  const copy = () => {
    navigator.clipboard.writeText(code).then(() => {
      setCopied(true);
      if (timer.current) clearTimeout(timer.current);
      timer.current = setTimeout(() => setCopied(false), 1400);
    });
  };

  return (
    <div className="group relative overflow-hidden rounded-xl border border-[rgba(139,92,246,0.16)] bg-[#151828] shadow-[0_1px_2px_rgba(0,0,0,0.5),0_8px_28px_rgba(0,0,0,0.4)]">
      {(label || filename) && (
        <div className="flex items-center justify-between gap-3 border-b border-white/[0.06] px-4 py-2">
          {label && (
            <span className="font-mono text-[11px] uppercase tracking-[0.14em] text-[#6a7089]">{label}</span>
          )}
          {filename && (
            <span className="truncate font-mono text-[11px] text-[#9aa0b4]">{filename}</span>
          )}
        </div>
      )}
      <pre className="overflow-x-auto p-4 pr-20 font-mono text-[13px] leading-[1.65] text-[#dfe2ef]">
        <code>{code}</code>
      </pre>
      <button
        type="button"
        onClick={copy}
        aria-label="Copy to clipboard"
        className={`absolute top-2.5 right-2.5 flex items-center gap-1.5 rounded-md border px-2.5 py-1 font-mono text-[11px] font-semibold opacity-0 transition-opacity focus-visible:opacity-100 group-hover:opacity-100 ${
          copied
            ? "border-[rgba(16,185,129,0.4)] bg-[rgba(16,185,129,0.1)] text-[#34d399] opacity-100"
            : "border-white/[0.08] bg-white/5 text-[#9aa0b4] hover:border-[rgba(139,92,246,0.5)] hover:text-white"
        }`}
      >
        {copied ? <Check className="h-3.5 w-3.5" /> : <Copy className="h-3.5 w-3.5" />}
        {copied ? "Copied!" : "Copy"}
      </button>
    </div>
  );
}
