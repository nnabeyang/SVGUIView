#!/usr/bin/env bash
#
# Build this package's DocC documentation locally.
#
# The Swift Package Index builds and hosts the published documentation from
# `.spi.yml`. This script reads the same manifest so that a local build covers
# exactly the targets the index publishes. It never writes into the repository;
# documentation output is not committed.
#
# The package depends on UIKit, so the documentation is built for the iOS
# Simulator with `xcodebuild docbuild` rather than with `swift build`.

set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: scripts/build-documentation.sh [--strict] [--output <dir>]

  (no arguments)     Build every target listed in .spi.yml and report failures.
  --strict           Treat DocC warnings as errors.
  --output <dir>     Keep the generated archives in <dir> instead of a
                     temporary directory that is removed on exit.
USAGE
}

repository_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly repository_root
readonly manifest_path="${repository_root}/.spi.yml"
readonly destination="generic/platform=iOS Simulator"

strict=false
output_path=""

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --strict)
      strict=true
      shift
      ;;
    --output)
      [[ "$#" -ge 2 ]] || { usage; exit 64; }
      output_path="$2"
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      printf 'error: unrecognized argument: %s\n' "$1" >&2
      usage
      exit 64
      ;;
  esac
done

if [[ ! -f "${manifest_path}" ]]; then
  printf 'error: Swift Package Index manifest is missing: %s\n' "${manifest_path}" >&2
  exit 1
fi

# Reads a YAML sequence from .spi.yml, accepting both the block form
# (`key:` followed by `- item` lines) and the inline form (`key: [a, b]`). The
# key itself may be the first key of a list item, so a leading `- ` is allowed.
read_manifest_sequence() {
  local key="$1"
  awk -v key="${key}" '
    function emit(value) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      gsub(/^["\x27]|["\x27]$/, "", value)
      if (value != "") print value
    }
    {
      line = $0
      sub(/[[:space:]]*#.*$/, "", line)
    }
    line ~ ("^[[:space:]]*(-[[:space:]]+)?" key ":[[:space:]]*\\[") {
      inline = line
      sub(/^[^[]*\[/, "", inline)
      sub(/\].*$/, "", inline)
      count = split(inline, items, ",")
      for (index_ = 1; index_ <= count; index_++) emit(items[index_])
      next
    }
    line ~ ("^[[:space:]]*(-[[:space:]]+)?" key ":[[:space:]]*$") {
      collecting = 1
      next
    }
    collecting && line ~ /^[[:space:]]*-[[:space:]]*/ {
      item = line
      sub(/^[[:space:]]*-[[:space:]]*/, "", item)
      emit(item)
      next
    }
    collecting && line ~ /^[[:space:]]*[^[:space:]]/ {
      collecting = 0
    }
  ' "${manifest_path}"
}

targets=()
while IFS= read -r target; do
  targets+=("${target}")
done < <(read_manifest_sequence documentation_targets)

if [[ "${#targets[@]}" == 0 ]]; then
  printf 'error: no documentation_targets found in %s\n' "${manifest_path}" >&2
  exit 1
fi

temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/svguiview-documentation.XXXXXX")"
readonly temporary_directory
trap 'rm -rf -- "${temporary_directory}"' EXIT

if [[ -n "${output_path}" ]]; then
  mkdir -p "${output_path}"
  archives_directory="$(cd -- "${output_path}" && pwd)"
fi

docc_flags=()
if [[ "${strict}" == true ]]; then
  docc_flags+=("OTHER_DOCC_FLAGS=--warnings-as-errors")
fi

failed_targets=()
for target in "${targets[@]}"; do
  printf '==> Building documentation for %s\n' "${target}" >&2

  # Each target gets its own derived data so that the archive found below is
  # the one this invocation produced.
  derived_data_path="${temporary_directory}/DerivedData/${target}"

  if ! (cd -- "${repository_root}" && xcodebuild docbuild \
    -scheme "${target}" \
    -destination "${destination}" \
    -derivedDataPath "${derived_data_path}" \
    -quiet \
    ${docc_flags[@]+"${docc_flags[@]}"}) >&2; then
    failed_targets+=("${target}")
    continue
  fi

  archive_path="$(find "${derived_data_path}/Build/Products" -type d -name "${target}.doccarchive" -print -quit)"
  if [[ -z "${archive_path}" ]]; then
    printf 'error: no documentation archive was produced for %s\n' "${target}" >&2
    failed_targets+=("${target}")
    continue
  fi

  if [[ -n "${output_path}" ]]; then
    rm -rf -- "${archives_directory}/${target}.doccarchive"
    cp -R "${archive_path}" "${archives_directory}/"
  fi
done

if [[ "${#failed_targets[@]}" -gt 0 ]]; then
  printf 'error: documentation build failed for: %s\n' "${failed_targets[*]}" >&2
  exit 1
fi

printf 'Built documentation for: %s\n' "${targets[*]}" >&2
if [[ -n "${output_path}" ]]; then
  printf 'Archives are in %s.\n' "${archives_directory}" >&2
fi
