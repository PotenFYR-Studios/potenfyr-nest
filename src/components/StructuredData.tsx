import { catalogSeed } from "../lib/data";

const SITE = "https://potenfyr-studios.github.io/potenfyr-nest/";

/**
 * JSON-LD structured data (2026 SEO/GEO): Organization + WebSite +
 * SoftwareApplication entries and a FAQPage generated from the live catalog.
 * Injected as a script tag so crawlers and AI answer engines read it.
 */
export function StructuredData() {
  const org = {
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
  };

  const website = {
    "@context": "https://schema.org",
    "@type": "WebSite",
    name: "PotenFYR Nest",
    alternateName: "PotenFYR Egg Catalog",
    url: SITE,
    description:
      "The official catalog of PotenFYR Studios multi eggs for Pterodactyl, Pelican and Feather Panel.",
    publisher: { "@type": "Organization", name: "PotenFYR Studios" },
    inLanguage: "en",
  };

  const apps = catalogSeed.collections.flatMap((c) =>
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
  );

  const faqs = [
    [
      "What is PotenFYR Nest?",
      "PotenFYR Nest is the official egg catalog of PotenFYR Studios. It indexes every multi egg the studio publishes for hosting panels and links each egg definition back to its source repository. The catalog is rebuilt automatically every 30 minutes.",
    ],
    [
      "What is a multi egg?",
      "A multi egg is a single Pterodactyl, Pelican or Feather egg that ships many engines or runtimes in one image and installs what you pick on demand: every database, 50+ programming languages, or every Minecraft server type.",
    ],
    [
      "Which panels are supported?",
      "Pterodactyl, Pelican and Feather Panel first, and any Docker host: Wisp, PufferPanel, Jexactyl, Emerald, Kubernetes, Fly.io, Railway and Render.",
    ],
    [
      "How do I install an egg?",
      "Download the egg JSON from this page or the source repository and import it in your panel under Nests, then Eggs. Each repository README documents every variable.",
    ],
    [
      "Is the catalog up to date?",
      "Yes. A GitHub Actions workflow rediscovers every eggs repository in the org every 30 minutes, rebuilds catalog.json and redeploys this site. Stars and push times are fetched live from the GitHub API on every page load.",
    ],
    [
      "Can I contribute an egg?",
      "Yes. Open a pull request in the relevant repository on GitHub. Any JSON file with a name and docker_images object is picked up automatically by the catalog sync.",
    ],
  ].map(([q, a]) => ({
    "@type": "Question",
    name: q,
    acceptedAnswer: { "@type": "Answer", text: a },
  }));

  const faqPage = {
    "@context": "https://schema.org",
    "@type": "FAQPage",
    mainEntity: faqs,
  };

  const graph = [org, website, ...apps, faqPage];

  return (
    <script
      type="application/ld+json"
      // eslint-disable-next-line react/no-danger
      dangerouslySetInnerHTML={{ __html: JSON.stringify(graph) }}
    />
  );
}
