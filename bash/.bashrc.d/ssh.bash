command -v ssh &>/dev/null || return

# A pty for a remote command too, not just a bare login session; -T opts out per call.
ssh() { command ssh -o RequestTTY=yes "$@"; }
