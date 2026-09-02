#!/bin/bash
# Install or remove the marker images that make the effects selectable in
# Omarchy's background switcher. Copies rather than symlinks, in the theme's own
# state directory: anything else breaks wallpaper cycling or theme switching.

set -u

dest="$HOME/.local/state/omarchy/current/theme/backgrounds"

tmp=""
claim=""
cleanup() {
  [ -n "$tmp" ] && rm -f -- "$tmp"
  [ -n "$claim" ] && rm -f -- "$claim"
  true
}
trap cleanup EXIT INT TERM

# Bare filenames only below: the cwd keeps the validated inode, the path does not.
enter_dest() {
  [ -d "$dest" ] && [ ! -L "$dest" ] || return 1
  cd -P -- "$dest" 2>/dev/null || return 1
  [ -O . ]
}

dest_is_live() {
  [ "$(stat -c %d:%i . 2>/dev/null)" = "$(stat -c %d:%i -- "$dest" 2>/dev/null)" ]
}

install_markers() {
  local f name
  enter_dest || return 1
  for f in "$src"/markers/animated-*.png; do
    [ -e "$f" ] || continue                  # unmatched glob stays literal

    name=${f##*/}
    if [ -e "$name" ] || [ -L "$name" ]; then
      continue                               # never overwrite what is already there
    fi

    tmp=$(mktemp ./.animated-XXXXXXXX 2>/dev/null) || continue
    if cp -- "$f" "$tmp" 2>/dev/null && chmod 644 "$tmp" 2>/dev/null; then
      ln "$tmp" "$name" 2>/dev/null
    fi
    rm -f -- "$tmp"
    tmp=""
  done
}

remove_markers() {
  local f name ours theirs
  enter_dest || return 1
  for f in "$src"/markers/animated-*.png; do
    [ -e "$f" ] || continue

    name=${f##*/}
    [ -f "$name" ] && [ ! -L "$name" ] || continue

    # Hash through the link, so the bytes checked and the file unlinked are one inode.
    claim=$(mktemp ./.claim-XXXXXXXX 2>/dev/null) || continue
    if ln -f -- "$name" "$claim" 2>/dev/null; then
      ours=$(sha256sum -- "$f" 2>/dev/null | cut -d" " -f1)
      theirs=$(sha256sum -- "$claim" 2>/dev/null | cut -d" " -f1)
      if [ -n "$ours" ] && [ "$ours" = "$theirs" ] &&
        [ "$(stat -c %i -- "$name" 2>/dev/null)" = "$(stat -c %i -- "$claim" 2>/dev/null)" ]; then
        rm -f -- "$name"
      fi
    fi
    rm -f -- "$claim"
    claim=""
  done
}

resolve_src() {
  [ -n "$src" ] && [ -d "$src/markers" ] || return 1
  src=$(cd -P -- "$src" 2>/dev/null && pwd) || return 1
  [ -n "$src" ]
}

case "${1:-}" in
  install)
    src="${2:-}"
    resolve_src || exit 0
    [ -d "$HOME/.local/state/omarchy/current/theme" ] || exit 0
    mkdir -p "$dest" 2>/dev/null || exit 0
    install_markers || exit 0

    dest_is_live || {
      cd / || exit 0
      mkdir -p "$dest" 2>/dev/null && install_markers
    }
    exit 0
    ;;
  remove)
    src="${2:-}"
    resolve_src || exit 0
    remove_markers || exit 0
    ;;
  *)
    echo "usage: markers.sh install <plugin-dir> | markers.sh remove <plugin-dir>" >&2
    exit 1
    ;;
esac
