import { useState, useMemo } from "react";
import { motion, AnimatePresence } from "motion/react";
import { X, Search, Copy, Check, Terminal, Layers, Settings2, Download, ExternalLink } from "lucide-react";
import type { Collection, Egg, LiveRepo } from "../lib/types";
import { starsFor } from "../lib/data";

interface Props {
  egg: Egg;
  collection: Collection;
  live: Map<string, LiveRepo>;
  onClose: () => void;
}

export function EggDetailModal({ egg, collection, live, onClose }: Props) {
  const [activeTab, setActiveTab] = useState<"vars" | "docker" | "startup" | "guide">("vars");
  const [varQuery, setVarQuery] = useState("");
  const [copiedKey, setCopiedKey] = useState<string | null>(null);

  const eggUrl = `${collection.url}/blob/${collection.default_branch || "main"}/${egg.path}`;
  const downloadUrl = `./${egg.local.replace(/^public\//, "")}`;

  const copyText = (text: string, key: string) => {
    navigator.clipboard.writeText(text);
    setCopiedKey(key);
    setTimeout(() => setCopiedKey(null), 1800);
  };

  const filteredVars = useMemo(() => {
    if (!varQuery) return egg.variables;
    const q = varQuery.toLowerCase();
    return egg.variables.filter(
      (v) =>
        v.name.toLowerCase().includes(q) ||
        v.env_variable.toLowerCase().includes(q) ||
        v.default_value.toLowerCase().includes(q)
    );
  }, [egg.variables, varQuery]);

  return (
    <AnimatePresence>
      <div className="fixed inset-0 z-50 flex items-center justify-center p-4 sm:p-6 md:p-10">
        {/* Backdrop */}
        <motion.div
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          exit={{ opacity: 0 }}
          onClick={onClose}
          className="fixed inset-0 bg-black/80 backdrop-blur-md"
        />

        {/* Modal Window */}
        <motion.div
          initial={{ opacity: 0, scale: 0.96, y: 12 }}
          animate={{ opacity: 1, scale: 1, y: 0 }}
          exit={{ opacity: 0, scale: 0.96, y: 12 }}
          transition={{ duration: 0.2 }}
          className="relative flex max-h-[90vh] w-full max-w-4xl flex-col rounded-2xl border border-white/10 bg-[#121524] shadow-[0_25px_70px_rgba(0,0,0,0.85)] overflow-hidden"
        >
          {/* Header */}
          <div className="flex items-start justify-between border-b border-white/10 p-6">
            <div className="flex items-start gap-4">
              <div className="flex h-12 w-12 shrink-0 items-center justify-center rounded-xl bg-white/5 border border-white/10 text-2xl">
                {egg.name.includes("Database") ? "🗄️" : egg.name.includes("Minecraft") ? "⚔️" : "⚡"}
              </div>
              <div>
                <div className="flex flex-wrap items-center gap-2">
                  <h2 className="text-xl font-bold tracking-tight text-white">{egg.name}</h2>
                  <span className="rounded-full border border-line bg-white/5 px-2.5 py-0.5 font-mono text-xs text-[#9aa0b4]">
                    ★ {starsFor(collection, live)}
                  </span>
                  <span className="rounded-full border border-line bg-white/5 px-2.5 py-0.5 font-mono text-xs text-[#9aa0b4]">
                    {collection.repo}
                  </span>
                </div>
                <p className="mt-1 text-sm text-[#9aa0b4] line-clamp-2 max-w-2xl">{egg.description}</p>
              </div>
            </div>

            <div className="flex items-center gap-2">
              <a
                href={downloadUrl}
                download
                className="grad-bg flex items-center gap-1.5 rounded-lg px-3 py-1.5 font-mono text-xs font-semibold text-white shadow-sm hover:opacity-95"
              >
                <Download className="h-3.5 w-3.5" />
                <span>egg.json</span>
              </a>
              <button
                type="button"
                onClick={onClose}
                className="rounded-lg p-2 text-[#9aa0b4] hover:bg-white/10 hover:text-white transition-colors"
                aria-label="Close modal"
              >
                <X className="h-5 w-5" />
              </button>
            </div>
          </div>

          {/* Navigation Tabs */}
          <div className="flex border-b border-white/10 px-6 pt-3 gap-2 overflow-x-auto bg-[#0e111d]">
            {[
              { id: "vars", label: `Variables (${egg.variables.length})`, icon: Settings2 },
              { id: "docker", label: `Docker Images (${egg.images.length})`, icon: Layers },
              { id: "startup", label: "Startup Command", icon: Terminal },
              { id: "guide", label: "Panel Install Guide", icon: ExternalLink },
            ].map((tab) => {
              const Icon = tab.icon;
              const active = activeTab === tab.id;
              return (
                <button
                  key={tab.id}
                  type="button"
                  onClick={() => setActiveTab(tab.id as typeof activeTab)}
                  className={`flex items-center gap-2 border-b-2 px-4 py-2.5 text-sm font-medium transition-all ${
                    active
                      ? "border-[#8b5cf6] text-white"
                      : "border-transparent text-[#9aa0b4] hover:text-white"
                  }`}
                >
                  <Icon className={`h-4 w-4 ${active ? "text-[#8b5cf6]" : "text-[#6a7089]"}`} />
                  {tab.label}
                </button>
              );
            })}
          </div>

          {/* Tab Content Body */}
          <div className="flex-1 overflow-y-auto p-6">
            {activeTab === "vars" && (
              <div className="space-y-4">
                <div className="relative">
                  <Search className="pointer-events-none absolute left-3.5 top-1/2 h-4 w-4 -translate-y-1/2 text-[#6a7089]" />
                  <input
                    type="text"
                    value={varQuery}
                    onChange={(e) => setVarQuery(e.target.value)}
                    placeholder="Search variables by name, ENV_KEY, or default value..."
                    className="w-full rounded-xl border border-white/10 bg-black/30 py-2.5 pl-10 pr-4 text-sm text-white placeholder:text-[#6a7089] focus:border-[#8b5cf6] focus:outline-none"
                  />
                </div>

                <div className="overflow-hidden rounded-xl border border-white/10 bg-black/20">
                  <div className="grid grid-cols-12 border-b border-white/10 bg-white/[0.02] px-4 py-2.5 font-mono text-xs font-semibold text-[#9aa0b4]">
                    <div className="col-span-5 sm:col-span-4">Variable Name</div>
                    <div className="col-span-4 sm:col-span-4">Environment Key</div>
                    <div className="col-span-3 sm:col-span-4">Default Value</div>
                  </div>
                  <div className="max-h-[46vh] divide-y divide-white/[0.04] overflow-y-auto">
                    {filteredVars.length === 0 ? (
                      <p className="p-8 text-center text-sm text-[#6a7089]">No variables match your search.</p>
                    ) : (
                      filteredVars.map((v) => (
                        <div
                          key={v.env_variable}
                          className="grid grid-cols-12 items-center px-4 py-3 text-xs transition-colors hover:bg-white/[0.02]"
                        >
                          <div className="col-span-5 sm:col-span-4 font-medium text-white pr-2">
                            {v.name}
                          </div>
                          <div className="col-span-4 sm:col-span-4 font-mono text-[#c3b5fc] flex items-center gap-1.5 pr-2">
                            <span className="truncate">{v.env_variable}</span>
                            <button
                              type="button"
                              onClick={() => copyText(v.env_variable, `var-${v.env_variable}`)}
                              className="shrink-0 text-[#6a7089] hover:text-white"
                              title="Copy environment variable key"
                            >
                              {copiedKey === `var-${v.env_variable}` ? (
                                <Check className="h-3 w-3 text-emerald-400" />
                              ) : (
                                <Copy className="h-3 w-3" />
                              )}
                            </button>
                          </div>
                          <div className="col-span-3 sm:col-span-4 font-mono text-[#9aa0b4] flex items-center gap-1.5">
                            <span className="truncate">{v.default_value || <em className="text-white/20">empty</em>}</span>
                            {v.default_value && (
                              <button
                                type="button"
                                onClick={() => copyText(v.default_value, `val-${v.env_variable}`)}
                                className="shrink-0 text-[#6a7089] hover:text-white"
                                title="Copy default value"
                              >
                                {copiedKey === `val-${v.env_variable}` ? (
                                  <Check className="h-3 w-3 text-emerald-400" />
                                ) : (
                                  <Copy className="h-3 w-3" />
                                )}
                              </button>
                            )}
                          </div>
                        </div>
                      ))
                    )}
                  </div>
                </div>
              </div>
            )}

            {activeTab === "docker" && (
              <div className="space-y-4">
                <p className="text-sm text-[#9aa0b4]">
                  Container images used by this egg. You can pull them directly or inspect them on GHCR:
                </p>
                <div className="space-y-3">
                  {egg.images.map((img) => (
                    <div
                      key={img.uri}
                      className="flex flex-col sm:flex-row sm:items-center justify-between gap-3 rounded-xl border border-white/10 bg-black/30 p-4"
                    >
                      <div>
                        <div className="text-sm font-semibold text-white">{img.name}</div>
                        <div className="mt-1 font-mono text-xs text-[#a78bfa]">{img.uri}</div>
                      </div>
                      <div className="flex items-center gap-2">
                        <button
                          type="button"
                          onClick={() => copyText(`docker pull ${img.uri}`, `pull-${img.uri}`)}
                          className="flex items-center gap-1.5 rounded-lg border border-white/10 bg-white/5 px-3 py-1.5 font-mono text-xs text-[#e8eaf2] hover:bg-white/10 hover:text-white transition-colors"
                        >
                          {copiedKey === `pull-${img.uri}` ? (
                            <>
                              <Check className="h-3.5 w-3.5 text-emerald-400" />
                              <span>Copied command!</span>
                            </>
                          ) : (
                            <>
                              <Copy className="h-3.5 w-3.5" />
                              <span>docker pull</span>
                            </>
                          )}
                        </button>
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            )}

            {activeTab === "startup" && (
              <div className="space-y-4">
                <div className="flex items-center justify-between">
                  <span className="text-sm text-[#9aa0b4]">Default container entrypoint startup command:</span>
                  <button
                    type="button"
                    onClick={() => copyText(egg.startup, "startup")}
                    className="flex items-center gap-1.5 rounded-lg border border-white/10 bg-white/5 px-3 py-1 font-mono text-xs text-white hover:bg-white/10"
                  >
                    {copiedKey === "startup" ? (
                      <>
                        <Check className="h-3 w-3 text-emerald-400" />
                        <span>Copied!</span>
                      </>
                    ) : (
                      <>
                        <Copy className="h-3 w-3" />
                        <span>Copy script</span>
                      </>
                    )}
                  </button>
                </div>
                <pre className="overflow-x-auto rounded-xl border border-white/10 bg-black/50 p-4 font-mono text-xs leading-relaxed text-[#c3b5fc]">
                  <code>{egg.startup}</code>
                </pre>
              </div>
            )}

            {activeTab === "guide" && (
              <div className="space-y-6 text-sm text-[#9aa0b4]">
                <div className="rounded-xl border border-white/10 bg-black/20 p-5">
                  <h3 className="text-base font-semibold text-white mb-2">Importing into Pterodactyl or Pelican</h3>
                  <ol className="list-decimal list-inside space-y-2 leading-relaxed">
                    <li>Download the <a href={downloadUrl} download className="text-[#a78bfa] underline">egg.json</a> file.</li>
                    <li>Log in to your Pterodactyl or Pelican Admin panel.</li>
                    <li>Navigate to <b>Nests</b> &rarr; select an existing Nest (or create a new one).</li>
                    <li>Click <b>Import Egg</b> in the top right.</li>
                    <li>Upload the downloaded <code className="text-white font-mono">{egg.path}</code> file and save.</li>
                    <li>You're ready! Create a new server and pick your new Multi Egg.</li>
                  </ol>
                </div>

                <div className="rounded-xl border border-white/10 bg-black/20 p-5">
                  <h3 className="text-base font-semibold text-white mb-2">Source Repository & Documentation</h3>
                  <p className="mb-3">
                    Every environment variable, supported runtime version, and configuration tweak is thoroughly documented in the source repository:
                  </p>
                  <a
                    href={eggUrl}
                    target="_blank"
                    rel="noopener"
                    className="inline-flex items-center gap-2 text-white font-semibold text-[#8b5cf6] hover:underline"
                  >
                    <span>View {egg.path} on GitHub</span>
                    <ExternalLink className="h-4 w-4" />
                  </a>
                </div>
              </div>
            )}
          </div>
        </motion.div>
      </div>
    </AnimatePresence>
  );
}
