import { defineConfig, type Plugin } from "vite";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const __dir = dirname(fileURLToPath(import.meta.url));

// base "./" keeps every asset path relative, so the build works on
// nest.potenfyr.in today and on any custom
// domain tomorrow without a rebuild.

const CANON = "https://nest.potenfyr.in";

const WEBSITE_JSONLD = {
  "@context": "https://schema.org",
  "@type": "WebSite",
  name: "PotenFYR Nest",
  alternateName: "PotenFYR Egg Catalog",
  url: `${CANON}/`,
  description:
    "The official catalog of PotenFYR Studios multi eggs for Pterodactyl, Pelican and Feather Panel.",
  publisher: { "@type": "Organization", name: "PotenFYR Studios" },
  inLanguage: "en",
};

function breadcrumb(slug: string, name: string) {
  return {
    "@context": "https://schema.org",
    "@type": "BreadcrumbList",
    itemListElement: [
      { "@type": "ListItem", position: 1, name: "Catalog", item: `${CANON}/` },
      { "@type": "ListItem", position: 2, name, item: `${CANON}/${slug}` },
    ],
  };
}

const EXAMPLE_JSONLD = {
  "@context": "https://schema.org",
  "@type": "ItemList",
  name: "Real multi egg JSON examples",
  itemListElement: [
    {
      "@type": "ListItem",
      position: 1,
      item: {
        "@type": "SoftwareSourceCode",
        name: "Multi Database egg definition (PTDL_v2)",
        programmingLanguage: "JSON",
        codeRepository: "https://github.com/PotenFYR-Studios/Database-Eggs",
        downloadUrl:
          "https://raw.githubusercontent.com/PotenFYR-Studios/Database-Eggs/main/egg-database-multi.json",
      },
    },
    {
      "@type": "ListItem",
      position: 2,
      item: {
        "@type": "SoftwareSourceCode",
        name: "Multi Minecraft egg definition (PTDL_v2)",
        programmingLanguage: "JSON",
        codeRepository: "https://github.com/PotenFYR-Studios/Minecraft-Eggs",
        downloadUrl:
          "https://raw.githubusercontent.com/PotenFYR-Studios/Minecraft-Eggs/main/egg-minecraft-multi.json",
      },
    },
    {
      "@type": "ListItem",
      position: 3,
      item: {
        "@type": "SoftwareSourceCode",
        name: "Prog-Language egg definition (PTDL_v2)",
        programmingLanguage: "JSON",
        codeRepository: "https://github.com/PotenFYR-Studios/Prog-Language-Eggs",
        downloadUrl:
          "https://raw.githubusercontent.com/PotenFYR-Studios/Prog-Language-Eggs/main/egg-programming-multi.json",
      },
    },
  ],
};

const PAGES = [
  {
    slug: "about",
    title: "About · PotenFYR Nest",
    description:
      "What PotenFYR Nest is, the multi-egg philosophy behind PotenFYR Studios, and how the catalog syncs from the org's *-Eggs repositories every 30 minutes.",
    jsonld: [
      WEBSITE_JSONLD,
      {
        "@context": "https://schema.org",
        "@type": "AboutPage",
        name: "About · PotenFYR Nest",
        url: `${CANON}/about`,
        description: "About the PotenFYR Nest multi egg catalog and its automated sync pipeline.",
        isPartOf: { "@id": `${CANON}/` },
      },
      breadcrumb("about", "About"),
    ],
  },
  {
    slug: "docs",
    title: "Docs · PotenFYR Nest",
    description:
      "How to browse the catalog, install eggs on Pterodactyl, Pelican and Feather Panel, run them on Docker, read the egg JSON format and contribute new eggs.",
    jsonld: [
      WEBSITE_JSONLD,
      {
        "@context": "https://schema.org",
        "@type": "WebPage",
        name: "Docs · PotenFYR Nest",
        url: `${CANON}/docs`,
        description: "Usage documentation for the PotenFYR Nest multi egg catalog.",
        isPartOf: { "@id": `${CANON}/` },
      },
      breadcrumb("docs", "Docs"),
    ],
  },
  {
    slug: "examples",
    title: "Examples · PotenFYR Nest",
    description:
      "Real multi egg JSON from PotenFYR Studios: Multi Database, Multi Minecraft and 50+ programming languages, with copyable snippets and install commands.",
    jsonld: [WEBSITE_JSONLD, EXAMPLE_JSONLD, breadcrumb("examples", "Examples")],
  },
] as const;

/**
 * Emit /<page>.html and /<page>/index.html copies of the SPA shell with
 * per-page SEO meta + JSON-LD, so every route is directly refreshable on
 * GitHub Pages (pattern: AuthCore docs multiPageEmit).
 */
function multiPageEmit(): Plugin {
  return {
    name: "nest-multi-page",
    closeBundle() {
      const outDir = resolve(__dir, "dist");
      const shell = readFileSync(resolve(outDir, "index.html"), "utf8");

      // Swap the landing SEO meta for this page's meta (applied to both
      // the flat and the subdirectory copy).
      const applyMeta = (html: string, p: (typeof PAGES)[number]) =>
        html
          .replace(/<title>.*?<\/title>/, `<title>${p.title}</title>`)
          .replace(
            /<meta name="description" content="[^"]*" \/>/,
            `<meta name="description" content="${p.description}" />`,
          )
          .replace(
            /<link rel="canonical" href="[^"]*" \/>/,
            `<link rel="canonical" href="${CANON}/${p.slug}" />`,
          )
          .replace(
            /<meta property="og:title" content="[^"]*" \/>/,
            `<meta property="og:title" content="${p.title}" />`,
          )
          .replace(
            /<meta property="og:description" content="[^"]*" \/>/,
            `<meta property="og:description" content="${p.description}" />`,
          )
          .replace(
            /<meta property="og:url" content="[^"]*" \/>/,
            `<meta property="og:url" content="${CANON}/${p.slug}" />`,
          )
          .replace(
            /<meta name="twitter:title" content="[^"]*" \/>/,
            `<meta name="twitter:title" content="${p.title}" />`,
          )
          .replace(
            /<meta name="twitter:description" content="[^"]*" \/>/,
            `<meta name="twitter:description" content="${p.description}" />`,
          )
          .replace(
            "</head>",
            `<script type="application/ld+json">${JSON.stringify(p.jsonld)}</script>\n</head>`,
          );

      for (const p of PAGES) {
        // Flat copy keeps the shell's "./" refs (served at /<slug>.html);
        // the /<slug>/ copy rewrites relative refs one level up.
        const flat = applyMeta(shell, p);
        const sub = shell
          .replace(
            /(src|href|content)="(?!https?:|#|\/|data:|mailto:)([^"]+)"/g,
            '$1="../$2"',
          );
        const subWithMeta = applyMeta(sub, p);

        writeFileSync(resolve(outDir, `${p.slug}.html`), flat);
        mkdirSync(resolve(outDir, p.slug), { recursive: true });
        writeFileSync(resolve(outDir, p.slug, "index.html"), subWithMeta);
      }
    },
  };
}

export default defineConfig({
  base: "./",
  plugins: [react(), tailwindcss(), multiPageEmit()],
  build: {
    outDir: "dist",
    emptyOutDir: true,
    target: "es2020",
  },
});
