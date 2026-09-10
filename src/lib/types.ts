export interface EggVariable {
  name: string;
  env_variable: string;
  default_value: string;
}

export interface EggImage {
  name: string;
  uri: string;
}

export interface Egg {
  path: string;
  /** Repo-relative mirror path (public/eggs/...), for direct downloads. */
  local: string;
  name: string;
  description: string;
  author: string;
  exported_at: string;
  images: EggImage[];
  variables: EggVariable[];
  features: string[];
  startup: string;
}

export interface Collection {
  repo: string;
  url: string;
  description: string;
  topics: string[];
  language: string;
  stars: number;
  forks: number;
  open_issues: number;
  license: string;
  default_branch: string;
  pushed_at: string;
  homepage: string;
  upstream_sha: string;
  eggs: Egg[];
}

export interface Catalog {
  org: string;
  generated_at: string;
  counts: {
    collections: number;
    eggs: number;
    variables: number;
    images: number;
  };
  collections: Collection[];
}

/** Live metadata the site merges over the synced catalog. */
export interface LiveRepo {
  stars: number;
  description: string;
  pushedAt: string;
  archived: boolean;
}
