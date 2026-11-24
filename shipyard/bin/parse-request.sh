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

# parse-request.sh: validate a shipyard "new repository" issue.
#
# Input (environment; the issue text is untrusted, never interpolated):
#   ISSUE_BODY   the issue body, containing a fenced ```shipyard block
# Output: name, description and language as key=value lines, appended to
# $GITHUB_OUTPUT when set, else printed. On invalid input: a one-line reason
# (never echoing the rejected value, since it is posted as a comment)
# on stderr and exit 1.
#
# Request format (see shipyard/README.md):
#   ```shipyard
#   name: my-repo
#   description: One line saying what it is
#   language: go
#   ```
set -euo pipefail

fail() { echo "$*" >&2; exit 1; }

body=${ISSUE_BODY:-}
body=${body//$'\r'/}

# Lines between the first ```shipyard fence and the next ``` fence.
block=$(awk '
  !in_block && /^[[:space:]]*```shipyard[[:space:]]*$/ { in_block = 1; next }
  in_block && /^[[:space:]]*```[[:space:]]*$/ { found = 1; exit }
  in_block { print }
  END { if (!found) exit 1 }
' <<<"$body") || fail 'No complete ```shipyard block found in the issue body.'

field() {
  # First "key: value" line for $1; value trimmed.
  awk -v k="$1" '
    { line = $0; sub(/^[[:space:]]+/, "", line) }
    index(line, k ":") == 1 {
      v = substr(line, length(k) + 2)
      sub(/^[[:space:]]+/, "", v); sub(/[[:space:]]+$/, "", v)
      print v; exit
    }
  ' <<<"$block"
}

name=$(field name)
description=$(field description)
language=$(field language)
language=${language,,}

[[ -n "$name" ]] || fail "Missing 'name:'."
# GitHub allows more, but go-steer repo names are lowercase, digits and
# hyphens, starting and ending with a letter or digit.
[[ "$name" =~ ^[a-z0-9]([a-z0-9-]{0,98}[a-z0-9])?$ ]] ||
  fail "Invalid name: use 1-100 lowercase letters, digits and hyphens, starting and ending with a letter or digit."
[[ "$name" != *--* ]] || fail "Invalid name: no consecutive hyphens."
[[ "$name" != ".github" ]] || fail "Name '.github' is reserved."

[[ -n "$description" ]] || fail "Missing 'description:'."
(( ${#description} <= 300 )) || fail "Description is ${#description} characters; keep it to 300."
if LC_ALL=C grep -q '[[:cntrl:]]' <<<"$description"; then
  fail "Description contains control characters."
fi

case "$language" in
  go|javascript|other) ;;
  "") fail "Missing 'language:' (go, javascript or other)." ;;
  *) fail "Invalid language: use go, javascript or other." ;;
esac

out=${GITHUB_OUTPUT:-/dev/stdout}
{
  echo "name=$name"
  echo "description=$description"
  echo "language=$language"
} >>"$out"
