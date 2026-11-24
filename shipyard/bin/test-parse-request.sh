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

# Tests for parse-request.sh. Run: shipyard/bin/test-parse-request.sh
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
pass=0 failn=0

expect_ok() { # label body expected-output
  local got
  if got=$(GITHUB_OUTPUT='' ISSUE_BODY=$2 "$here/parse-request.sh" 2>&1) && [[ "$got" == "$3" ]]; then
    pass=$((pass + 1))
  else
    failn=$((failn + 1)); printf 'FAIL %s\n  got: %q\n  want: %q\n' "$1" "$got" "$3"
  fi
}
expect_err() { # label body error-substring
  local got
  if got=$(GITHUB_OUTPUT='' ISSUE_BODY=$2 "$here/parse-request.sh" 2>&1); then
    failn=$((failn + 1)); printf 'FAIL %s: accepted, output %q\n' "$1" "$got"
  elif [[ "$got" == *"$3"* ]]; then
    pass=$((pass + 1))
  else
    failn=$((failn + 1)); printf 'FAIL %s\n  got: %q\n  want substring: %q\n' "$1" "$got" "$3"
  fi
}

fence='```'
ok_body="Please create this.

${fence}shipyard
name: my-repo
description: A small tool, with commas & symbols: fine
language: Go
${fence}

Thanks"
expect_ok "valid request" "$ok_body" $'name=my-repo\ndescription=A small tool, with commas & symbols: fine\nlanguage=go'
expect_ok "CRLF line endings" $'```shipyard\r\nname: a1\r\ndescription: d\r\nlanguage: other\r\n```\r\n' $'name=a1\ndescription=d\nlanguage=other'
expect_ok "indented keys, first value wins" $'```shipyard\n  name: x\nname: y\n  description:   spaced   \nlanguage: javascript\n```' $'name=x\ndescription=spaced\nlanguage=javascript'

expect_err "no block" "name: my-repo" "No complete"
expect_err "unterminated block" $'```shipyard\nname: a\n' "No complete"
expect_err "other fence language ignored" $'```yaml\nname: a\ndescription: d\nlanguage: go\n```' "No complete"
expect_err "missing name" $'```shipyard\ndescription: d\nlanguage: go\n```' "Missing 'name:'"
expect_err "uppercase name" $'```shipyard\nname: MyRepo\ndescription: d\nlanguage: go\n```' "Invalid name"
expect_err "path in name" $'```shipyard\nname: ../evil\ndescription: d\nlanguage: go\n```' "Invalid name"
expect_err "shell metachar in name" $'```shipyard\nname: a$(id)\ndescription: d\nlanguage: go\n```' "Invalid name"
expect_err "trailing hyphen" $'```shipyard\nname: a-\ndescription: d\nlanguage: go\n```' "Invalid name"
expect_err "double hyphen" $'```shipyard\nname: a--b\ndescription: d\nlanguage: go\n```' "consecutive"
expect_err "missing description" $'```shipyard\nname: a\nlanguage: go\n```' "Missing 'description:'"
expect_err "control char in description" $'```shipyard\nname: a\ndescription: bad\x07bell\nlanguage: go\n```' "control characters"
long=$(printf 'x%.0s' {1..301})
expect_err "long description" $'```shipyard\nname: a\ndescription: '"$long"$'\nlanguage: go\n```' "keep it to 300"
expect_err "bad language" $'```shipyard\nname: a\ndescription: d\nlanguage: rust\n```' "Invalid language"
expect_err "missing language" $'```shipyard\nname: a\ndescription: d\n```' "Missing 'language:'"

echo "parse-request: $pass passed, $failn failed"
(( failn == 0 ))
