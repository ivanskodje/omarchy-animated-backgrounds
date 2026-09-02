#!/bin/bash
# Install or remove the marker images that make the effects selectable in
# Omarchy's background switcher. Copies rather than symlinks, in the theme's own
# state directory: anything else breaks wallpaper cycling or theme switching.

set -u

dest="$HOME/.local/state/omarchy/current/theme/backgrounds"

tmp=""
cleanup() {
  [ -n "$tmp" ] && rm -f -- "$tmp"
  true
}
trap cleanup EXIT INT TERM

usable_dest() {
  [ -d "$dest" ] && [ ! -L "$dest" ] && [ -O "$dest" ]
}

case "${1:-}" in
  install)
    src="${2:-}"
    [ -n "$src" ] && [ -d "$src/markers" ] || exit 0
    [ -d "$HOME/.local/state/omarchy/current/theme" ] || exit 0
    mkdir -p "$dest" 2>/dev/null || exit 0
    usable_dest || exit 0

    for f in "$src"/markers/animated-*.png; do
      [ -e "$f" ] || continue                  # unmatched glob stays literal

      t="$dest/${f##*/}"
      if [ -e "$t" ] || [ -L "$t" ]; then
        continue                               # never overwrite what is already there
      fi

      tmp=$(mktemp "$dest/.animated-XXXXXXXX" 2>/dev/null) || continue
      if cp -- "$f" "$tmp" 2>/dev/null && chmod 644 "$tmp" 2>/dev/null; then
        ln "$tmp" "$t" 2>/dev/null
      fi
      rm -f -- "$tmp"
      tmp=""
    done
    ;;
  remove)
    src="${2:-}"
    [ -n "$src" ] && [ -d "$src/markers" ] || exit 0
    usable_dest || exit 0

    for f in "$src"/markers/animated-*.png; do
      [ -e "$f" ] || continue

      t="$dest/${f##*/}"
      [ -f "$t" ] && [ ! -L "$t" ] || continue

      ours=$(sha256sum < "$f" 2>/dev/null) || continue
      theirs=$(sha256sum < "$t" 2>/dev/null) || continue
      [ "$ours" = "$theirs" ] && rm -f -- "$t"
    done
    ;;
  *)
    echo "usage: markers.sh install <plugin-dir> | markers.sh remove <plugin-dir>" >&2
    exit 1
    ;;
esac
