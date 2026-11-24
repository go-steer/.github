#!/usr/bin/env bash
# Copyright 2026 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# create-repo.sh: create a public repo with the go-steer baseline applied.
#
# Environment:
#   ORG          organization (e.g. go-steer)
#   NAME         repo name, already validated by parse-request.sh
#   DESCRIPTION  one-line description, already validated
#   LANGUAGE     go | javascript | other
#   CODE_OWNER   owner for gate paths in CODEOWNERS, e.g. @mastersingh24
#   GH_TOKEN     go-steer-shipyard installation token (Administration,
#                Contents, Workflows: write)
#   PHASE        create | configure | all (default all)
#                create: only create the empty repo (needs an org-wide
#                token, administration only). configure: everything after
#                (a token scoped to the new repo is enough).
#   DRY_RUN=1    print the API calls instead of making them
#
# Steps, in order: create the repo; add CODEOWNERS and dependabot.yml
# (before the rulesets, so they land without a PR); turn on secret
# scanning, push protection and Dependabot security updates; try CodeQL
# default setup; apply the standard rulesets from shipyard/rulesets/.
# Prints a Markdown summary on stdout for the issue comment. A failure in a
# best-effort step is reported as a warning; a failure in a required step
# exits non-zero.
set -euo pipefail

: "${ORG:?}" "${NAME:?}" "${DESCRIPTION:?}" "${LANGUAGE:?}" "${CODE_OWNER:?}"
here=$(cd "$(dirname "$0")" && pwd)
rulesets="$here/../rulesets"
repo="$ORG/$NAME"
phase=${PHASE:-all}
warnings=()
case "$phase" in create|configure|all) ;; *) echo "PHASE must be create, configure or all" >&2; exit 2 ;; esac

api() { # method path [json-body]
  local method=$1 path=$2 body=${3:-}
  if [[ "${DRY_RUN:-}" == 1 ]]; then
    if [[ -n "$body" ]]; then
      echo "DRY_RUN: $method $path $(jq -c 'if .content then .content = "<\(.content | length) base64 chars>" else . end' <<<"$body")" >&2
    else
      echo "DRY_RUN: $method $path" >&2
    fi
    echo '{}'
    return 0
  fi
  if [[ -n "$body" ]]; then
    gh api -X "$method" "$path" --input - <<<"$body"
  else
    gh api -X "$method" "$path"
  fi
}

put_file() { # path content message
  local body
  body=$(jq -n --arg m "$3" --arg c "$(base64 -w0 <<<"$2")" '{message: $m, content: $c}')
  api PUT "repos/$repo/contents/$1" "$body" >/dev/null
}

if [[ "$phase" != configure ]]; then
# 1. The repo must not exist yet.
if [[ "${DRY_RUN:-}" != 1 ]] && gh api "repos/$repo" >/dev/null 2>&1; then
  echo "Repository $repo already exists." >&2
  exit 1
fi

# 2. Create it: public (rulesets on private repos need a paid plan),
# rebase merges only, initialized so main exists.
api POST "orgs/$ORG/repos" "$(jq -n --arg n "$NAME" --arg d "$DESCRIPTION" '{
  name: $n, description: $d, visibility: "public", auto_init: true,
  has_wiki: false, has_projects: false,
  allow_squash_merge: false, allow_merge_commit: false, allow_rebase_merge: true,
  delete_branch_on_merge: true
}')" >/dev/null

if [[ "${DRY_RUN:-}" != 1 ]]; then
  for _ in $(seq 1 15); do
    gh api "repos/$repo/branches/main" >/dev/null 2>&1 && break
    sleep 2
  done
fi
[[ "$phase" == create ]] && exit 0
fi

# 3. CODEOWNERS and dependabot.yml, before the rulesets exist.
put_file .github/CODEOWNERS "# Paths that must not merge on surveyor's approval alone. No catch-all:
# everything else merges on surveyor's approval. See
# https://github.com/go-steer/surveyor/blob/main/docs/DESIGN.md#61-policy
/.github/CODEOWNERS          $CODE_OWNER
/.github/workflows/          $CODE_OWNER
/.github/dependabot.yml      $CODE_OWNER
/.github/surveyor.yaml       $CODE_OWNER
/dev/ci/                     $CODE_OWNER
/dev/tools/.golangci.yml     $CODE_OWNER" "chore: CODEOWNERS for the merge gate"

ecosystems="github-actions"
case "$LANGUAGE" in
  go) ecosystems="gomod $ecosystems" ;;
  javascript) ecosystems="npm $ecosystems" ;;
esac
dependabot="version: 2
updates:"
for e in $ecosystems; do
  dependabot+="
  - package-ecosystem: \"$e\"
    directory: \"/\"
    schedule:
      interval: \"weekly\""
done
put_file .github/dependabot.yml "$dependabot" "chore: dependabot for $ecosystems"

# 4. Secret scanning, push protection, Dependabot alerts and security updates.
if ! api PATCH "repos/$repo" '{"security_and_analysis": {"secret_scanning": {"status": "enabled"}, "secret_scanning_push_protection": {"status": "enabled"}}}' >/dev/null; then
  warnings+=("Could not turn on secret scanning and push protection.")
fi
if ! { api PUT "repos/$repo/vulnerability-alerts" >/dev/null && api PUT "repos/$repo/automated-security-fixes" >/dev/null; }; then
  warnings+=("Could not turn on Dependabot alerts and security updates.")
fi

# 5. CodeQL default setup. Best effort: with no code yet, GitHub may have no
# language to analyze; the drift check reports repos still without it.
if ! api PATCH "repos/$repo/code-scanning/default-setup" '{"state": "configured", "query_suite": "default"}' >/dev/null 2>&1; then
  warnings+=("CodeQL default setup didn't start (normal for a repo with no code yet). Turn it on after the first code lands.")
fi

# 6. Standard rulesets. Required: without them the repo has no merge gate.
for f in "$rulesets"/main.json "$rulesets"/release-tags.json; do
  api POST "repos/$repo/rulesets" "$(cat "$f")" >/dev/null
done

echo "Created **[$repo](https://github.com/$repo)** with:"
echo
echo "- rebase-only merges; rulesets \`main\` and \`release tags\` from \`shipyard/rulesets/\`"
echo "- \`.github/CODEOWNERS\` (gate paths owned by $CODE_OWNER) and \`.github/dependabot.yml\` ($ecosystems)"
echo "- secret scanning, push protection, Dependabot alerts and security updates"
if ((${#warnings[@]})); then
  echo
  echo "Warnings:"
  for w in "${warnings[@]}"; do echo "- $w"; done
fi
