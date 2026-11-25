#!/usr/bin/env bash
#
# Install the lan-harden nftables rules on the exit VPS.
#
# The 2ip.io privacy check probes the IP that reaches the website (the
# host's SOCKS5 exit) for ICMP echo/timestamp replies and for ICMP-unreachable
# answers to VPN-port probes.  Those probes never reach the claude-cage
# container, so they have to be dropped on the exit host itself.
#
# Usage: ./install-harden.sh [root@host]
#
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
VPS="${1:-root@<IP>}"
KEY="${KEY:-$SCRIPT_DIR/vps.pem}"

scp -q -i "$KEY" -o BatchMode=yes \
    "$SCRIPT_DIR/lan-harden.nft" "$SCRIPT_DIR/lan-harden.service" \
    "$VPS:/tmp/"

ssh -i "$KEY" -o BatchMode=yes "$VPS" '
    set -eu
    install -m 0644 /tmp/lan-harden.nft /etc/lan-harden.nft
    install -m 0644 /tmp/lan-harden.service /etc/systemd/system/lan-harden.service
    rm -f /tmp/lan-harden.nft /tmp/lan-harden.service
    systemctl daemon-reload
    systemctl enable --now lan-harden.service
    systemctl --no-pager --lines=0 status lan-harden.service
    nft list table inet lan_harden
'
