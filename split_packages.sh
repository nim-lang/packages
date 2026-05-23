#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: split_packages.sh [--force] [packages.json] [pkgs-dir]

Split a top-level packages.json array into sharded package folders:
  pkgs/<first-letter>/<package-name>.json

Arguments:
  packages.json  Input package manifest. Default: packages.json
  pkgs-dir       Output shard directory. Default: pkgs

Options:
  --force        Replace an existing non-empty output directory.
  --help         Show this help text.
EOF
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "error: missing required command: $1" >&2
    exit 1
  fi
}

is_nonempty_dir() {
  local dir="$1"
  [[ -d "$dir" ]] && find "$dir" -mindepth 1 -print -quit | grep -q .
}

force=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force)
      force=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    --*)
      echo "error: unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      break
      ;;
  esac
done

input_json="${1:-packages.json}"
output_root="${2:-pkgs}"

require_cmd jq

if [[ ! -f "$input_json" ]]; then
  echo "error: input file not found: $input_json" >&2
  exit 1
fi

if is_nonempty_dir "$output_root" && [[ "$force" -ne 1 ]]; then
  echo "error: output directory already exists and is not empty: $output_root" >&2
  echo "rerun with --force to replace it" >&2
  exit 1
fi

tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/split-packages.XXXXXX")"
cleanup() {
  rm -rf "$tmp_root"
}
trap cleanup EXIT

jq -e 'if type == "array" then . else error("packages.json must be a JSON array") end' "$input_json" >/dev/null

count=0
while IFS= read -r package_json; do
  package_name="$(jq -r '.name // empty' <<<"$package_json")"
  if [[ -z "$package_name" ]]; then
    echo "error: encountered package without a name" >&2
    exit 1
  fi

  shard="$(printf '%s' "$package_name" | cut -c1 | tr '[:upper:]' '[:lower:]')"
  if [[ ! "$shard" =~ ^[a-z]$ ]]; then
    echo "error: package name must start with an ASCII letter for alphabetical sharding: $package_name" >&2
    exit 1
  fi

  package_dir="$tmp_root/$shard"
  mkdir -p "$package_dir"
  jq . <<<"$package_json" > "$package_dir/$package_name.json"
  count=$((count + 1))
done < <(jq -c '.[]' "$input_json")

rm -rf "$output_root"
mv "$tmp_root" "$output_root"
trap - EXIT

echo "Wrote $count package metadata files into $output_root"
