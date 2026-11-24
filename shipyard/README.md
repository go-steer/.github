# shipyard

Creates go-steer repositories with the baseline already applied, after the
maintainer approves each one. Background: on GitHub Free, the permission
that creates repos also edits every repo's rulesets, so no agent holds it.
See [surveyor `docs/agent-identity.md`](https://github.com/go-steer/surveyor/blob/main/docs/agent-identity.md#creating-repos-go-steer-shipyard).

## Requesting a repository

Open an issue in `go-steer/.github` titled `shipyard: <name>` with this block
in the body:

````
```shipyard
name: my-repo
description: One line saying what it is
language: go
```
````

- `name`: lowercase letters, digits and hyphens; starts and ends with a letter or digit.
- `description`: one line, up to 300 characters.
- `language`: `go`, `javascript` or `other` (decides the Dependabot ecosystems).

Org owners, members and `go-steer-deckhand` can request; other issues are
ignored. Shipyard comments if the request is invalid and checks again on
every edit. A valid request waits for the maintainer to approve the
`shipyard` deployment (browser or GitHub mobile app). Then it creates the
repo, comments what it did, and closes the issue.

## What a new repo gets

- Public, rebase merges only, branches deleted after merge.
- Rulesets `main` and `release tags`, from [`rulesets/`](./rulesets/).
- `.github/CODEOWNERS` owning the gate paths (workflows, CODEOWNERS,
  `dependabot.yml`, `surveyor.yaml`, `dev/ci/`, lint config), and
  `.github/dependabot.yml` for the language plus GitHub Actions.
- Secret scanning, push protection, Dependabot alerts and security updates.
- CodeQL default setup when GitHub can detect a language. A repo with no
  code yet gets a warning instead; turn CodeQL on after the first code lands.

**Not automatic yet:** while `go-steer-deckhand` is installed on selected
repositories only, add each new repo to its installation by hand.

The two setup commits (CODEOWNERS, `dependabot.yml`) are authored by
`go-steer-shipyard[bot]`. They are machine-generated scaffolding, not agent
work, and they land before the repo has any attribution check.

## One-time setup (maintainer)

1. **Create the `go-steer-shipyard` GitHub App:**
   - Repository permissions: Administration, read and write; Contents,
     read and write; Metadata, read. Nothing else (no Workflows: shipyard
     never writes workflow files).
   - No webhook. Installable only on this account.
   - Install it on **All repositories**, so it can configure repos it creates.
2. **Create the `shipyard` environment** in `go-steer/.github` (Settings →
   Environments):
   - Required reviewers: the maintainer.
   - Deployment branches and tags: selected branches, `main` only.
   - Environment secret `SHIPYARD_PRIVATE_KEY`: the App's private key.
     Store it only here; never give it to an agent.
3. **Repository variables** (Settings → Secrets and variables → Actions →
   Variables):
   - `SHIPYARD_CLIENT_ID`: the App's client ID.
   - `SHIPYARD_CODE_OWNER`: `@mastersingh24`.

The workflow uses two tokens: an org-wide one with administration only, for
the single "create repository" call, and one scoped to the new repo for
everything after.

## Ruleset drift report

[`ruleset-drift.yml`](../.github/workflows/ruleset-drift.yml) runs nightly
(and on demand), compares every public repo's rulesets to
[`rulesets/`](./rulesets/), and keeps one "Ruleset drift report" issue up to
date, closing it when nothing differs. It uses only the workflow's read
token, so it can't see bypass lists (reading those needs admin).

To check locally: `GH_TOKEN=$(gh auth token) shipyard/bin/ruleset-drift.sh`
(or `REPOS="a b"` for a subset).

## Other organizations

Copy this repo into the other org's `.github`, create that org's own
shipyard App and environment, and set the two variables. The scripts read
the organization from the workflow context.

## Tests

`shipyard/bin/test-parse-request.sh` covers request parsing; `checks.yml`
runs it and a dry run of `create-repo.sh` on every PR.
