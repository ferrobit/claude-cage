#!/usr/bin/env bash
#
# Host-side helper for the claude-cage Docker desktop.
#
# It exports the host identity/session variables that compose.yml expects,
# allows the host X server to accept windows from the same user, and wraps
# common GUI applications in `docker exec`.
#
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="$SCRIPT_DIR/compose.yml"
PROJECT_NAME="claude-cage"
CONTAINER_NAME="claude-cage"

HOST_USER="$(id -un)"
HOST_UID="$(id -u)"
HOST_GID="$(id -g)"
export HOST_USER HOST_UID HOST_GID
export USER="$HOST_USER"
export LOGNAME="$HOST_USER"
export HOME="${HOME:-$(getent passwd "$HOST_USER" | cut -d: -f6)}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$HOST_UID}"
export DISPLAY="${DISPLAY:-:0}"

# Compose cannot run `id`, so resolve supplementary device/audio GIDs here.
group_gid() {
    getent group "$1" 2>/dev/null | cut -d: -f3 || true
}
export VIDEO_GID="${VIDEO_GID:-$(group_gid video)}"
export RENDER_GID="${RENDER_GID:-$(group_gid render)}"
export AUDIO_GID="${AUDIO_GID:-$(group_gid audio)}"
export INPUT_GID="${INPUT_GID:-$(group_gid input)}"
export VIDEO_GID="${VIDEO_GID:-986}"
export RENDER_GID="${RENDER_GID:-989}"
export AUDIO_GID="${AUDIO_GID:-995}"
export INPUT_GID="${INPUT_GID:-993}"

# The container timezone is fixed in compose.yml (it matches the proxy exit
# location), so the host timezone is intentionally not forwarded.

# The container has its own home directory (./home), so the host Xauthority
# file is exposed separately as a single read-only file.  On a Wayland session
# XAUTHORITY often lives under XDG_RUNTIME_DIR; `xhost +si:localuser` covers
# X11 access either way.
HOST_XAUTHORITY="${XAUTHORITY:-$HOME/.Xauthority}"
if [ -f "$HOST_XAUTHORITY" ]; then
    export XAUTHORITY_FILE="$HOST_XAUTHORITY"
else
    export XAUTHORITY_FILE=/dev/null
fi

COMPOSE=(docker compose --project-name "$PROJECT_NAME" -f "$COMPOSE_FILE")

# A process with our UID must be allowed to talk to the host X server.  This
# is sufficient for both Xorg and XWayland; it does not grant access to other
# local users.
allow_x11() {
    if [ -n "${DISPLAY:-}" ] && command -v xhost >/dev/null 2>&1; then
        xhost +si:localuser:"$HOST_USER" >/dev/null 2>&1 || true
    fi
}

# Map the host Xauthority path into the container.  The wrapper mounts the
# file at a fixed location instead of sharing the host home directory.
container_xauthority() {
    printf '/run/host/xauthority\n'
}

# Create the dedicated container home before compose does, so it is owned by
# the invoking user rather than root.  The host ~/Claude hand-off folder is
# bind-mounted into it (see compose.yml), so create it as the user as well.
ensure_home() {
    mkdir -p "$SCRIPT_DIR/home"
    mkdir -p "$HOME/Claude"
}

require_container() {
    if ! docker inspect -f '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null | grep -q true; then
        echo "error: $CONTAINER_NAME is not running; start it with: $0 up" >&2
        exit 1
    fi
}

usage() {
    cat <<EOF
Usage: $(basename "$0") <command> [arguments...]

Lifecycle:
  build                 Build the claude-cage image
  up [--build]          Start the desktop container
  down                  Stop and remove the container
  restart               Recreate the container
  ps                    Show container status
  logs [service]        Follow logs (default: all services)

Desktop / GUI:
  claude [args...]      Launch Claude Desktop on the host display
  firefox [args...]     Launch Firefox on the host display
  dolphin [args...]     Launch Dolphin on the host display
  konsole [args...]     Launch Konsole on the host display
  kate [args...]        Launch Kate on the host display

Inside the container:
  shell                 Interactive bash shell
  run <command...>      Run a command in the foreground
  exec <command...>     Alias for run

Environment:
  HOST_PROXY_PORT       Host SOCKS5 port (default: 7800, see compose.yml)

Examples:
  $(basename "$0") up
  HOST_PROXY_PORT=1080 $(basename "$0") up
  $(basename "$0") claude
  $(basename "$0") firefox
  $(basename "$0") run pacman -Q arc-kde-git
EOF
}

run_gui() {
    require_container
    allow_x11
    docker exec -d -u "$HOST_UID:$HOST_GID" \
        -e DISPLAY="$DISPLAY" \
        -e XAUTHORITY="$(container_xauthority)" \
        -e WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-}" \
        -e XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
        -e XDG_SESSION_TYPE="${XDG_SESSION_TYPE:-x11}" \
        -e DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus" \
        -e PULSE_SERVER="unix:$XDG_RUNTIME_DIR/pulse/native" \
        "$CONTAINER_NAME" "$@"
}

run_interactive() {
    require_container
    allow_x11
    # Use a TTY only when the caller has one; this keeps `run` usable from
    # scripts and cron jobs as well as from an interactive terminal.
    local tty_flags=(-i)
    if [ -t 0 ] && [ -t 1 ]; then
        tty_flags=(-it)
    fi
    docker exec "${tty_flags[@]}" -u "$HOST_UID:$HOST_GID" \
        -e DISPLAY="$DISPLAY" \
        -e XAUTHORITY="$(container_xauthority)" \
        -e WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-}" \
        -e XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
        -e XDG_SESSION_TYPE="${XDG_SESSION_TYPE:-x11}" \
        -e DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus" \
        -e PULSE_SERVER="unix:$XDG_RUNTIME_DIR/pulse/native" \
        "$CONTAINER_NAME" "$@"
}

cmd="${1:-help}"
[ $# -gt 0 ] && shift || true

case "$cmd" in
    build)
        "${COMPOSE[@]}" build "$@"
        ;;
    up|start)
        allow_x11
        ensure_home
        "${COMPOSE[@]}" up -d --build --remove-orphans "$@"
        ;;
    down|stop)
        "${COMPOSE[@]}" down "$@"
        ;;
    restart)
        "${COMPOSE[@]}" down
        allow_x11
        ensure_home
        "${COMPOSE[@]}" up -d --build --remove-orphans
        ;;
    ps|status)
        "${COMPOSE[@]}" ps "$@"
        ;;
    logs)
        "${COMPOSE[@]}" logs -f --tail=200 "$@"
        ;;
    shell|bash)
        run_interactive bash -l
        ;;
    run|exec)
        if [ $# -eq 0 ]; then
            echo "error: run requires a command" >&2
            exit 1
        fi
        run_interactive "$@"
        ;;
    claude|claude-desktop|claude-code)
        run_gui claude-desktop "$@"
        ;;
    firefox)
        run_gui firefox "$@"
        ;;
    dolphin)
        run_gui dolphin "$@"
        ;;
    konsole)
        run_gui konsole "$@"
        ;;
    kate)
        run_gui kate "$@"
        ;;
    help|-h|--help)
        usage
        ;;
    *)
        echo "error: unknown command: $cmd" >&2
        echo
        usage
        exit 1
        ;;
esac
