#!/bin/bash
# Install or remove the marker images that make the effects selectable in
# Omarchy's background switcher. Copies rather than symlinks, in the theme's own
# state directory: anything else breaks wallpaper cycling or theme switching.

set -u

dest="$HOME/.local/state/omarchy/current/theme/backgrounds"

case "${1:-}" in
  install)
    src="${2:-}"
    [ -n "$src" ] && [ -d "$src/markers" ] || exit 0
    [ -d "$HOME/.local/state/omarchy/current/theme" ] || exit 0
    mkdir -p "$dest" 2>/dev/null || exit 0
    for f in "$src"/markers/animated-*.png; do
      [ -e "$f" ] || continue                  # unmatched glob stays literal
      t="$dest/${f##*/}"
      [ -e "$t" ] && continue                  # never overwrite what is already there
      cp -- "$f" "$t.tmp.$$" 2>/dev/null && mv -f -- "$t.tmp.$$" "$t" 2>/dev/null
    done
    ;;
  remove)
    rm -f "$dest"/animated-*.png
    ;;
  *)
    echo "usage: markers.sh install <plugin-dir> | markers.sh remove" >&2
    exit 1
    ;;
esac
