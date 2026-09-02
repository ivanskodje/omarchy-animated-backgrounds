#!/bin/bash
# Install or remove the marker images that make the effects selectable in
# Omarchy's background switcher. Copies rather than symlinks, in the theme's own
# state directory: anything else breaks wallpaper cycling or theme switching.

set -u

PATH=/usr/bin:/bin
export PATH

dest="$HOME/.local/state/omarchy/current/theme/backgrounds"

tmp=""
claim=""
grab=""
grab_name=""
cleanup() {
  [ -n "$tmp" ] && rm -f -- "$tmp"
  [ -n "$claim" ] && rm -f -- "$claim"
  # Never delete a grab: it can be the only link to a file that is not ours.
  [ -n "$grab" ] && ln -- "$grab" "$grab_name" 2>/dev/null && rm -f -- "$grab"
  true
}
trap cleanup EXIT INT TERM

# Omarchy recreates these with rm -rf plus mv, so a symlink is never legitimate here.
theme_dir_ok() {
  local base="$HOME/.local/state/omarchy/current"
  [ ! -L "$base" ] && [ ! -L "$base/theme" ] && [ -d "$base/theme" ]
}

# Bare filenames only below: the cwd keeps the validated inode, the path does not.
enter_dest() {
  theme_dir_ok || return 1
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

    # Verify through a spare link first, so a file that will be kept is never moved.
    claim=$(mktemp ./.claim-XXXXXXXX 2>/dev/null) || continue
    ln -f -- "$name" "$claim" 2>/dev/null || { rm -f -- "$claim"; claim=""; continue; }
    # Skipping early also caps the hash at the shipped marker's size.
    if [ "$(stat -c %s -- "$claim" 2>/dev/null)" != "$(stat -c %s -- "$f" 2>/dev/null)" ]; then
      rm -f -- "$claim"
      claim=""
      continue
    fi
    ours=$(timeout 10 sha256sum -- "$f" 2>/dev/null | cut -d" " -f1)
    theirs=$(timeout 10 sha256sum -- "$claim" 2>/dev/null | cut -d" " -f1)
    if [ -z "$ours" ] || [ "$ours" != "$theirs" ]; then
      rm -f -- "$claim"
      claim=""
      continue
    fi

    # Rename because there is no unlink-by-descriptor: what returns is what is deleted.
    grab=$(mktemp ./.grab-XXXXXXXX 2>/dev/null) || { rm -f -- "$claim"; claim=""; continue; }
    grab_name=$name
    if mv -f -- "$name" "$grab" 2>/dev/null; then
      if [ "$(stat -c %i -- "$grab" 2>/dev/null)" = "$(stat -c %i -- "$claim" 2>/dev/null)" ]; then
        rm -f -- "$grab"
      elif ln -- "$grab" "$grab_name" 2>/dev/null; then
        rm -f -- "$grab"
      else
        echo "markers.sh: $grab_name was taken during removal; left as $grab" >&2
      fi
    else
      rm -f -- "$grab"
    fi
    grab=""
    grab_name=""
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
    theme_dir_ok || exit 0
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
