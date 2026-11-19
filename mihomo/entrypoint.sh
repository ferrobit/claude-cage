#!/bin/sh
# Entrypoint for claude-cage.
#
# Starts the embedded mihomo instance and the loopback forwarder to the host's
# SOCKS5 service, installs an egress firewall, then hands over to the container
# command (normally `sleep infinity`).  The helpers are supervised so a
# transient host-side hiccup does not permanently take the container offline.
set -eu

# The host's SOCKS5 port comes from compose.yml (HOST_PROXY_PORT), which is
# the only place that defines it.
HOST_PROXY_PORT="${HOST_PROXY_PORT:-}"
case "$HOST_PROXY_PORT" in
    ''|0*|*[!0-9]*)
        echo "claude-cage: invalid HOST_PROXY_PORT '${HOST_PROXY_PORT}'" >&2
        exit 1
        ;;
esac
if [ "$HOST_PROXY_PORT" -gt 65535 ]; then
    echo "claude-cage: invalid HOST_PROXY_PORT '${HOST_PROXY_PORT}'" >&2
    exit 1
fi

MIHOMO_DIR=/var/lib/mihomo
MIHOMO_CONFIG="$MIHOMO_DIR/config.yaml"

# /etc/mihomo/config.yaml is a template: write the runtime copy with the
# actual port, so changing the port needs no image rebuild.
render_mihomo_config() {
    sed "s/[\$]{HOST_PROXY_PORT}/${HOST_PROXY_PORT}/g" \
        /etc/mihomo/config.yaml > "$MIHOMO_CONFIG"
    if grep -qF '${HOST_PROXY_PORT}' "$MIHOMO_CONFIG"; then
        echo "claude-cage: failed to render $MIHOMO_CONFIG" >&2
        exit 1
    fi
}

# Forward 127.0.0.1:HOST_PROXY_PORT inside the container to the same port on
# the host.  This keeps mihomo's proxy entry exactly
# `127.0.0.1:HOST_PROXY_PORT` without exposing any additional listener.
# `nodelay` sets TCP_NODELAY on both sockets: socat otherwise leaves Nagle's
# algorithm on, which holds small packets back.
forward_loop() {
    while :; do
        socat TCP-LISTEN:${HOST_PROXY_PORT},bind=127.0.0.1,fork,reuseaddr,nodelay \
            TCP:host.docker.internal:${HOST_PROXY_PORT},nodelay || true
        sleep 2
    done
}

# mihomo listens on loopback only (mixed-port 7890) and routes every
# connection through host-proxy.
mihomo_loop() {
    while :; do
        mihomo -d "$MIHOMO_DIR" -f "$MIHOMO_CONFIG" || true
        sleep 2
    done
}

# Deny every outbound packet except:
#   - loopback (mihomo, socat, Docker's DNS socket)
#   - established/related replies
#   - the host's SOCKS5 port used by socat
# This prevents applications that ignore proxy environment variables from
# falling back to the host's own internet connection.
apply_egress_firewall() {
    host_gw="$(getent ahostsv4 host.docker.internal | awk 'NR == 1 { print $1 }')"
    if [ -z "$host_gw" ]; then
        echo "claude-cage: cannot resolve host.docker.internal" >&2
        exit 1
    fi

    sudo -n iptables -F OUTPUT
    sudo -n iptables -A OUTPUT -o lo -j ACCEPT
    sudo -n iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    sudo -n iptables -A OUTPUT -d "$host_gw" -p tcp --dport "$HOST_PROXY_PORT" -j ACCEPT
    sudo -n iptables -P OUTPUT DROP

    # The container has no IPv6 path; drop it as well when supported.
    if command -v ip6tables >/dev/null 2>&1; then
        sudo -n ip6tables -F OUTPUT 2>/dev/null || true
        sudo -n ip6tables -A OUTPUT -o lo -j ACCEPT 2>/dev/null || true
        sudo -n ip6tables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
        sudo -n ip6tables -P OUTPUT DROP 2>/dev/null || true
    fi
}

render_mihomo_config
apply_egress_firewall
forward_loop &
mihomo_loop &

# Plasma keeps its own copy of the locale settings in the home directory; the
# bind-mounted home starts empty, so seed it from LANG and LANGUAGE.  The
# timezone itself comes from /etc/localtime.
seed_kde_locale() {
    conf="${HOME:-/root}/.config/plasma-localerc"
    [ -e "$conf" ] && return 0
    mkdir -p "$(dirname "$conf")" 2>/dev/null || return 0
    {
        echo '[Formats]'
        echo "LANG=${LANG}"
        echo "LC_MEASUREMENT=${LANG}"
        echo
        echo '[Translations]'
        echo "LANGUAGE=${LANGUAGE}"
    } > "$conf" 2>/dev/null || true
}
seed_kde_locale

# Claude's file dialog (GTK, used by Electron) builds its sidebar from
# ~/.config/gtk-3.0/bookmarks.  The host's ~/Claude is bind-mounted at the
# same path, so bookmark it there; the entry then shows up as "Claude (host)"
# in the standard open/save dialog.  Existing bookmarks are preserved.
seed_file_dialog_bookmark() {
    dir="${HOME:-/root}/.config/gtk-3.0"
    file="$dir/bookmarks"
    entry="file://${HOME:-/root}/Claude Claude (host)"
    mkdir -p "$dir" 2>/dev/null || return 0
    if [ -f "$file" ] && grep -qxF "$entry" "$file"; then
        return 0
    fi
    printf '%s\n' "$entry" >> "$file" 2>/dev/null || true
}
seed_file_dialog_bookmark

exec "$@"
