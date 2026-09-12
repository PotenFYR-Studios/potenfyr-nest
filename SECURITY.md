# Security Policy

## Supported versions

The nest site deploys straight from `master` on every sync; there are no
release branches. Always run the latest deployed version; report issues
against `master`.

## Reporting a vulnerability

**Do not open a public issue for a security problem.**

Use GitHub's private vulnerability reporting:
[Security tab → Report a vulnerability](https://github.com/PotenFYR-Studios/potenfyr-nest/security/advisories/new),
or reach the studio through the [Support Discord](https://discord.com/invite/zUaN2FPBec)
(start a thread and mention it is security-related; do not post details
publicly).

Please include:

- what is vulnerable (page, workflow, script, egg mirror),
- how to reproduce it,
- the impact you observed,
- any logs or requests involved.

We will acknowledge reports as fast as we can and coordinate a fix and
disclosure timeline with you.

### Scope notes

- **In scope:** this repository: the site code, `scripts/sync-eggs.sh`,
  `scripts/prerender.mjs`, the sync workflow, and anything served from
  nest.potenfyr.in.
- **Out of scope:** the egg collection repositories (`*-Eggs`); report
  those in the respective repository; GitHub.com infrastructure; automated
  scanner output without a reproducible impact description.

## Safe harbor

We consider good-faith research of our public deployments authorized: we
will not pursue action against anyone who avoids privacy violations,
destroys data, or degrades service, and who reports findings through this
policy.

## Do nots

- Do not test with denial-of-service or spam volume.
- Do not exploit issues for anything beyond minimal proof of impact.
- Do not post exploit code, proof-of-concept payloads or secrets in public
  issues, PRs or the Discord; use the private channels above.
