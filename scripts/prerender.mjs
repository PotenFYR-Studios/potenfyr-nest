/**
 * Prerenders site/dist/index.html so crawlers and AI assistants see the
 * full catalog without executing JavaScript:
 *   - runs the built app in a headless-ish way is overkill here; instead we
 *     inject a static, SEO-complete HTML snapshot of the catalog into #root
 *   - the React app hydrates over it on load (same data, same markup order)
 *
 * Usage: bun scripts/prerender.mjs   (run after `vite build`)
 */
import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const dist = fileURLToPath(new URL("../dist/", import.meta.url));
const html = readFileSync(`${dist}index.html`, "utf8");
const catalog = JSON.parse(readFileSync(`${dist}data/catalog.json`, "utf8"));

const esc = (s) =>
  String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));

const cards = catalog.collections
  .map(
    (c) => `
  <section aria-label="${esc(c.repo)}">
    <h2>${esc(c.repo)}</h2>
    <p>${esc(c.description)}</p>
    <ul>
      ${c.eggs
        .map(
          (e) => `
        <li>
          <h3><a href="${esc(c.url)}/blob/${esc(c.default_branch)}/${esc(e.path)}">${esc(e.name)}</a></h3>
          <p>${esc(e.description)}</p>
          <p>Panel support: ${esc(c.topics.join(", "))}. Variables: ${e.variables.map((v) => esc(v.env_variable)).join(", ")}.</p>
        </li>`,
        )
        .join("")}
    </ul>
  </section>`,
  )
  .join("\n");

const faq = [
  ["What is PotenFYR Nest?", "PotenFYR Nest is the official egg catalog of PotenFYR Studios. It indexes every multi egg the studio publishes for hosting panels and links each egg definition back to its source repository. The catalog is rebuilt automatically every 30 minutes."],
  ["What is a multi egg?", "A multi egg is a single Pterodactyl, Pelican or Feather egg that ships many engines or runtimes in one image and installs what you pick on demand: every database, 50+ programming languages, or every Minecraft server type."],
  ["Which panels are supported?", "Pterodactyl, Pelican and Feather Panel first, and any Docker host: Wisp, PufferPanel, Jexactyl, Emerald, Kubernetes, Fly.io, Railway and Render."],
  ["How do I install an egg?", "Open an egg, download the JSON definition from its source repository, and import it in your panel under Nests, then Eggs."],
  ["Is the catalog up to date?", "Yes. A GitHub Actions workflow rediscovers every eggs repository in the org every 30 minutes, rebuilds catalog.json and redeploys this site. Stars and push times are fetched live from the GitHub API on every page load."],
  ["Can I contribute an egg?", "Yes. Open a pull request in the relevant repository on GitHub. Any JSON file with a name and docker_images object is picked up automatically by the catalog sync."],
];

const staticHtml = `
<div style="position:absolute;left:-9999px">
  <h1>PotenFYR Nest · Every Multi Egg. One Nest.</h1>
  <p>The official catalog of PotenFYR Studios multi eggs for Pterodactyl, Pelican and Feather Panel.</p>
  ${cards}
  <h2>Frequently asked questions</h2>
  ${faq.map(([q, a]) => `<h3>${esc(q)}</h3><p>${esc(a)}</p>`).join("\n")}
</div>`;

// JSON-LD structured data (same graph the React app renders at runtime).
const SITE = "https://nest.potenfyr.in/";
const faqPairs = [
  ["What is PotenFYR Nest?", "PotenFYR Nest is the official egg catalog of PotenFYR Studios. It indexes every multi egg the studio publishes for hosting panels and links each egg definition back to its source repository. The catalog is rebuilt automatically every 30 minutes."],
  ["What is a multi egg?", "A multi egg is a single Pterodactyl, Pelican or Feather egg that ships many engines or runtimes in one image and installs what you pick on demand: every database, 50+ programming languages, or every Minecraft server type."],
  ["Which panels are supported?", "Pterodactyl, Pelican and Feather Panel first, and any Docker host: Wisp, PufferPanel, Jexactyl, Emerald, Kubernetes, Fly.io, Railway and Render."],
  ["How do I install an egg?", "Download the egg JSON from this page or the source repository and import it in your panel under Nests, then Eggs. Each repository README documents every variable."],
  ["Is the catalog up to date?", "Yes. A GitHub Actions workflow rediscovers every eggs repository in the org every 30 minutes, rebuilds catalog.json and redeploys this site. Stars and push times are fetched live from the GitHub API on every page load."],
  ["Can I contribute an egg?", "Yes. Open a pull request in the relevant repository on GitHub. Any JSON file with a name and docker_images object is picked up automatically by the catalog sync."],
];
const graph = [
  {
    "@context": "https://schema.org",
    "@type": "Organization",
    name: "PotenFYR Studios",
    url: "https://potenfyr.in",
    logo: `${SITE}og.png`,
    sameAs: [
      "https://github.com/PotenFYR-Studios",
      "https://modrinth.com/organization/potenfyr",
      "https://discord.com/invite/zUaN2FPBec",
    ],
  },
  {
    "@context": "https://schema.org",
    "@type": "WebSite",
    name: "PotenFYR Nest",
    alternateName: "PotenFYR Egg Catalog",
    url: SITE,
    description: "The official catalog of PotenFYR Studios multi eggs for Pterodactyl, Pelican and Feather Panel.",
    publisher: { "@type": "Organization", name: "PotenFYR Studios" },
    inLanguage: "en",
  },
  ...catalog.collections.flatMap((c) =>
    c.eggs.map((e) => ({
      "@context": "https://schema.org",
      "@type": "SoftwareApplication",
      name: e.name,
      applicationCategory: "ServerApplication",
      operatingSystem: "Docker, Linux",
      description: e.description || `${e.name} multi egg by PotenFYR Studios.`,
      url: `${c.url}/blob/${c.default_branch}/${e.path}`,
      downloadUrl: `${SITE}${e.local.replace(/^public\//, "")}`,
      author: { "@type": "Organization", name: "PotenFYR Studios", url: "https://potenfyr.in" },
      license: c.license || "MIT",
      keywords: [...c.topics, ...e.images.map((i) => i.name)].join(", "),
      offers: { "@type": "Offer", price: "0", priceCurrency: "USD" },
    })),
  ),
  {
    "@context": "https://schema.org",
    "@type": "FAQPage",
    mainEntity: faqPairs.map(([q, a]) => ({
      "@type": "Question",
      name: q,
      acceptedAnswer: { "@type": "Answer", text: a },
    })),
  },
];
const jsonLd = `<script type="application/ld+json">${JSON.stringify(graph)}</script>`;

// The React app replaces #root content on mount; crawlers without JS read this.
const out = html
  .replace('<div id="root"></div>', `<div id="root">${staticHtml}</div>`)
  .replace("</head>", `${jsonLd}</head>`);
writeFileSync(`${dist}index.html`, out);
console.log(`prerendered ${dist}index.html (${catalog.counts.eggs} eggs, ${catalog.counts.collections} collections, ${graph.length} JSON-LD nodes)`);
