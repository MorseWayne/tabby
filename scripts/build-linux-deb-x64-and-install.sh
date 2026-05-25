#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

arch="${ARCH:-x64}"
deb_path="${1:-dist/tabby-1.0.234-nightly.0-linux-x64.deb}"

run_step() {
    local name="$1"
    shift
    printf '\n==> %s\n' "$name"
    "$@"
}

export ARCH="$arch"

run_step "Install dependencies" yarn --network-timeout 1000000 --arch="$arch" --target-arch="$arch"
run_step "Build app and packages" yarn run build --arch="$arch" --target_arch="$arch"
run_step "Prepackage builtin plugins" node scripts/prepackage-plugins.mjs
run_step "Build Linux DEB" env USE_HARD_LINKS=false USE_SYSTEM_FPM=true node scripts/build-linux.mjs

if [[ ! -f "$deb_path" ]]; then
    printf '\nDEB package not found: %s\n' "$deb_path" >&2
    printf 'Available packages:\n' >&2
    find dist -maxdepth 1 -name '*.deb' -print >&2
    exit 1
fi

install_path="$(realpath "$deb_path")"
tmp_deb="$(mktemp --tmpdir tabby-install-XXXXXX.deb)"
cp "$install_path" "$tmp_deb"
chmod 644 "$tmp_deb"
trap 'rm -f "$tmp_deb"' EXIT

package_name="$(dpkg-deb -f "$tmp_deb" Package)"
if dpkg-query -W -f='${Status}' "$package_name" 2>/dev/null | grep -q '^install ok installed$'; then
    run_step "Remove installed $package_name package" sudo apt remove -y "$package_name"
fi

run_step "Install DEB package" sudo apt install "$tmp_deb"
