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

# ruleset-drift.sh: compare every public repo's rulesets to the standard in
# shipyard/rulesets/ and print a Markdown report.
#
# Environment:
#   ORG       organization (default go-steer)
#   GH_TOKEN  any token that can read the org's public repos
#   REPOS     optional space-separated subset of repo names
#
# A repo drifts if a standard ruleset is missing, not active, has different
# conditions, or lacks a standard rule or rule parameter value (objects are
# compared as values, so key order doesn't matter). Extra rules
# are allowed (they can only add restrictions). Bypass lists are compared
# only when the token can see them (it needs admin on the repo); otherwise
# the report says they were not checked.
#
# Exit status: 0 always when the report was produced; the first line of
# output is "drift: N" for the caller.
set -euo pipefail

ORG=${ORG:-go-steer}
here=$(cd "$(dirname "$0")" && pwd)
standards=("$here/../rulesets/main.json" "$here/../rulesets/release-tags.json")

if [[ -n "${REPOS:-}" ]]; then
  read -r -a repos <<<"$REPOS"
else
  mapfile -t repos < <(gh api --paginate "orgs/$ORG/repos?type=public&per_page=100" \
    --jq '.[] | select(.archived | not) | .name' | sort)
fi

# compare STANDARD_JSON ACTUAL_JSON -> one problem per line (empty = match)
compare() {
  jq -nr --argjson s "$1" --argjson a "$2" '
    def params($rules): $rules | map({key: .type, value: (.parameters // {})}) | from_entries;
    (params($s.rules)) as $sr | (params($a.rules)) as $ar |
    [
      (if $a.enforcement != $s.enforcement then "enforcement is \($a.enforcement), want \($s.enforcement)" else empty end),
      (if $a.target != $s.target then "target is \($a.target), want \($s.target)" else empty end),
      (if $a.conditions != $s.conditions then "conditions differ: \($a.conditions | tojson)" else empty end),
      ($sr | to_entries[] | .key as $t | .value as $p |
        if ($ar | has($t) | not) then "missing rule \($t)"
        else ($p | to_entries[] | select($ar[$t][.key] != .value) |
              "rule \($t): \(.key) is \($ar[$t][.key] | tojson), want \(.value | tojson)")
        end),
      (if $a.bypass_actors == null then empty
       elif ($a.bypass_actors | sort) != ($s.bypass_actors | sort)
       then "bypass list differs: \($a.bypass_actors | tojson)" else empty end)
    ] | .[]'
}

drifted=0 checked=0 bypass_unchecked=0
report=""
for r in "${repos[@]}"; do
  checked=$((checked + 1))
  list=$(gh api "repos/$ORG/$r/rulesets?includes_parents=false" 2>/dev/null || echo '[]')
  problems=""
  for f in "${standards[@]}"; do
    std=$(cat "$f")
    sname=$(jq -r .name <<<"$std")
    id=$(jq -r --arg n "$sname" 'map(select(.name == $n)) | .[0].id // empty' <<<"$list")
    if [[ -z "$id" ]]; then
      problems+="- missing ruleset \`$sname\`"$'\n'
      continue
    fi
    actual=$(gh api "repos/$ORG/$r/rulesets/$id")
    if [[ $(jq -r '.bypass_actors == null' <<<"$actual") == true ]]; then
      bypass_unchecked=1
    fi
    while IFS= read -r p; do
      [[ -n "$p" ]] && problems+="- \`$sname\`: $p"$'\n'
    done < <(compare "$std" "$actual")
  done
  if [[ -n "$problems" ]]; then
    drifted=$((drifted + 1))
    report+="### [$r](https://github.com/$ORG/$r/rules)"$'\n\n'"$problems"$'\n'
  fi
done

echo "drift: $drifted"
echo
echo "Compared $checked public repos in **$ORG** against \`shipyard/rulesets/\` on $(date -u +%Y-%m-%d)."
if ((bypass_unchecked)); then
  echo "Bypass lists were not checked for some repos: reading them needs admin access."
fi
echo
if ((drifted == 0)); then
  echo "No drift."
else
  echo "**$drifted repos differ from the standard:**"
  echo
  printf '%s' "$report"
fi
