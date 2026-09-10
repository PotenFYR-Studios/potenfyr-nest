/* PotenFYR Nest — renders docs/data/catalog.json, then live-refreshes
   stars / descriptions / push dates from the public GitHub API on load. */

(() => {
  "use strict";

  const ORG = "PotenFYR-Studios";
  const state = { catalog: null, live: new Map(), tab: "all", query: "" };

  const $ = (id) => document.getElementById(id);
  const esc = (s) => String(s ?? "").replace(/[&<>"']/g,
    (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
  const fmtDate = (iso) => {
    if (!iso) return "—";
    const d = new Date(iso);
    return isNaN(d) ? "—" : d.toLocaleDateString(undefined, { year: "numeric", month: "short", day: "numeric" });
  };
  const relTime = (iso) => {
    if (!iso) return "";
    const s = (Date.now() - new Date(iso).getTime()) / 1000;
    if (isNaN(s)) return "";
    const units = [[86400, "d"], [3600, "h"], [60, "m"]];
    for (const [sec, label] of units) if (s >= sec) return `${Math.floor(s / sec)}${label} ago`;
    return "just now";
  };

  /* ---------- data loading ---------- */

  async function loadCatalog() {
    const res = await fetch("data/catalog.json", { cache: "no-store" });
    if (!res.ok) throw new Error(`catalog.json HTTP ${res.status}`);
    return res.json();
  }

  // Live layer: public repo metadata, in one batched call. Best-effort —
  // on rate limit / offline the synced catalog stays authoritative.
  async function loadLiveMetadata(repos) {
    const res = await fetch(`https://api.github.com/orgs/${ORG}/repos?per_page=100`, { cache: "no-store" });
    if (!res.ok) throw new Error(`GitHub API HTTP ${res.status}`);
    const data = await res.json();
    const map = new Map();
    for (const r of data) {
      map.set(r.name, {
        stars: r.stargazers_count,
        description: r.description || "",
        pushedAt: r.pushed_at,
        archived: r.archived,
      });
    }
    return map;
  }

  /* ---------- rendering ---------- */

  function starsFor(repo) {
    const live = state.live.get(repo);
    const col = state.catalog.collections.find((c) => c.repo === repo);
    const n = live ? live.stars : (col ? col.stars : 0);
    return n;
  }

  function pushedFor(col) {
    const live = state.live.get(col.repo);
    return live ? live.pushedAt : col.pushed_at;
  }

  function describeCollection(col) {
    const live = state.live.get(col.repo);
    return (live && live.description) || col.description || "";
  }

  function visibleCollections() {
    return state.catalog.collections.filter((c) => {
      if (state.tab !== "all" && c.repo !== state.tab) return false;
      if (!state.query) return true;
      const q = state.query.toLowerCase();
      const hay = [
        c.repo,
        describeCollection(c),
        ...c.eggs.map((e) => [e.name, e.description, e.path,
          ...e.variables.map((v) => `${v.name} ${v.env_variable}`),
          ...e.images.map((i) => i.name)].join(" ")),
      ].join(" ").toLowerCase();
      return hay.includes(q);
    });
  }

  function eggTags(egg) {
    const tags = [];
    if (egg.variables.length) tags.push(`${egg.variables.length} vars`);
    if (egg.images.length > 1) tags.push(`${egg.images.length} images`);
    for (const f of egg.features.slice(0, 2)) tags.push(esc(f));
    return tags;
  }

  function render() {
    const cols = visibleCollections();

    // collection tabs (always all, even when filtered)
    const tabs = $("tabs");
    tabs.innerHTML = "";
    const mk = (key, label) => {
      const b = document.createElement("button");
      b.className = "tab" + (state.tab === key ? " active" : "");
      b.setAttribute("role", "tab");
      b.textContent = label;
      b.addEventListener("click", () => { state.tab = key; render(); });
      tabs.appendChild(b);
    };
    mk("all", `All (${state.catalog.counts.eggs})`);
    for (const c of state.catalog.collections) mk(c.repo, `${c.repo.replace(/-Eggs$/, "")} (${c.eggs.length})`);

    const root = $("collections");
    root.innerHTML = "";

    for (const c of cols) {
      const sec = document.createElement("section");
      sec.className = "collection";
      const stars = starsFor(c.repo);
      const pushed = pushedFor(c);
      const desc = describeCollection(c);

      const head = document.createElement("div");
      head.className = "collection-head";
      head.innerHTML = `
        <h2><a href="${esc(c.url)}" target="_blank" rel="noopener">${esc(c.repo)}</a></h2>
        <span class="badge">${c.eggs.length} egg${c.eggs.length === 1 ? "" : "s"}</span>
        <span class="badge">★ ${stars}</span>
        <span class="badge">pushed ${esc(relTime(pushed)) || fmtDate(pushed)}</span>`;
      if (desc) {
        const p = document.createElement("p");
        p.className = "collection-desc";
        p.textContent = desc;
        sec.appendChild(p);
      }
      sec.appendChild(head);

      const grid = document.createElement("div");
      grid.className = "grid";

      for (const egg of c.eggs) {
        const card = document.createElement("article");
        card.className = "card";
        const tags = eggTags(egg);
        const firstEnv = egg.variables.slice(0, 3)
          .map((v) => v.env_variable).filter(Boolean);
        const eggUrl = `${c.url}/blob/${c.default_branch || "main"}/${egg.path}`;
        card.innerHTML = `
          <div class="card-top">
            <h3 class="card-title"><a href="${esc(eggUrl)}" target="_blank" rel="noopener" title="egg definition: ${esc(egg.path)}">${esc(egg.name)}</a></h3>
            <span class="stars">★ ${stars}</span>
          </div>
          <p class="card-desc">${esc(egg.description) || "<em>No description.</em>"}</p>
          <div class="card-tags">
            <a class="tag" href="${esc(eggUrl)}" target="_blank" rel="noopener">${esc(egg.path)}</a>
            ${tags.map((t) => `<span class="tag pink">${t}</span>`).join("")}
          </div>
          <div class="card-meta">
            <span>vars <b>${egg.variables.length}</b></span>
            <span>images <b>${egg.images.length}</b></span>
            ${firstEnv.length ? `<span title="${esc(egg.variables.map((v) => v.env_variable).join(", "))}">env <b>${esc(firstEnv.join(", "))}</b></span>` : ""}
            <span>updated <b>${esc(fmtDate(pushed))}</b></span>
          </div>`;
        grid.appendChild(card);
      }

      sec.appendChild(grid);
      root.appendChild(sec);
    }

    $("empty").classList.toggle("hidden", cols.length > 0);
  }

  function renderStats() {
    let eggs = 0, variables = 0, images = 0;
    for (const c of state.catalog.collections) {
      eggs += c.eggs.length;
      for (const e of c.eggs) { variables += e.variables.length; images += e.images.length; }
    }
    $("stat-collections").textContent = state.catalog.collections.length;
    $("stat-eggs").textContent = eggs;
    $("stat-variables").textContent = variables;
    $("stat-images").textContent = images;
  }

  /* ---------- boot ---------- */

  async function main() {
    try {
      state.catalog = await loadCatalog();
    } catch (err) {
      $("sync-text").textContent = "catalog unavailable — is the sync workflow green?";
      document.querySelector(".pulse").style.background = "var(--orange)";
      console.error(err);
      return;
    }

    renderStats();
    render();
    $("sync-text").textContent =
      `synced ${fmtDate(state.catalog.generated_at)} · refreshing live data…`;

    // live refresh pass
    try {
      state.live = await loadLiveMetadata();
      renderStats();
      render();
      const t = state.catalog.generated_at;
      $("sync-text").textContent =
        `live ★ counts & push times from api.github.com · catalog synced ${fmtDate(t)}`;
      const note = $("live-note");
      note.textContent = "● live: stars, descriptions and push dates below are fetched fresh from the GitHub API on every page load.";
      note.classList.remove("hidden");
    } catch (err) {
      $("sync-text").textContent =
        `synced data shown (GitHub API rate-limited) · catalog generated ${fmtDate(state.catalog.generated_at)}`;
      console.warn("live refresh skipped:", err);
    }
  }

  $("search").addEventListener("input", (e) => { state.query = e.target.value.trim(); render(); });

  main();
})();
