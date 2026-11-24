# go-steer/.github

Org-wide defaults for [go-steer](https://github.com/go-steer).

GitHub treats a repository named `.github` in an organization specially:
community health files here (`CONTRIBUTING.md`, `SECURITY.md`, issue and PR
templates) apply to every go-steer repo that has none of its own, a
`profile/README.md` would appear on the organization page, and files in
`workflow-templates/` show up under Actions → New workflow.

## What lives here

| Path | What | Status |
|---|---|---|
| `.github/surveyor.yaml` | Org defaults for [surveyor](https://github.com/go-steer/surveyor), the AI code reviewer. Repos override with their own `.github/surveyor.yaml` | Draft |
| `.github/workflows/go-baseline.yml` | Shared Go baseline, called from each repo | Planned |
| `.github/workflows/shipyard.yml` | Creates new repos with the baseline applied, after the maintainer approves | Planned |
| `.github/workflows/ruleset-drift.yml` | Nightly: flags repos whose rulesets differ from the standard | Planned |

Design and decisions: [surveyor `docs/DESIGN.md`](https://github.com/go-steer/surveyor/blob/main/docs/DESIGN.md)
and [`docs/agent-identity.md`](https://github.com/go-steer/surveyor/blob/main/docs/agent-identity.md).

## Calling the shared workflows

Pin to a full commit SHA, as every go-steer workflow pins its actions:

```yaml
jobs:
  baseline:
    uses: go-steer/.github/.github/workflows/go-baseline.yml@<commit-sha>
```

## Changes here

Everything under `.github/` is code-owned: changes need the maintainer's
review, not just surveyor's. Merges are rebase-only.
