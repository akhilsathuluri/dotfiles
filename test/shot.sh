#!/usr/bin/env bash
# Guards `shot`: the local half of getting a screenshot in front of an agent on
# another machine. Two properties matter and neither is visible by eye:
#
#   1. the path typed into the pane names the file that was actually written -
#      the failure is an agent told to read something that is not there;
#   2. the file and the path go to the SAME host, so a focus change between the
#      two halves cannot strand them.
#
# ssh is stubbed with a second HOME, which is what makes the remote leg real:
# the receiver script has to expand $HOME at the far end, and the test can then
# assert the file landed under that other home. dictate is a recorder, so
# nothing is typed into a live pane and DICTATE_REMOTE is observable.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHOT="$REPO/shot/.local/bin/shot"
pass=0 fail=0

ok() {
    pass=$((pass + 1))
    printf '  \033[32m✓\033[0m %s\n' "$1"
}
no() {
    fail=$((fail + 1))
    printf '  \033[31m✗\033[0m %s\n' "$1"
    [ $# -gt 1 ] && printf '      %s\n' "$2"
}
eq() { [ "$2" = "$3" ] && ok "$1" || no "$1" "want [$2] got [$3]"; }
has() { grep -qF -- "$2" <<<"$1" && ok "$3" || no "$3" "no [$2] in [$1]"; }

TMP=$(mktemp -d)
FARHOME="$TMP/far"
export DOTFILES_TRACE=0
export SHOT_SOURCE_DIR="$TMP/shots"
export TMPDIR="$TMP/tmp"
mkdir -p "$TMP/shim" "$SHOT_SOURCE_DIR" "$FARHOME" "$TMPDIR"
export PATH="$TMP/shim:$PATH"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

# ssh stub: the far machine, with its own HOME. The command is the last argument
# and stdin is the image, exactly as the real thing hands them over.
cat >"$TMP/shim/ssh" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>$TMP/ssh.log
for a in "\$@"; do cmd=\$a; done
[ "\$cmd" = true ] && exit 0
HOME=$FARHOME exec sh -c "\$cmd"
EOF

# dictate stub: records the route it was pinned to and every argument.
cat >"$TMP/shim/dictate" <<EOF
#!/usr/bin/env bash
if [ "\$1" = --route ]; then printf '%s\n' "\${STUB_ROUTE:-}"; exit 0; fi
printf 'remote=[%s] args=[%s]\n' "\${DICTATE_REMOTE-unset}" "\$*" >>$TMP/typed.log
EOF

# pngpaste stub: first in shot's backend order, so the clipboard is decided here
# and never by whatever this machine really has. Empty output = no image.
cat >"$TMP/shim/pngpaste" <<EOF
#!/usr/bin/env bash
[ -n "\${STUB_CLIP:-}" ] && printf '%s' "\$STUB_CLIP"
exit 0
EOF
chmod +x "$TMP/shim/ssh" "$TMP/shim/dictate" "$TMP/shim/pngpaste"
export DICTATE_BIN="$TMP/shim/dictate"

reset() {
    : >"$TMP/typed.log"
    : >"$TMP/ssh.log"
    rm -rf "$FARHOME" "$TMP/landing"
    mkdir -p "$FARHOME"
    unset STUB_CLIP STUB_ROUTE
}
typed() { tr -d '\n' <"$TMP/typed.log"; }
# The path shot said it wrote, taken out of what it typed.
typed_path() { sed -n 's/.*args=\[--type \(.*\)\]/\1/p' "$TMP/typed.log" | sed 's/ *$//' | head -1; }
landed() { find "$1" -type f -name 'shot-*' 2>/dev/null | head -1; }

printf '%s' 'PNGDATA' >"$TMP/pic.png"

# ---- a file, to this machine ------------------------------------------------
printf '\nlocal\n'
reset
export SHOT_REMOTE=""
export SHOT_DIR="$TMP/landing"
out=$("$SHOT" "$TMP/pic.png" 2>&1)
f=$(landed "$TMP/landing")
[ -n "$f" ] && ok "the image lands where it was told" || no "the image lands where it was told" "$out"
eq "with its bytes intact" PNGDATA "$(cat "$f" 2>/dev/null)"
has "$(typed)" "$f" "and the pane is typed that exact path"
has "$(typed)" "args=[--type $f ]" "with a trailing space, so a question can follow"
eq "no ssh for a local route" "" "$(cat "$TMP/ssh.log")"

# ---- a file, to another machine ---------------------------------------------
printf '\nremote\n'
reset
unset SHOT_DIR
export SHOT_REMOTE=faraway
out=$("$SHOT" "$TMP/pic.png" 2>&1)
f=$(landed "$FARHOME")
[ -n "$f" ] && ok "the receiver expands \$HOME at the far end" ||
    no "the receiver expands \$HOME at the far end" "$out"
has "$f" ".cache/dotfiles/shots/shot-" "into the default folder there"
eq "the path typed is the path written" "$f" "$(typed_path)"
has "$(typed)" "remote=[faraway]" "and the typing is pinned to that same host"
has "$(cat "$TMP/ssh.log")" "faraway" "over ssh"

# ---- one route, asked once --------------------------------------------------
printf '\nroute\n'
reset
unset SHOT_REMOTE
export STUB_ROUTE=viadictate
"$SHOT" "$TMP/pic.png" >/dev/null 2>&1
has "$(typed)" "remote=[viadictate]" "dictate's own route is used when there is no pin"
reset
unset SHOT_REMOTE STUB_ROUTE
mkdir -p "$TMP/dotcfg/dictate"
printf '# a comment\n\nfromfile\n' >"$TMP/dotcfg/dictate/remote"
HOME_SAVE=$HOME
HOME="$TMP" ln -sfn "$TMP/dotcfg" "$TMP/.config" 2>/dev/null
out=$(HOME="$TMP" DICTATE_BIN=/nonexistent "$SHOT" --check 2>&1)
has "$out" "fromfile" "and dictate's candidate file is the last resort"
has "$out" "dictate-remote-file" "which --check names"
HOME=$HOME_SAVE

# ---- where the image comes from ---------------------------------------------
printf '\nsource\n'
reset
export SHOT_REMOTE="" SHOT_DIR="$TMP/landing"
export STUB_CLIP=FROMCLIP
"$SHOT" >/dev/null 2>&1
eq "the clipboard wins when it holds an image" FROMCLIP "$(cat "$(landed "$TMP/landing")")"

reset
export STUB_CLIP=""
printf '%s' 'OLDER' >"$SHOT_SOURCE_DIR/a.png"
sleep 1
printf '%s' 'NEWEST' >"$SHOT_SOURCE_DIR/b.png"
"$SHOT" >/dev/null 2>&1
eq "an empty clipboard falls back to the newest file" NEWEST "$(cat "$(landed "$TMP/landing")")"

reset
out=$("$SHOT" --clip 2>&1)
rc=$?
[ "$rc" -ne 0 ] && ok "--clip never falls back to the folder" ||
    no "--clip never falls back to the folder" "rc=0"
has "$out" "no image" "and says why"

reset
printf '%s' 'JPEG' >"$SHOT_SOURCE_DIR/c.JPG"
"$SHOT" "$SHOT_SOURCE_DIR/c.JPG" >/dev/null 2>&1
has "$(landed "$TMP/landing")" ".jpg" "a jpeg keeps its extension"

# ---- refusals ---------------------------------------------------------------
printf '\nrefusals\n'
reset
out=$("$SHOT" "$TMP/nope.png" 2>&1)
[ $? -ne 0 ] && ok "a missing file fails" || no "a missing file fails"
has "$out" "no such file" "by name"
: >"$TMP/empty.png"
out=$("$SHOT" "$TMP/empty.png" 2>&1)
has "$out" "empty image" "an empty file is refused before any ssh"

# ---- --send -----------------------------------------------------------------
printf '\nsend\n'
reset
"$SHOT" --send >/dev/null 2>&1
has "$(typed)" -- "--send" "--send presses Enter after the path"
grep -qF 'args=[--type ' "$TMP/typed.log" &&
    ! grep -qE 'args=\[--type .* \]$' "$TMP/typed.log" &&
    ok "and drops the trailing space, so Enter submits the path alone" ||
    no "and drops the trailing space" "$(typed)"

# ---- pruning ----------------------------------------------------------------
printf '\nprune\n'
reset
mkdir -p "$TMP/landing"
touch -t 202001010000 "$TMP/landing/shot-ancient.png"
printf '%s' 'x' >"$TMP/landing/shot-ancient.png"
touch -t 202001010000 "$TMP/landing/shot-ancient.png"
"$SHOT" "$TMP/pic.png" >/dev/null 2>&1
[ -f "$TMP/landing/shot-ancient.png" ] &&
    no "an old image is pruned on the next send" "still there" ||
    ok "an old image is pruned on the next send"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
