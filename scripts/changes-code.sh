#!/usr/bin/env bash
#
# Prints whether the changes between two commits touch the files that the tests and the documentation build use,
# as `code=true` or `code=false`, for the output of a step of GitHub Actions.
#
#   scripts/changes-code.sh <base> <head>
#
# The changes are those of a pull request: from the commit where the head branches off the base to the head.
# Add a path here when a new file or directory affects the build, the tests or the documentation.

set -euo pipefail

if [ $# -ne 2 ]; then
  echo "usage: $0 <base> <head>" >&2
  exit 2
fi

code_paths='^(Sources/|Tests/|Development/|scripts/|\.github/workflows/|Package\.swift$|Package\.resolved$|\.spi\.yml$|\.swift-format$|format\.sh$)'

changed=$(git diff --name-only "$1...$2")
echo "Changed files:" >&2
echo "$changed" | sed 's/^/  /' >&2
if echo "$changed" | grep -Eq "$code_paths"; then
  echo "code=true"
else
  echo "code=false"
fi
