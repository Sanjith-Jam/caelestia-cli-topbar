#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
qs_dir="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/caelestia/modules/dashboard"
bin_dir="${XDG_BIN_HOME:-$HOME/.local/bin}"
stamp=$(date +%Y%m%d-%H%M%S)

mkdir -p "$qs_dir" "$bin_dir"

backup_dir="$HOME/.local/state/caelestia-cli-topbar/backups/$stamp"
mkdir -p "$backup_dir"
for file in CliTopTab.qml; do
    if [ -e "$qs_dir/$file" ]; then
        cp -p "$qs_dir/$file" "$backup_dir/$file"
    fi
done
if [ -e "$bin_dir/caelestia-cli-top" ]; then
    cp -p "$bin_dir/caelestia-cli-top" "$backup_dir/caelestia-cli-top"
fi

install -m 0644 "$repo_dir/caelestia/modules/dashboard/CliTopTab.qml" "$qs_dir/CliTopTab.qml"
install -m 0755 "$repo_dir/scripts/caelestia-cli-top" "$bin_dir/caelestia-cli-top"

printf '%s\n' "Installed the College tab and CLI-TOP wrapper."
printf '%s\n' "Backup: $backup_dir"
printf '%s\n' "Now merge the Content.qml snippets from README.md, then restart Caelestia."
