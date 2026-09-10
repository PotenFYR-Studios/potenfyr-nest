import type { Collection, Egg, LiveRepo } from "./types";
import { catalogSeed } from "../../generated/catalog.seed";

export { catalogSeed };

export function starsFor(c: Collection, live: Map<string, LiveRepo>) {
  return live.get(c.repo)?.stars ?? c.stars;
}

export function pushedFor(c: Collection, live: Map<string, LiveRepo>) {
  return live.get(c.repo)?.pushedAt ?? c.pushed_at;
}

export function describeFor(c: Collection, live: Map<string, LiveRepo>) {
  return live.get(c.repo)?.description || c.description;
}

export function eggHay(c: Collection, e: Egg) {
  return [
    e.name,
    e.description,
    e.path,
    c.repo,
    ...c.topics,
    ...e.variables.map((v) => `${v.name} ${v.env_variable}`),
    ...e.images.map((i) => i.name),
  ]
    .join(" ")
    .toLowerCase();
}
