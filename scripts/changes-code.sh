#!/usr/bin/env bash
#
# Prints whether the changes between two commits touch the files that the tests use, as `test=true` or `test=false`,
# and the files that the documentation build uses, as `documentation=true` or `documentation=false`, for the outputs
# of a step of GitHub Actions. The DocC catalogs are in Sources/, but the tests don't use them, so changes of only the
# catalogs build the documentation without the tests.
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
code=$(echo "$changed" | grep -E "$code_paths" || true)
if [ -n "$code" ]; then
  echo "documentation=true"
else
  echo "documentation=false"
fi
if echo "$code" | grep -Ev '\.docc/' | grep -q .; then
  echo "test=true"
else
  echo "test=false"
fi
