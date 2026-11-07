#!/usr/bin/env bash
# Isolated, checksum-verified Godot installation for GitHub-hosted Linux CI.
# Run with bash; the following workflow steps receive GODOT_BIN and XDG_DATA_HOME.
set -Eeuo pipefail

if [[ "$(uname -s)" != "Linux" || "$(uname -m)" != "x86_64" ]]; then
  printf '%s\n' 'This installer requires Linux x86_64.' >&2
  exit 1
fi

if [[ -z "${GITHUB_ENV:-}" || ! -f "$GITHUB_ENV" || ! -w "$GITHUB_ENV" ]]; then
  printf '%s\n' 'Run this installer in GitHub Actions with a writable GITHUB_ENV file.' >&2
  exit 1
fi

for dependency in curl unzip sha256sum mktemp mkdir chmod tr; do
  if ! command -v "$dependency" >/dev/null 2>&1; then
    printf 'Missing required command: %s\n' "$dependency" >&2
    exit 1
  fi
done

readonly godot_release='4.6.3-stable'
readonly godot_template_version='4.6.3.stable'
readonly godot_binary_name="Godot_v${godot_release}_linux.x86_64"
readonly godot_binary_archive="${godot_binary_name}.zip"
readonly godot_templates_archive="Godot_v${godot_release}_export_templates.tpz"
readonly godot_binary_sha256='d0bc2113065e481c9c2c2b2c37daa4e8be3fe9e27f0ab9ab0b6096e9a37907f3'
readonly godot_templates_sha256='3fbe2c0e2dec9d537ab9ec97bcf8da91dcf23357fc51f67092dd068d839290a8'
readonly godot_release_url="https://github.com/godotengine/godot-builds/releases/download/${godot_release}"

# Each run gets its own directory. Nothing is removed from or replaced in HOME,
# the repository, or an existing Godot installation.
godot_ci_root="$(mktemp -d "${RUNNER_TEMP:-/tmp}/water-sort-godot-4.6.3.XXXXXX")"
readonly godot_ci_root
readonly godot_download_dir="${godot_ci_root}/downloads"
readonly godot_bin_dir="${godot_ci_root}/bin"
readonly godot_data_dir="${godot_ci_root}/data"
readonly godot_templates_dir="${godot_data_dir}/godot/export_templates/${godot_template_version}"
mkdir -p "$godot_download_dir" "$godot_bin_dir" "$godot_templates_dir"

download_release_asset() {
  local asset_name="$1"
  curl --fail --location --silent --show-error \
    --proto '=https' --proto-redir '=https' --tlsv1.2 \
    --retry 3 --retry-delay 2 --connect-timeout 20 --max-time 900 \
    --output "${godot_download_dir}/${asset_name}" \
    "${godot_release_url}/${asset_name}"
}

printf 'Downloading official Godot %s and matching templates (about 1.3 GB).\n' "$godot_release"
download_release_asset "$godot_binary_archive"
download_release_asset "$godot_templates_archive"

# Verify both complete archives before executing or extracting anything.
(
  cd "$godot_download_dir"
  printf '%s  %s\n' \
    "$godot_binary_sha256" "$godot_binary_archive" \
    "$godot_templates_sha256" "$godot_templates_archive" |
    sha256sum --check --strict -
)

unzip -q "${godot_download_dir}/${godot_binary_archive}" \
  "$godot_binary_name" -d "$godot_bin_dir"
unzip -q -j "${godot_download_dir}/${godot_templates_archive}" \
  'templates/web_nothreads_release.zip' \
  'templates/web_nothreads_debug.zip' \
  'templates/version.txt' \
  -d "$godot_templates_dir"

if [[ "$(tr -d '\r\n' < "${godot_templates_dir}/version.txt")" != "$godot_template_version" ]]; then
  printf '%s\n' 'The extracted export template version does not match Godot 4.6.3 stable.' >&2
  exit 1
fi

readonly godot_bin="${godot_bin_dir}/${godot_binary_name}"
chmod u+x "$godot_bin"
godot_actual_version="$("$godot_bin" --headless --version)"
if [[ "$godot_actual_version" != 4.6.3.stable.* ]]; then
  printf 'Unexpected Godot version: %s\n' "$godot_actual_version" >&2
  exit 1
fi

printf 'GODOT_BIN=%s\nXDG_DATA_HOME=%s\n' "$godot_bin" "$godot_data_dir" >> "$GITHUB_ENV"
printf 'Installed %s with isolated Web export templates.\n' "$godot_actual_version"
