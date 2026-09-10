import { useCallback, useEffect, useRef, useState } from "react";
import type { Catalog, LiveRepo } from "./types";

const ORG = "PotenFYR-Studios";

function useLiveRef() {
  const ref = useRef(new Map<string, LiveRepo>());
  const [, force] = useState(0);
  const setLive = useCallback((map: Map<string, LiveRepo>) => {
    ref.current = map;
    force((n) => n + 1);
  }, []);
  return { live: ref.current, setLive };
}

export function useNestData() {
  const [catalog, setCatalog] = useState<Catalog | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [liveState, setLiveState] = useState<"pending" | "live" | "fallback">("pending");
  const { live, setLive } = useLiveRef();

  useEffect(() => {
    let cancelled = false;
    let timer;

    const pull = async () => {
      try {
        const res = await fetch("./data/catalog.json", { cache: "no-store" });
        if (!res.ok) throw new Error(`catalog.json HTTP ${res.status}`);
        const data = (await res.json()) as Catalog;
        if (!cancelled) setCatalog(data);
      } catch (e) {
        if (!cancelled) setError(e instanceof Error ? e.message : String(e));
        return;
      }

      // live pass: merge fresh org metadata over the synced catalog
      try {
        const res = await fetch(`https://api.github.com/orgs/${ORG}/repos?per_page=100`, {
          cache: "no-store",
        });
        if (!res.ok) throw new Error(`GitHub API HTTP ${res.status}`);
        const repos = (await res.json()) as Array<Record<string, unknown>>;
        const map = new Map<string, LiveRepo>();
        for (const r of repos) {
          map.set(r.name as string, {
            stars: r.stargazers_count as number,
            description: (r.description as string) || "",
            pushedAt: r.pushed_at as string,
            archived: r.archived as boolean,
          });
        }
        if (!cancelled) {
          setLive(map);
          setLiveState("live");
        }
      } catch {
        if (!cancelled) setLiveState("fallback");
      }
    };

    pull();
    // keep the page live while it stays open: re-pull every 5 minutes
    timer = setInterval(pull, 5 * 60 * 1000);

    return () => {
      cancelled = true;
      clearInterval(timer);
    };
  }, [setLive]);

  return { catalog, error, live, liveState };
}
