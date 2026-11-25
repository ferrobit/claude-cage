# Manjaro KDE desktop image for claude-cage.
#
# Build context contains:
#   mihomo/         embedded proxy config and entrypoint
#   this file
#
# Claude Desktop is installed from the AUR package `claude-desktop`, which
# repackages Anthropic's official Debian build; no local .deb is needed.
#
# The image is intentionally a full KDE environment: plasma-meta plus a
# handful of KDE applications.  It is NOT a Manjaro ISO; manjarolinux/base
# is the official minimal Manjaro rootfs.

# Only the static mihomo binary is taken from the upstream image; mihomo runs
# inside the desktop container, not as a separate service.
FROM metacubex/mihomo:latest AS mihomo

FROM manjarolinux/base:latest

ARG USERNAME=user
ARG USER_UID=1000
ARG USER_GID=1000

# The mirrorlist shipped in the base image can point at a mirror whose package
# database is stale relative to the other mirrors (e.g. it advertises a
# Firefox version whose package file has already been replaced).  Use a small
# set of mirrors that were verified to carry the same repository snapshot.
RUN printf '%s\n' \
        'Server = https://ftp.halifax.rwth-aachen.de/manjaro/stable/$repo/$arch' \
        'Server = https://mirror.23m.com/manjaro/stable/$repo/$arch' \
        'Server = https://mirrors.tuna.tsinghua.edu.cn/manjaro/stable/$repo/$arch' \
        > /etc/pacman.d/mirrorlist

# Host device group IDs.  The image's "video"/"render"/"audio"/"input"
# groups must use the same numeric GIDs as the host so that processes
# started with `docker exec -u` can open /dev/dri and audio devices.
ARG VIDEO_GID=986
ARG RENDER_GID=989
ARG AUDIO_GID=995
ARG INPUT_GID=993

ENV LANG=en_US.UTF-8
ENV LC_ALL=${LANG}
ENV LANGUAGE=en_US:en
ENV TZ=America/Sao_Paulo

# ---------------------------------------------------------------------------
# Base system + KDE
# ---------------------------------------------------------------------------
RUN pacman-key --init \
 && (pacman-key --populate archlinux manjaro || true) \
 && pacman -Syu --noconfirm --needed

RUN pacman -S --noconfirm --needed \
        base-devel \
        git \
        sudo \
        libarchive \
        dbus \
        plasma-meta \
        dolphin \
        konsole \
        kate \
        ark \
        firefox \
        kde-cli-tools \
        kde-gtk-config \
        xdg-utils \
        xdg-desktop-portal \
        xdg-desktop-portal-kde \
        gtk3 \
        libnotify \
        nss \
        nspr \
        at-spi2-core \
        libdrm \
        mesa \
        libxcb \
        libxfixes \
        libxrender \
        libxss \
        libcups \
        libxcomposite \
        libxdamage \
        libxrandr \
        libxkbcommon \
        gdk-pixbuf2 \
        libsecret \
        libxtst \
        libsm \
        libice \
        alsa-lib \
        libpulse \
        breeze \
        breeze-gtk \
        noto-fonts \
        noto-fonts-emoji \
        ttf-dejavu \
        ttf-liberation

# Optional Claude Desktop integrations (the AUR package's optdepends).
# Hard dependencies such as qemu-system-x86, edk2-ovmf and virtiofsd are
# resolved by `makepkg -s` while the AUR package is built.
RUN pacman -S --noconfirm --needed \
        ca-certificates \
        kwallet \
        libayatana-appindicator

# ---------------------------------------------------------------------------
# AUR packages: arc-kde-git and claude-desktop
#
# makepkg refuses to run as root, so create a throw-away user, build the
# packages with sudo/makepkg, then remove that user again.  A dedicated UID far
# away from typical host UIDs keeps the image independent of the build host.
#
# `claude-desktop` repackages Anthropic's official .deb: its PKGBUILD downloads
# the archive and installs the payload under /usr/lib/claude-desktop.  Build
# dependencies (qemu-system-x86, edk2-ovmf, virtiofsd, ...) are installed by
# `makepkg -s`.
# ---------------------------------------------------------------------------
RUN set -eux; \
    useradd -m -u 60000 -U -s /bin/bash aurbuild; \
    printf 'aurbuild ALL=(ALL) NOPASSWD: ALL\n' > /etc/sudoers.d/aurbuild; \
    chmod 440 /etc/sudoers.d/aurbuild; \
    for pkg in arc-kde-git claude-desktop; do \
        ok=0; \
        for i in 1 2 3 4 5; do \
            if runuser -u aurbuild -- bash -lc \
                "set -e; rm -rf /tmp/$pkg; cd /tmp; git clone --depth=1 https://aur.archlinux.org/$pkg.git; cd $pkg; makepkg -si --noconfirm --needed"; then \
                ok=1; break; \
            fi; \
            echo "$pkg build attempt $i failed, retrying"; \
            sleep 5; \
        done; \
        [ "$ok" = 1 ]; \
        rm -rf "/tmp/$pkg"; \
    done; \
    rm -f /etc/sudoers.d/aurbuild; \
    userdel -r aurbuild 2>/dev/null || true; \
    groupdel aurbuild 2>/dev/null || true

# ---------------------------------------------------------------------------
# Claude Desktop wrapper
#
# The AUR package installs /usr/bin/claude-desktop (a launcher that selects the
# Wayland backend and reads ~/.config/claude-desktop-flags.conf) and the
# Electron payload at /usr/lib/claude-desktop.  A wrapper earlier in PATH keeps
# the proxy and sandbox flags in force even when that optional flags file is
# missing or edited.
# ---------------------------------------------------------------------------
RUN set -eux; \
    test -x /usr/lib/claude-desktop/claude-desktop; \
    mkdir -p /usr/local/bin; \
    printf '%s\n' \
        '#!/bin/sh' \
        '# Electron/Chromium sandbox is unreliable inside plain Docker.' \
        '# --no-zygote is required when unprivileged user namespaces are blocked.' \
        '# Internet access must go through the embedded mihomo listener.' \
        '# --lang is derived from LANG (de_DE.UTF-8 -> de-DE); disabling non-proxied UDP' \
        '# stops WebRTC from leaking the container or host address.' \
        'lang_tag="$(printf "%s" "${LANG%%[.@]*}" | tr _ -)"' \
        'exec /usr/lib/claude-desktop/claude-desktop \' \
        '    --no-sandbox --no-zygote --ozone-platform-hint=auto \' \
        '    --proxy-server=http://127.0.0.1:7890 \' \
        '    --lang="${lang_tag}" \' \
        '    --force-webrtc-ip-handling-policy=disable_non_proxied_udp \' \
        '    "$@"' \
        > /usr/local/bin/claude-desktop; \
    chmod 755 /usr/local/bin/claude-desktop

# Firefox does not read proxy environment variables.  An enterprise policy
# forces all browser traffic through the embedded mihomo listener, including
# DNS (the HTTP CONNECT proxy receives hostnames, not pre-resolved addresses).
#
# Geolocation is blocked outright: there is no usable GPS/network location in
# the container, and a granted request could reveal the host's real position.
# WebRTC is disabled so it cannot leak a non-proxied UDP address.  Region
# detection, captive-portal probes, connectivity checks and DoH are turned off
# because they would either bypass the proxy or reveal the real location.
RUN set -eux; \
    lang_tag="$(printf '%s' "${LANG%%[.@]*}" | tr _ -)"; \
    mkdir -p /usr/lib/firefox/distribution; \
    printf '%s\n' \
        '{' \
        '  "policies": {' \
        '    "Proxy": {' \
        '      "Mode": "manual",' \
        '      "Locked": true,' \
        '      "HTTPProxy": "127.0.0.1:7890",' \
        '      "UseHTTPProxyForAllProtocols": true,' \
        '      "SSLProxy": "127.0.0.1:7890",' \
        '      "FTPProxy": "127.0.0.1:7890",' \
        '      "Passthrough": "localhost, 127.0.0.1, ::1"' \
        '    },' \
        '    "DNSOverHTTPS": {' \
        '      "Enabled": false,' \
        '      "Locked": true' \
        '    },' \
        '    "RequestedLocales": ["'"${lang_tag}"'"],' \
        '    "Preferences": {' \
        '      "geo.enabled": {' \
        '        "Value": false,' \
        '        "Status": "locked"' \
        '      },' \
        '      "permissions.default.geo": {' \
        '        "Value": 2,' \
        '        "Status": "locked"' \
        '      },' \
        '      "media.peerconnection.enabled": {' \
        '        "Value": false,' \
        '        "Status": "locked"' \
        '      },' \
        '      "media.peerconnection.ice.proxy_only": {' \
        '        "Value": true,' \
        '        "Status": "locked"' \
        '      },' \
        '      "browser.region.update.enabled": {' \
        '        "Value": false,' \
        '        "Status": "locked"' \
        '      },' \
        '      "browser.region.network.url": {' \
        '        "Value": "",' \
        '        "Status": "locked"' \
        '      },' \
        '      "network.captive-portal-service.enabled": {' \
        '        "Value": false,' \
        '        "Status": "locked"' \
        '      },' \
        '      "network.connectivity-service.enabled": {' \
        '        "Value": false,' \
        '        "Status": "locked"' \
        '      },' \
        '      "network.trr.mode": {' \
        '        "Value": 5,' \
        '        "Status": "locked"' \
        '      }' \
        '    }' \
        '  }' \
        '}' \
        > /usr/lib/firefox/distribution/policies.json

# ---------------------------------------------------------------------------
# Desktop user matching the host UID/GID
#
# The Manjaro base image already ships a "builder" user with UID 1000.  Remove
# it so it cannot shadow the real desktop account (which usually uses UID 1000).
# ---------------------------------------------------------------------------
RUN set -eux; \
    groupadd -f wheel; \
    groupadd -f video; \
    groupadd -f render; \
    groupadd -f audio; \
    groupadd -f input; \
    groupmod -o -g "${VIDEO_GID}" video; \
    groupmod -o -g "${RENDER_GID}" render; \
    groupmod -o -g "${AUDIO_GID}" audio; \
    groupmod -o -g "${INPUT_GID}" input; \
    userdel -r builder 2>/dev/null || true; \
    groupdel builder 2>/dev/null || true; \
    groupadd -o -g "${USER_GID}" "${USERNAME}"; \
    useradd -o -m -u "${USER_UID}" -g "${USER_GID}" \
        -G wheel,video,render,audio,input -s /bin/bash "${USERNAME}"; \
    printf '%s ALL=(ALL) NOPASSWD: ALL\n' "${USERNAME}" \
        > "/etc/sudoers.d/90-${USERNAME}"; \
    chmod 440 "/etc/sudoers.d/90-${USERNAME}"

# ---------------------------------------------------------------------------
# Embedded mihomo
#
# mihomo listens on container loopback (mixed-port 7890) and sends every
# connection to the host's SOCKS5 proxy.  /etc/mihomo/config.yaml is a
# template; at start the entrypoint fills in HOST_PROXY_PORT (set in
# compose.yml) and forwards container 127.0.0.1:HOST_PROXY_PORT to the same
# port on the host.  No ports are published and the container is not attached
# to any other container's network.  COPY keeps the file modes of the build
# context, so the template is made world-readable explicitly: the entrypoint
# runs as the unprivileged container user.
# ---------------------------------------------------------------------------
COPY --from=mihomo /mihomo /usr/local/bin/mihomo
COPY mihomo/config.yaml /etc/mihomo/config.yaml
COPY mihomo/entrypoint.sh /usr/local/bin/claude-cage-entrypoint

RUN set -eux; \
    pacman -S --noconfirm --needed socat; \
    chmod 0755 /usr/local/bin/mihomo /usr/local/bin/claude-cage-entrypoint; \
    chmod 0755 /etc/mihomo; \
    chmod 0644 /etc/mihomo/config.yaml; \
    mkdir -p /var/lib/mihomo; \
    chown "${USER_UID}:${USER_GID}" /var/lib/mihomo

# Locale used by Qt/GTK applications and the system timezone.
RUN set -eux; \
    sed -i "s/^#${LANG} /${LANG} /" /etc/locale.gen; \
    grep -q "^${LANG} " /etc/locale.gen; \
    locale-gen
RUN set -eux; \
    test -f "/usr/share/zoneinfo/${TZ}"; \
    ln -snf "/usr/share/zoneinfo/${TZ}" /etc/localtime; \
    printf '%s\n' "${TZ}" > /etc/timezone; \
    printf 'LANG=%s\nLC_ALL=%s\n' "${LANG}" "${LC_ALL}" > /etc/locale.conf

# Convenience proxy variables for interactive shells.  Compose sets the same
# values as container environment variables; these make login shells that
# reset the environment keep using the embedded mihomo.
RUN printf '%s\n' \
    'export ALL_PROXY="socks5h://127.0.0.1:7890"' \
    'export all_proxy="$ALL_PROXY"' \
    'export HTTP_PROXY="$ALL_PROXY"' \
    'export HTTPS_PROXY="$ALL_PROXY"' \
    'export http_proxy="$ALL_PROXY"' \
    'export https_proxy="$ALL_PROXY"' \
    'export NO_PROXY="localhost,127.0.0.1,::1"' \
    'export no_proxy="$NO_PROXY"' \
    > /etc/profile.d/99-claude-cage-proxy.sh

WORKDIR /home/${USERNAME}

# Start the embedded proxy helpers, then the long-lived desktop-session
# command.  GUI programs are launched with docker exec by the host script.
ENTRYPOINT ["/usr/local/bin/claude-cage-entrypoint"]
CMD ["sleep", "infinity"]
