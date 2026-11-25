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
IMAGE_NAME="claude-cage"

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

# The container has its own home directory (~/.config/codespace/home), so the
# host Xauthority file is exposed separately as a single read-only file.  On a
# Wayland session XAUTHORITY often lives under XDG_RUNTIME_DIR;
# `xhost +si:localuser` covers X11 access either way.
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

# Create the dedicated container home and the host ~/Codespace hand-off folder
# before compose does, so they are owned by the invoking user rather than
# root.  The empty Codespace mount point inside the container home is created
# too: otherwise Docker creates it as root.
ensure_home() {
    mkdir -p "$HOME/.config/codespace/home/Codespace"
    mkdir -p "$HOME/Codespace"
}

# Set by the --up option: start the container on demand instead of failing.
AUTO_UP=0

container_running() {
    docker inspect -f '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null | grep -q true
}

start_container() {
    allow_x11
    ensure_home
    "${COMPOSE[@]}" up -d --build --remove-orphans "$@"
}

# The entrypoint starts mihomo in the background, so a freshly started
# container may not accept proxy connections yet.  Wait up to 15 seconds for
# the local listener before launching applications that need the network.
wait_for_proxy() {
    local attempt
    for attempt in $(seq 1 30); do
        if docker exec "$CONTAINER_NAME" bash -c 'exec 3<>/dev/tcp/127.0.0.1/7890' 2>/dev/null; then
            return 0
        fi
        sleep 0.5
    done
    echo "warning: mihomo is not listening on 127.0.0.1:7890 yet; see: $0 logs" >&2
}

require_container() {
    if container_running; then
        return 0
    fi
    if [ "$AUTO_UP" != 1 ]; then
        echo "error: $CONTAINER_NAME is not running; start it with: $0 up" >&2
        echo "       or add --up to start it on demand: $0 --up <command>" >&2
        exit 1
    fi
    echo "$CONTAINER_NAME is not running; starting it" >&2
    start_container
    if ! container_running; then
        echo "error: $CONTAINER_NAME did not start; see: $0 logs" >&2
        exit 1
    fi
    wait_for_proxy
}

usage() {
    cat <<EOF
Usage: $(basename "$0") [--up] <command> [arguments...]

Options:
  --up                  Start the container first if it is not running
                        (GUI commands, shell, run)

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
  brave [args...]       Launch Brave on the host display
  dolphin [args...]     Launch Dolphin on the host display
  konsole [args...]     Launch Konsole on the host display
  kate [args...]        Launch Kate on the host display

Host menu:
  install-menu          Add a Codespace section with these applications to
                        the host's application menu
  uninstall-menu        Remove the Codespace section again

Inside the container:
  shell                 Interactive bash shell
  run <command...>      Run a command in the foreground
  exec <command...>     Alias for run

Examples:
  $(basename "$0") up
  $(basename "$0") claude
  $(basename "$0") --up claude
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

# ---------------------------------------------------------------------------
# Host menu
#
# install-menu adds a "Codespace" section to the host's application menu.
# Every entry runs this script with --up, so the container starts on demand.
# Only files under the user's home are written: desktop entries, a .directory
# file, an XDG merged menu and icons copied from the image.
# ---------------------------------------------------------------------------
MENU_PREFIX="claude-cage"
MENU_CATEGORY="X-Codespace"
MENU_DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}"
MENU_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"
MENU_APPLICATIONS_DIR="$MENU_DATA_DIR/applications"
MENU_DIRECTORIES_DIR="$MENU_DATA_DIR/desktop-directories"
MENU_MERGED_DIR="$MENU_CONFIG_DIR/menus/applications-merged"
MENU_ICONS_DIR="$MENU_DATA_DIR/$MENU_PREFIX/icons"
MENU_DIRECTORY_FILE="$MENU_PREFIX-codespace.directory"
MENU_FILE="$MENU_MERGED_DIR/$MENU_PREFIX-codespace.menu"

# command|name|comment|binary in the image|fallback icon|field code|terminal
MENU_ENTRIES=(
    "claude|Claude Desktop|Claude Desktop in the claude-cage container|claude-desktop|claude-desktop||false"
    "firefox|Firefox|Firefox in the claude-cage container|firefox|firefox|%U|false"
    "brave|Brave|Brave in the claude-cage container|brave|brave-browser|%U|false"
    "dolphin|Dolphin|Dolphin file manager in the claude-cage container|dolphin|org.kde.dolphin||false"
    "konsole|Konsole|Konsole terminal in the claude-cage container|konsole|org.kde.konsole||false"
    "kate|Kate|Kate text editor in the claude-cage container|kate|org.kde.kate||false"
    "shell|Shell|Bash shell in the claude-cage container||utilities-terminal||true"
)

refresh_menu_cache() {
    local tool
    for tool in kbuildsycoca6 kbuildsycoca5; do
        if command -v "$tool" >/dev/null 2>&1; then
            "$tool" >/dev/null 2>&1 || true
            return 0
        fi
    done
}

# The Exec key is written as a double-quoted argument; refuse the characters
# that would need desktop-entry escaping instead of escaping them.
menu_exec_path() {
    local path="$SCRIPT_DIR/claude-cage.sh"
    case "$path" in
        *'"'*|*'`'*|*'$'*|*'\'*|*'%'*|*$'\n'*)
            echo "error: cannot write menu entries for path: $path" >&2
            exit 1
            ;;
    esac
    printf '"%s"\n' "$path"
}

# Copy the icon of <binary> out of the image into MENU_ICONS_DIR and print the
# value for the Icon key.  The image's desktop files are read from a
# container that is created but never started.  When nothing can be copied,
# the fallback icon name from the host's icon theme is printed instead.
menu_icon() {
    local source_id="$1" apps_dir="$2" command="$3" binary="$4" fallback="$5"
    local desktop icon candidate extension
    if [ -z "$source_id" ] || [ -z "$binary" ]; then
        printf '%s\n' "$fallback"
        return 0
    fi
    desktop="$(grep -l -E "^Exec=([^ ]*/)?$binary( |$)" "$apps_dir"/*.desktop 2>/dev/null | head -n 1)"
    if [ -n "$desktop" ]; then
        icon="$(sed -n 's/^Icon=//p' "$desktop" | head -n 1)"
    fi
    icon="${icon:-$fallback}"
    for candidate in \
        "$icon" \
        "/usr/share/icons/hicolor/256x256/apps/$icon.png" \
        "/usr/share/icons/hicolor/512x512/apps/$icon.png" \
        "/usr/share/icons/hicolor/128x128/apps/$icon.png" \
        "/usr/share/icons/hicolor/scalable/apps/$icon.svg" \
        "/usr/share/pixmaps/$icon.png" \
        "/usr/share/pixmaps/$icon.svg"; do
        case "$candidate" in
            /*) ;;
            *) continue ;;
        esac
        extension="${candidate##*.}"
        if docker cp -L "$source_id:$candidate" "$MENU_ICONS_DIR/$command.$extension" >/dev/null 2>&1; then
            printf '%s\n' "$MENU_ICONS_DIR/$command.$extension"
            return 0
        fi
    done
    printf '%s\n' "$icon"
}

install_menu() {
    local exec_path source_id="" apps_dir entry command name comment binary
    local fallback field terminal icon exec_line directory_icon=""
    exec_path="$(menu_exec_path)"
    mkdir -p "$MENU_APPLICATIONS_DIR" "$MENU_DIRECTORIES_DIR" "$MENU_MERGED_DIR"
    rm -rf "$MENU_ICONS_DIR"
    mkdir -p "$MENU_ICONS_DIR"
    apps_dir="$(mktemp -d)"
    if docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
        source_id="$(docker create "$IMAGE_NAME" 2>/dev/null || true)"
    else
        echo "warning: image $IMAGE_NAME not found; using icons from the host theme" >&2
        echo "         (run $0 build, then $0 install-menu again)" >&2
    fi
    if [ -n "$source_id" ]; then
        docker cp "$source_id:/usr/share/applications/." "$apps_dir" >/dev/null 2>&1 || true
    fi
    for entry in "${MENU_ENTRIES[@]}"; do
        IFS='|' read -r command name comment binary fallback field terminal <<<"$entry"
        icon="$(menu_icon "$source_id" "$apps_dir" "$command" "$binary" "$fallback")"
        if [ "$command" = claude ]; then
            directory_icon="$icon"
        fi
        exec_line="$exec_path --up $command${field:+ $field}"
        {
            printf '%s\n' '[Desktop Entry]'
            printf '%s\n' 'Type=Application'
            printf '%s\n' 'Version=1.0'
            printf 'Name=%s\n' "$name"
            printf 'Comment=%s\n' "$comment"
            printf 'Exec=%s\n' "$exec_line"
            printf 'Icon=%s\n' "$icon"
            printf 'Terminal=%s\n' "$terminal"
            printf 'Categories=%s;\n' "$MENU_CATEGORY"
        } > "$MENU_APPLICATIONS_DIR/$MENU_PREFIX-$command.desktop"
    done
    if [ -n "$source_id" ]; then
        docker rm "$source_id" >/dev/null 2>&1 || true
    fi
    rm -rf "$apps_dir"
    {
        printf '%s\n' '[Desktop Entry]'
        printf '%s\n' 'Type=Directory'
        printf '%s\n' 'Version=1.0'
        printf '%s\n' 'Name=Codespace'
        printf '%s\n' 'Comment=Applications in the claude-cage container'
        printf 'Icon=%s\n' "${directory_icon:-applications-development}"
    } > "$MENU_DIRECTORIES_DIR/$MENU_DIRECTORY_FILE"
    {
        printf '%s\n' '<!DOCTYPE Menu PUBLIC "-//freedesktop//DTD Menu 1.0//EN"'
        printf '%s\n' ' "http://www.freedesktop.org/standards/menu-spec/menu-1.0.dtd">'
        printf '%s\n' '<Menu>'
        printf '%s\n' '  <Name>Applications</Name>'
        printf '%s\n' '  <Menu>'
        printf '%s\n' '    <Name>Codespace</Name>'
        printf '    <Directory>%s</Directory>\n' "$MENU_DIRECTORY_FILE"
        printf '%s\n' '    <Include>'
        printf '      <Category>%s</Category>\n' "$MENU_CATEGORY"
        printf '%s\n' '    </Include>'
        printf '%s\n' '  </Menu>'
        printf '%s\n' '</Menu>'
    } > "$MENU_FILE"
    refresh_menu_cache
    echo "Installed the Codespace menu with ${#MENU_ENTRIES[@]} entries"
}

uninstall_menu() {
    local entry command
    for entry in "${MENU_ENTRIES[@]}"; do
        command="${entry%%|*}"
        rm -f "$MENU_APPLICATIONS_DIR/$MENU_PREFIX-$command.desktop"
    done
    rm -f "$MENU_DIRECTORIES_DIR/$MENU_DIRECTORY_FILE" "$MENU_FILE"
    rm -rf "$MENU_ICONS_DIR"
    rmdir "$MENU_DATA_DIR/$MENU_PREFIX" 2>/dev/null || true
    refresh_menu_cache
    echo "Removed the Codespace menu"
}

while [ $# -gt 0 ]; do
    case "$1" in
        --up)
            AUTO_UP=1
            shift
            ;;
        *)
            break
            ;;
    esac
done

cmd="${1:-help}"
[ $# -gt 0 ] && shift || true

case "$cmd" in
    build)
        "${COMPOSE[@]}" build "$@"
        ;;
    up|start)
        start_container "$@"
        ;;
    down|stop)
        "${COMPOSE[@]}" down "$@"
        ;;
    restart)
        "${COMPOSE[@]}" down
        start_container
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
    brave|brave-browser)
        run_gui brave "$@"
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
    install-menu)
        install_menu
        ;;
    uninstall-menu)
        uninstall_menu
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
