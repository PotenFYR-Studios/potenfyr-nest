import Landing from "./pages/Landing";
import AboutPage from "./pages/About";
import DocsPage from "./pages/Docs";
import ExamplesPage from "./pages/Examples";

/**
 * Path router. Every route is also a real HTML file emitted at build time
 * (vite multiPageEmit), so direct refresh works on every route; this only
 * decides which page the shared SPA shell renders.
 */
function route(): "landing" | "about" | "docs" | "examples" {
  if (typeof window === "undefined") return "landing";
  const p = window.location.pathname.replace(/\/+$/, "").replace(/\.html$/, "");
  if (p === "/about") return "about";
  if (p === "/docs") return "docs";
  if (p === "/examples") return "examples";
  return "landing";
}

export default function App() {
  switch (route()) {
    case "about":
      return <AboutPage />;
    case "docs":
      return <DocsPage />;
    case "examples":
      return <ExamplesPage />;
    default:
      return <Landing />;
  }
}
