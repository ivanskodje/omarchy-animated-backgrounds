#!/bin/bash
# Exercises markers.sh against a throwaway HOME. Run: bash test/markers-test.sh

set -u

sh="$(cd "$(dirname "$0")/.." && pwd)/markers.sh"
pass=0
fail=0

ok()    { printf '  ok    %s\n' "$1"; pass=$((pass + 1)); }
bad()   { printf '  FAIL  %s\n' "$1"; fail=$((fail + 1)); }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

setup() {
  root=$(mktemp -d)
  export HOME="$root/home"
  # Every path below hangs off HOME, so a failed override would run the tests
  # against the real one.
  [ "$HOME" = "$root/home" ] || { echo "refusing to run: HOME override failed" >&2; exit 1; }
  dest="$HOME/.local/state/omarchy/current/theme/backgrounds"
  plug="$root/plugin"
  mkdir -p "$HOME/.local/state/omarchy/current/theme" "$plug/markers"
  cp "$(dirname "$sh")/markers"/animated-*.png "$plug/markers/"
  echo "secret" >"$root/victim"
}

teardown() { rm -rf "$root"; }

# The injection cases need PATH shims, which the script's pinned PATH defeats. They
# run against a copy with that one line removed; the pinning is tested separately.
unpinned() {
  sed '/^PATH=/d; /^export PATH$/d' "$sh" >"$root/markers-unpinned.sh"
  chmod 755 "$root/markers-unpinned.sh"
  printf '%s' "$root/markers-unpinned.sh"
}

echo "install"
setup
bash "$sh" install "$plug"
check "both markers land"            '[ -f "$dest/animated-grid.png" ] && [ -f "$dest/animated-rain.png" ]'
check "content matches source"       'cmp -s "$plug/markers/animated-grid.png" "$dest/animated-grid.png"'
check "mode is 644"                  '[ "$(stat -c %a "$dest/animated-grid.png")" = 644 ]'
check "owned by us"                  '[ "$(stat -c %u "$dest/animated-grid.png")" = "$(id -u)" ]'
check "no temporary left behind"     '[ -z "$(find "$dest" \( -name ".animated-*" -o -name "*.tmp.*" \) -print -quit)" ]'
inode=$(stat -c %i "$dest/animated-grid.png")
bash "$sh" install "$plug"
check "second run replaces nothing"  '[ "$(stat -c %i "$dest/animated-grid.png")" = "$inode" ]'
teardown

# No theme installed yet.
setup
rm -rf "$HOME/.local/state/omarchy/current/theme"
bash "$sh" install "$plug"
check "no theme, nothing created"    '[ ! -e "$dest" ]'
teardown

echo
echo "install leaves other people's files alone"
# Your own image already sitting under a marker name.
setup
mkdir -p "$dest"
echo "user artwork" >"$dest/animated-grid.png"
bash "$sh" install "$plug"
check "regular file untouched"       '[ "$(cat "$dest/animated-grid.png")" = "user artwork" ]'
check "other marker still lands"     '[ -f "$dest/animated-rain.png" ]'
teardown

# Symlink parked at a marker name, aimed at a file worth protecting.
setup
mkdir -p "$dest"
ln -s "$root/victim" "$dest/animated-grid.png"
bash "$sh" install "$plug"
check "symlinked target skipped"     '[ "$(cat "$root/victim")" = "secret" ]'
check "symlink itself intact"        '[ -L "$dest/animated-grid.png" ]'
teardown

setup
mkdir -p "$dest"
# Publication once used "$t.tmp.$$"; exec keeps the pid, so this is that exact path.
bash -c 'ln -s "$1/victim" "$2/animated-grid.png.tmp.$$"; exec bash "$3" install "$4"' \
  _ "$root" "$dest" "$sh" "$plug"
check "no write through a predictable temp" '[ "$(cat "$root/victim")" = "secret" ]'
teardown

# Dangling symlink: -e reports false, so only -L catches it.
setup
mkdir -p "$dest"
ln -s "$root/nonexistent" "$dest/animated-grid.png"
bash "$sh" install "$plug"
check "dangling symlink skipped"     '[ -L "$dest/animated-grid.png" ] && [ ! -e "$root/nonexistent" ]'
teardown

# The destination directory itself replaced by a symlink.
setup
rm -rf "$dest"
mkdir -p "$root/elsewhere"
ln -s "$root/elsewhere" "$dest"
bash "$sh" install "$plug"
check "symlinked destination refused" '[ -z "$(ls -A "$root/elsewhere")" ]'
teardown

echo
echo "remove only takes what this plugin owns"
# A third-party file and a tampered marker, both sharing the animated- prefix.
setup
bash "$sh" install "$plug"
echo "somebody else's" >"$dest/animated-custom.png"
printf 'tampered' >>"$dest/animated-rain.png"
bash "$sh" remove "$plug"
check "identical marker removed"     '[ ! -e "$dest/animated-grid.png" ]'
check "modified marker kept"         '[ -f "$dest/animated-rain.png" ]'
check "unrelated animated-* kept"    '[ -f "$dest/animated-custom.png" ]'
check "no claim or grab left behind" '[ -z "$(find "$dest" \( -name ".claim-*" -o -name ".grab-*" \) -print -quit)" ]'
teardown

# A marker the user has edited must be kept without ever being moved.
setup
bash "$sh" install "$plug"
printf 'tampered' >>"$dest/animated-rain.png"
inode=$(stat -c %i "$dest/animated-rain.png")
bash "$sh" remove "$plug"
check "kept file is never renamed"   '[ "$(stat -c %i "$dest/animated-rain.png")" = "$inode" ]'
teardown

# Symlink at a marker name, this time on the delete path.
setup
mkdir -p "$dest"
ln -s "$root/victim" "$dest/animated-grid.png"
bash "$sh" remove "$plug"
check "symlink not unlinked"         '[ -L "$dest/animated-grid.png" ]'
check "symlink target intact"        '[ -f "$root/victim" ]'
teardown

# remove with no plugin directory has nothing to compare against.
setup
bash "$sh" install "$plug"
bash "$sh" remove
check "remove without a plugin dir deletes nothing" '[ -f "$dest/animated-grid.png" ]'
teardown

echo
echo "theme switch mid-operation"

# A shim earlier in PATH swaps the theme dir the way omarchy-theme-set does.
make_shim() {
  local cmd=$1 fire_on=$2 real
  real=$(command -v "$cmd")
  mkdir -p "$root/shim"
  cat >"$root/shim/$cmd" <<SHIM
#!/bin/bash
n=1
[ -f "$root/shim/.n-$cmd" ] && n=\$(( \$(cat "$root/shim/.n-$cmd") + 1 ))
echo "\$n" >"$root/shim/.n-$cmd"
if [ "\$n" = "$fire_on" ]; then
  rm -rf "$HOME/.local/state/omarchy/current/theme"
  mv "$root/next-theme" "$HOME/.local/state/omarchy/current/theme"
fi
exec "$real" "\$@"
SHIM
  chmod 755 "$root/shim/$cmd"
}

# Switch lands between validation and publication; the new dir is a symlink.
setup
mkdir -p "$root/decoy" "$root/next-theme"
ln -s "$root/decoy" "$root/next-theme/backgrounds"
make_shim mktemp 1
PATH="$root/shim:$PATH" bash "$(unpinned)" install "$plug"
rc=$?
check "swap before publication writes nothing unvalidated" '[ -z "$(ls -A "$root/decoy")" ]'
check "swap before publication exits clean"                '[ "$rc" = 0 ]'
teardown

setup
bash "$sh" install "$plug"
mkdir -p "$root/next-theme/backgrounds"
echo "someone else's file" >"$root/next-theme/backgrounds/animated-grid.png"
# Switch lands while hashing.
make_shim sha256sum 1
PATH="$root/shim:$PATH" bash "$(unpinned)" remove "$plug"
check "swap during hashing spares the new directory"       '[ "$(cat "$dest/animated-grid.png")" = "someone else'"'"'s file" ]'
teardown

setup
bash "$sh" install "$plug"
mkdir -p "$root/next-theme/backgrounds"
echo "someone else's file" >"$root/next-theme/backgrounds/animated-grid.png"
# Switch lands between the hash and the unlink, the reviewer's exact case.
make_shim sha256sum 2
PATH="$root/shim:$PATH" bash "$(unpinned)" remove "$plug"
check "swap between hash and unlink spares the new file"    '[ "$(cat "$dest/animated-grid.png")" = "someone else'"'"'s file" ]'
teardown

echo
echo "basename replaced mid-removal"

# Same idea as make_shim, but the swap happens inside the already pinned directory.
make_name_shim() {
  local cmd=$1 fire_on=$2 real
  real=$(command -v "$cmd")
  mkdir -p "$root/shim"
  cat >"$root/shim/$cmd" <<SHIM
#!/bin/bash
n=1
[ -f "$root/shim/.n-$cmd" ] && n=\$(( \$(cat "$root/shim/.n-$cmd") + 1 ))
echo "\$n" >"$root/shim/.n-$cmd"
if [ "\$n" = "$fire_on" ]; then
  printf 'intruder' >"$dest/.intruder"
  mv -f "$dest/.intruder" "$dest/animated-grid.png"
fi
exec "$real" "\$@"
SHIM
  chmod 755 "$root/shim/$cmd"
}

# The name is taken over after the identity check and before the unlink, which is
# the last gap an external command can be wedged into.
setup
bash "$sh" install "$plug"
make_name_shim stat 2
PATH="$root/shim:$PATH" bash "$(unpinned)" remove "$plug"
check "replacement at the name survives" '[ "$(cat "$dest/animated-grid.png" 2>/dev/null)" = "intruder" ]'
check "our own marker still removed"     '[ ! -e "$dest/animated-rain.png" ]'
check "no claim or grab left behind"     '[ -z "$(find "$dest" \( -name ".claim-*" -o -name ".grab-*" \) -print -quit)" ]'
teardown

echo
echo "symlinked theme directory"

# Omarchy recreates the theme dir with rm -rf plus mv, so a symlink there is never
# legitimate, and -d follows it.
setup
rm -rf "$HOME/.local/state/omarchy/current/theme"
mkdir -p "$root/decoy-theme"
ln -s "$root/decoy-theme" "$HOME/.local/state/omarchy/current/theme"
bash "$sh" install "$plug"
check "symlinked theme refused on install" '[ -z "$(find "$root/decoy-theme" -type f -print -quit)" ]'
teardown

# Same one component higher: current itself replaced by a symlink.
setup
rm -rf "$HOME/.local/state/omarchy/current"
mkdir -p "$root/decoy-current/theme/backgrounds"
ln -s "$root/decoy-current" "$HOME/.local/state/omarchy/current"
bash "$sh" install "$plug"
check "symlinked current refused"          '[ -z "$(find "$root/decoy-current" -type f -print -quit)" ]'
teardown

setup
mkdir -p "$root/decoy-theme/backgrounds"
cp "$plug/markers/animated-grid.png" "$root/decoy-theme/backgrounds/"
rm -rf "$HOME/.local/state/omarchy/current/theme"
ln -s "$root/decoy-theme" "$HOME/.local/state/omarchy/current/theme"
bash "$sh" remove "$plug"
check "symlinked theme refused on remove"  '[ -f "$root/decoy-theme/backgrounds/animated-grid.png" ]'
teardown

echo
echo "runtime boundaries"

# A tool planted first in PATH must never be reached by the real script.
setup
bash "$sh" install "$plug"
mkdir -p "$root/evil"
cat >"$root/evil/sha256sum" <<EVIL
#!/bin/bash
touch "$root/evil/EXECUTED"
exec /usr/bin/sha256sum "\$@"
EVIL
chmod 755 "$root/evil/sha256sum"
PATH="$root/evil:$PATH" bash "$sh" remove "$plug"
check "shadowed tool in PATH is not run"  '[ ! -e "$root/evil/EXECUTED" ]'
teardown

# A huge file under a marker name must be rejected on size, not hashed.
setup
bash "$sh" install "$plug"
rm -f "$dest/animated-grid.png"
truncate -s 12G "$dest/animated-grid.png"
started=$(date +%s)
bash "$sh" remove "$plug"
elapsed=$(( $(date +%s) - started ))
check "oversized marker is not hashed"    '[ "$elapsed" -lt 5 ] && [ -f "$dest/animated-grid.png" ]'
teardown

# A FIFO under a marker name must not block the read.
setup
mkdir -p "$dest"
mkfifo "$dest/animated-grid.png"
timeout 10 bash "$sh" remove "$plug"
check "fifo at a marker name is skipped"  '[ "$?" != 124 ] && [ -p "$dest/animated-grid.png" ]'
teardown

echo
echo "launch environment and teardown"

# bash sources BASH_ENV before the script's first line, so only the launch site can
# stop it. These run the argv Service.qml uses; Quickshell's clearEnvironment itself
# is not reachable from a shell suite, so it is asserted statically below.
setup
printf 'touch "%s/BASH_ENV_RAN"\n' "$root" >"$root/evil.sh"
BASH_ENV="$root/evil.sh" /usr/bin/bash "$sh" install "$plug"
check "control: BASH_ENV fires on a dirty env" '[ -e "$root/BASH_ENV_RAN" ]'
rm -f "$root/BASH_ENV_RAN"
BASH_ENV="$root/evil.sh" env -i HOME="$HOME" /usr/bin/timeout -k 5 30 /usr/bin/bash "$sh" install "$plug"
check "hostile BASH_ENV is not sourced"        '[ ! -e "$root/BASH_ENV_RAN" ]'
teardown

check "Service.qml clears the environment"     'grep -q "clearEnvironment: true" "$(dirname "$sh")/Service.qml"'
check "Service.qml bounds the helper"          'grep -q "/usr/bin/timeout" "$(dirname "$sh")/Service.qml"'

# The destination does not exist yet, so the create path runs; the theme is swapped
# for a symlinked decoy at exactly that moment.
setup
rm -rf "$dest"
mkdir -p "$root/next-theme"
make_shim mkdir 1
PATH="$root/shim:$PATH" bash "$(unpinned)" install "$plug"
check "no create in a replaced theme"          '[ ! -e "$HOME/.local/state/omarchy/current/theme/backgrounds" ]'
teardown

# TERM during the run must clean up and then die of the signal.
setup
cat >"$root/killer" <<'KILL'
#!/bin/bash
gp=$(awk '{print $4}' "/proc/$PPID/stat")
kill -TERM "$gp" 2>/dev/null
exec /usr/bin/mktemp "$@"
KILL
chmod 755 "$root/killer"
mkdir -p "$root/shim"; cp "$root/killer" "$root/shim/mktemp"
( PATH="$root/shim:$PATH" bash "$(unpinned)" install "$plug" ) 2>/dev/null
rc=$?
check "TERM exits with the signal status"      '[ "$rc" -ge 128 ]'
check "TERM leaves no temporary behind"        '[ -z "$(find "$dest" \( -name ".animated-*" -o -name ".claim-*" -o -name ".grab-*" \) -print -quit)" ]'
teardown

echo
echo "usage"
out=$(bash "$sh" 2>&1)
rc=$?
check "bare invocation exits 1"      '[ "$rc" = 1 ]'
check "usage names both verbs"       'grep -q "install <plugin-dir> | markers.sh remove <plugin-dir>" <<<"$out"'

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
