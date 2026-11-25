<div align="center">

<img src="docs/logo.svg" alt="claude-cage logo" width="160" height="160">

# claude-cage

**Claude Desktop in a Manjaro KDE container whose only way to the internet is a single SOCKS5 proxy.**

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Platform: Linux](https://img.shields.io/badge/platform-Linux-informational?logo=linux&logoColor=white)](#requirements)
[![Docker Compose](https://img.shields.io/badge/Docker-Compose-2496ED?logo=docker&logoColor=white)](https://docs.docker.com/compose/)
[![Manjaro](https://img.shields.io/badge/base-Manjaro-35BF5C?logo=manjaro&logoColor=white)](https://hub.docker.com/r/manjarolinux/base)
[![KDE Plasma](https://img.shields.io/badge/desktop-KDE%20Plasma-1D99F3?logo=kde&logoColor=white)](https://kde.org/plasma-desktop/)
[![mihomo](https://img.shields.io/badge/proxy-mihomo-2BB3A3)](https://github.com/MetaCubeX/mihomo)
[![Shell: Bash](https://img.shields.io/badge/shell-Bash-4EAA25?logo=gnubash&logoColor=white)](claude-cage.sh)

[Quick start](#quick-start) •
[Usage](#usage) •
[Examples](#examples) •
[How it works](#how-it-works) •
[Proxy port](#changing-the-proxy-port) •
[Timezone & language](#timezone-language-and-geolocation) •
[Notes](#notes-and-limitations)

</div>

---

## Overview

`claude-cage` runs [Claude Desktop](https://claude.ai/download) inside a Docker
container with a full Manjaro KDE stack. Claude Desktop is installed from the
AUR package [`claude-desktop`](https://aur.archlinux.org/packages/claude-desktop).
All internet traffic leaves the container through
[mihomo](https://github.com/MetaCubeX/mihomo), which runs inside the same
container and has exactly one upstream: the host's SOCKS5 proxy on port
`HOST_PROXY_PORT` (see [Changing the proxy port](#changing-the-proxy-port)).
Any other outbound connection is dropped by a firewall.

The container's timezone and language are set explicitly instead of being
inherited from the host, and geolocation and WebRTC leaks are blocked, so
websites cannot recover the host's real position.

## Features

- 🖥️ **Full KDE desktop stack** — Dolphin, Konsole, Kate, Ark, Firefox and
  Brave, rendered on the host's X11 or Wayland display.
- 🔒 **Single egress path** — mihomo → socat → host SOCKS5; everything else is
  dropped by an `iptables` `OUTPUT` policy.
- 🌎 **Configurable location** — timezone, language and geolocation are set
  explicitly and can be matched to any proxy; see the
  [step-by-step guide](#timezone-language-and-geolocation).
- 🏠 **Isolated home** — a dedicated `~/.config/codespace/home` instead of
  your host home; only `~/Codespace` is shared as a hand-off folder.
- 👤 **Same UID/GID as the host user** — files written by the container belong
  to you.
- 🛡️ **Exit-host hardening** — optional nftables rules for the VPS that hide
  the tunnel from "two-way ping" privacy tests.

## Requirements

- Linux host with Docker Engine and the Docker Compose v2 plugin.
- An X11 or Wayland desktop session; `xhost` is used on X11.
- A SOCKS5 proxy on host port `HOST_PROXY_PORT` (see
  [Changing the proxy port](#changing-the-proxy-port)), reachable from the
  Docker bridge (for example a port published by another container). A
  service bound only to the host's `127.0.0.1` is **not** reachable through
  `host.docker.internal`.
- Several gigabytes of free disk space and direct internet access during
  `docker build`.
- Optional: `/dev/dri` for GPU acceleration.

## Quick start

```bash
git clone https://github.com/ferrobit/claude-cage.git
cd claude-cage

./claude-cage.sh build   # Manjaro KDE + AUR arc-kde-git/claude-desktop (slow the first time)
./claude-cage.sh up      # start the desktop container
./claude-cage.sh claude  # launch Claude Desktop on the host display
```

> [!IMPORTANT]
> Always run Compose through `claude-cage.sh`. The wrapper supplies the build
> arguments, runtime groups and container user that `compose.yml` expects.

## Usage

```text
./claude-cage.sh <command> [arguments...]
```

| Command | Description |
|---|---|
| `build` | Build the `claude-cage` image |
| `up` | Start the desktop container (rebuilds the image when needed) |
| `down` | Stop and remove the container |
| `restart` | Recreate the container |
| `ps` | Show container status |
| `logs` | Follow the logs |
| `claude [args...]` | Launch Claude Desktop on the host display |
| `firefox [args...]` | Launch Firefox |
| `brave [args...]` | Launch Brave |
| `dolphin [args...]` | Launch Dolphin |
| `konsole [args...]` | Launch Konsole |
| `kate [args...]` | Launch Kate |
| `shell` | Open an interactive login shell inside the container |
| `run <command...>` | Run a command inside the container (`exec` is an alias) |

GUI commands run detached and return immediately after launching the
application. Use `./claude-cage.sh logs` if an application fails to start.

## Examples

**Check that traffic leaves through the proxy:**

```bash
./claude-cage.sh run ss -ltnp
# 127.0.0.1:<HOST_PROXY_PORT>  socat
# 127.0.0.1:7890               mihomo

./claude-cage.sh run curl -sS https://ifconfig.me
# the public address of your proxy, not the host's own address
```

**Check installed package versions:**

```bash
./claude-cage.sh run pacman -Q arc-kde-git claude-desktop
```

**Hand a file to Claude Desktop:**

```bash
cp ~/Documents/report.pdf ~/Codespace/
./claude-cage.sh claude
# In Claude Desktop: attach a file → "Codespace (host)" in the sidebar → report.pdf
```

**Update Claude Desktop to the latest AUR version:**

```bash
./claude-cage.sh build --pull --no-cache
./claude-cage.sh restart
```

**Update Brave to a newer release:**

Take the version and the SHA-256 from
`brave-browser-<version>-linux-amd64.zip.sha256` on the
[release page](https://github.com/brave/brave-browser/releases), put them into
`BRAVE_VERSION` and `BRAVE_SHA256` in `compose.dockerfile`, then:

```bash
./claude-cage.sh build
./claude-cage.sh restart
```

**Open a shell for troubleshooting:**

```bash
./claude-cage.sh shell
./claude-cage.sh logs
```

## How it works

```mermaid
flowchart LR
    subgraph cage["claude-cage container"]
        apps["Claude Desktop<br/>Firefox / Brave<br/>CLI tools"] -->|"HTTP / SOCKS5<br/>127.0.0.1:7890"| mihomo["mihomo"]
        mihomo -->|"SOCKS5<br/>127.0.0.1:HOST_PROXY_PORT"| socat["socat"]
        other["Direct connections"] -.->|"dropped by iptables"| drop(("✕"))
    end
    socat -->|"TCP<br/>host.docker.internal:HOST_PROXY_PORT"| host["Host SOCKS5 proxy"]
    host --> vps["Exit server"]
    vps --> net(("Internet"))
```

### What the image contains

- `manjarolinux/base:latest` with the `plasma-meta` KDE desktop stack,
  Dolphin, Konsole, Kate, Ark and Firefox from the standard Manjaro
  repositories.
- `arc-kde-git` and `claude-desktop`, built from the AUR during
  `docker build` with `makepkg` under a throw-away `aurbuild` user. The
  `claude-desktop` PKGBUILD repackages Anthropic's official Debian build, so
  the image always follows the AUR version and no local `.deb` is needed.
- Claude Desktop under `/usr/lib/claude-desktop`, with the package launcher at
  `/usr/bin/claude-desktop`. A wrapper at `/usr/local/bin/claude-desktop`
  (earlier in `PATH`) starts the Electron binary with:
  - `--no-sandbox --no-zygote` — required because Docker blocks unprivileged
    user and PID namespaces here;
  - `--lang=<language>` — the UI language (see
    [Timezone, language and geolocation](#timezone-language-and-geolocation));
  - `--proxy-server=http://127.0.0.1:7890`;
  - `--force-webrtc-ip-handling-policy=disable_non_proxied_udp`.
- Brave under `/opt/brave`, unpacked from the official release ZIP
  (`brave-browser-<version>-linux-amd64.zip` from
  [GitHub](https://github.com/brave/brave-browser/releases)) instead of the
  Manjaro package. The archive is pinned by `BRAVE_VERSION` and `BRAVE_SHA256`
  in `compose.dockerfile` and checked with `sha256sum` during the build. A
  wrapper at `/usr/local/bin/brave` starts the browser with the same four
  groups of flags as Claude Desktop; the KDE menu entry
  (`brave-browser.desktop`) runs the wrapper too.
- A non-root user whose UID/GID match the host user, so files in the container
  home (`~/.config/codespace/home`) are owned by you on the host.
- The static `mihomo` binary copied from `metacubex/mihomo:latest`, plus
  `socat`, the configuration in `container/mihomo/config.yaml` and the
  entrypoint in `container/mihomo/entrypoint.sh`. Both helpers start with the
  container and restart automatically if they exit.

### Network model

mihomo is embedded in `claude-cage`: it is not a separate service, and the
container does not join another container's network. No ports are published,
and no extra Docker networks are used.

- `container/mihomo/config.yaml` is a template that defines exactly one proxy,
  `host-proxy`, a SOCKS5 upstream at `127.0.0.1:${HOST_PROXY_PORT}`, and the
  single rule `MATCH,host-proxy`. At start the entrypoint fills in the port and
  runs mihomo with the result.
- The entrypoint runs
  `socat TCP-LISTEN:$HOST_PROXY_PORT,bind=127.0.0.1,nodelay ... TCP:host.docker.internal:$HOST_PROXY_PORT,nodelay`,
  so container loopback port `HOST_PROXY_PORT` is the host's published SOCKS5
  service.
  `host.docker.internal` is mapped by
  `extra_hosts: host.docker.internal:host-gateway`.
- mihomo listens on the mixed HTTP/SOCKS5 port `127.0.0.1:7890` with
  `bind-address: 127.0.0.1` and `allow-lan: false`, so it is reachable only
  from the container's loopback.
- `ALL_PROXY`, `HTTP_PROXY` and `HTTPS_PROXY` (upper and lower case) point to
  `socks5h://127.0.0.1:7890`, so hostnames are resolved by the proxy and
  mihomo applies its rules.
- The entrypoint installs an `OUTPUT` firewall (the container has
  `cap_add: NET_ADMIN`). It accepts loopback traffic, established replies and
  TCP to the host gateway on port `HOST_PROXY_PORT`, and drops everything
  else. A process that ignores the proxy settings cannot fall back to the
  host's internet connection.
- Claude Desktop is started with `--proxy-server=http://127.0.0.1:7890`,
  because Electron/Chromium does not read the proxy environment variables.
  Firefox gets an enterprise policy at
  `/usr/lib/firefox/distribution/policies.json` that sends HTTP and HTTPS to
  the same listener and locks DNS over HTTPS off.
- Brave gets a managed policy at
  `/etc/brave/policies/managed/claude-cage.json`: `ProxySettings` sends all
  traffic to the same listener, `WebRtcIPHandling` keeps WebRTC from sending
  UDP past the proxy, `DnsOverHttpsMode` is `off`,
  `DefaultGeolocationSetting` denies location requests and `TorDisabled`
  removes private windows with Tor; `CommandLineFlagSecurityWarningsEnabled`
  hides the warning bar about `--no-sandbox`. Managed policies take precedence
  over command-line flags and the browser settings.

### Low-latency TCP

Small TCP packets are sent at once on every hop inside the container instead
of being held back and merged:

| Hop | Setting | Where |
|---|---|---|
| application → mihomo (`127.0.0.1:7890`) | `TCP_NODELAY`, set by mihomo (the Go runtime enables it by default) | built in |
| mihomo → socat (`127.0.0.1:HOST_PROXY_PORT`) | `TCP_NODELAY` on both ends: mihomo by default, socat by `nodelay` | `container/mihomo/entrypoint.sh` |
| socat → host SOCKS5 (`host.docker.internal:HOST_PROXY_PORT`) | `TCP_NODELAY` by `nodelay` | `container/mihomo/entrypoint.sh` |
| every TCP socket in the container | `net.ipv4.tcp_autocorking: 0` (no kernel-side merging of small writes) | `compose.yml` → `sysctls:` |

`TCP_NODELAY` turns off Nagle's algorithm, which delays a small packet until
the previous one is acknowledged. Without `nodelay`, the socat hop added about
40 ms to every request made of two small writes. The sysctl is limited to the
container's network namespace; the host keeps its own value. Everything
beyond the host's SOCKS5 port (the proxy itself and its exit server) is
outside the container and is not affected.

Check it:

```bash
./claude-cage.sh run cat /proc/sys/net/ipv4/tcp_autocorking   # 0
./claude-cage.sh run pgrep -a socat                           # ...,nodelay ...,nodelay
```

## Timezone, language and geolocation

The container never inherits the host's timezone or language: both are set
explicitly in the image and in `compose.yml`. Websites compare the timezone,
the language and any geolocation they can read with the location of the IP
address they see, so set these values to match the country of your proxy's
exit address.

> [!NOTE]
> The values that ship with the repository are listed below so you know what
> to search for. Replace them with your own; the example values used in this
> guide are `Europe/Berlin`, `de_DE.UTF-8` and `de-DE`.

### Step 1. Choose the values

| Value | Format | Example | How to find it |
|---|---|---|---|
| Timezone | IANA name | `Europe/Berlin` | `timedatectl list-timezones` on the host |
| System locale | `<lang>_<REGION>.UTF-8` | `de_DE.UTF-8` | `./claude-cage.sh run grep -i de_DE /etc/locale.gen` |
| Language list | `<lang>_<REGION>:<lang>` | `de_DE:de` | built from the locale |
| Browser language tag | `<lang>-<REGION>` | `de-DE` | built from the locale |
| Coordinates (optional) | latitude, longitude | `52.52`, `13.405` | any map service |

### Step 2. Timezone

| File | Setting | What it controls | Shipped value |
|---|---|---|---|
| `compose.dockerfile` | `ENV TZ=…` | image timezone: `/etc/localtime` and `/etc/timezone` are built from `${TZ}` | `America/Sao_Paulo` |
| `compose.yml` | `environment:` → `TZ:` | runtime `TZ` variable (takes precedence over `/etc/localtime`) | `America/Sao_Paulo` |

Keep both values identical. The build checks that
`/usr/share/zoneinfo/${TZ}` exists and stops with an error on a misspelled
name. One command replaces both values:

```bash
sed -i 's|America/Sao_Paulo|Europe/Berlin|g' compose.yml compose.dockerfile
```

### Step 3. Language and locale

Only two variables are set by hand, in two files:

| File | Setting | What it controls | Shipped value |
|---|---|---|---|
| `compose.dockerfile` | `ENV LANG` | system locale of the image | `en_US.UTF-8` |
| `compose.dockerfile` | `ENV LANGUAGE` | message translation order | `en_US:en` |
| `compose.yml` | `environment:` → `LANG` | runtime locale (`LC_ALL` is a YAML alias of it) | `en_US.UTF-8` |
| `compose.yml` | `environment:` → `LANGUAGE` | runtime translation order | `en_US:en` |

Everything else is derived from them, so do not edit it:

| Derived setting | Source | When |
|---|---|---|
| `ENV LC_ALL` | `${LANG}` | build |
| `/etc/locale.gen` entry and `locale-gen` | `${LANG}`; the build fails if `/etc/locale.gen` has no such locale | build |
| `/etc/locale.conf` | `${LANG}`, `${LC_ALL}` | build |
| Firefox policy `"RequestedLocales"` | `${LANG}` → language tag (`de_DE.UTF-8` → `de-DE`) | build |
| Claude Desktop `--lang` | `${LANG}` → language tag | every launch |
| Brave `--lang` | `${LANG}` → language tag | every launch |
| KDE `~/.config/plasma-localerc` | `${LANG}`, `${LANGUAGE}` (seeded by `container/mihomo/entrypoint.sh`) | first container start |

Keep the values in `compose.dockerfile` and `compose.yml` identical. The
replacement order matters (`en_US:en` first), so use exactly this command:

```bash
sed -i -e 's|en_US:en|de_DE:de|g' -e 's|en_US\.UTF-8|de_DE.UTF-8|g' \
    compose.yml compose.dockerfile
```

For a language other than English, also extend the `pacman -S` list in
`compose.dockerfile`:

- `firefox-i18n-<lang>` (for example `firefox-i18n-de`) — the Firefox
  language pack; without it `RequestedLocales` falls back to English;
- `noto-fonts-cjk` — required for Chinese, Japanese and Korean text.

Brave needs no extra package: its interface translations ship in the
release ZIP.

Optionally, pin the language list that Firefox sends to websites by adding
this entry to the `"Preferences"` block of the Firefox policy:

```json
"intl.accept_languages": {
  "Value": "de-DE, de",
  "Status": "locked"
}
```

### Step 4. Geolocation

By default geolocation is blocked everywhere:

- **Firefox.** The enterprise policy in `compose.dockerfile`
  (`/usr/lib/firefox/distribution/policies.json` in the image) locks these
  preferences:

  | Preference | Locked value | Effect |
  |---|---|---|
  | `geo.enabled` | `false` | no `navigator.geolocation` API |
  | `permissions.default.geo` | `2` | location requests are denied |
  | `media.peerconnection.enabled` | `false` | WebRTC is off, so no address leak |
  | `media.peerconnection.ice.proxy_only` | `true` | WebRTC may only use the proxy |
  | `browser.region.update.enabled` | `false` | no region detection by IP |
  | `browser.region.network.url` | `""` | no region detection service |
  | `network.captive-portal-service.enabled` | `false` | no probes outside the proxy |
  | `network.connectivity-service.enabled` | `false` | no probes outside the proxy |
  | `network.trr.mode` | `5` | DNS over HTTPS is off |

- **Brave.** The managed policy in `compose.dockerfile`
  (`/etc/brave/policies/managed/claude-cage.json` in the image) sets:

  | Policy | Value | Effect |
  |---|---|---|
  | `DefaultGeolocationSetting` | `2` | location requests are denied |
  | `WebRtcIPHandling` | `disable_non_proxied_udp` | WebRTC may only use the proxy |
  | `DnsOverHttpsMode` | `off` | DNS over HTTPS is off |
  | `ProxySettings` | `fixed_servers`, `http://127.0.0.1:7890` | every request goes through mihomo |
  | `TorDisabled` | `true` | no private windows with Tor |
  | `CommandLineFlagSecurityWarningsEnabled` | `false` | no warning bar about `--no-sandbox` |

  The wrapper also adds
  `--force-webrtc-ip-handling-policy=disable_non_proxied_udp`.

- **Claude Desktop.** Electron (the framework Claude Desktop is built on) has
  no location source of its own: it needs a Google API key, which is not set.
  The wrapper adds `--force-webrtc-ip-handling-policy=disable_non_proxied_udp`,
  so WebRTC cannot send UDP past the proxy.

Keeping geolocation blocked is the recommended setup. If a site needs a
location, Firefox can report **fixed coordinates** instead (Brave has no such
setting, so keep it blocked there). Replace the
`geo.enabled` and `permissions.default.geo` entries in the Firefox policy with
the block below (inside the Dockerfile's `printf` every line stays wrapped in
single quotes):

```json
"geo.enabled": { "Value": true, "Status": "locked" },
"permissions.default.geo": { "Value": 0, "Status": "locked" },
"geo.provider.use_geoclue": { "Value": false, "Status": "locked" },
"geo.provider.network.url": {
  "Value": "data:application/json,{\"location\":{\"lat\":52.52,\"lng\":13.405},\"accuracy\":1000}",
  "Status": "locked"
}
```

> [!CAUTION]
> Never enable geolocation without `geo.provider.use_geoclue: false`. The
> container shares the host's system D-Bus (`/run/dbus/system_bus_socket`),
> so Firefox could ask the host's GeoClue service for the **real** location.

### Step 5. Apply the changes

```bash
# let the entrypoint seed the new KDE locale
rm -f ~/.config/codespace/home/.config/plasma-localerc
./claude-cage.sh build
./claude-cage.sh restart
```

`seed_kde_locale` never overwrites an existing `plasma-localerc`, so delete it
first. Restart Claude Desktop, Firefox and Brave after the container is
recreated.

### Step 6. Verify

```bash
./claude-cage.sh run date                          # local time with the new UTC offset
./claude-cage.sh run cat /etc/timezone             # Europe/Berlin
./claude-cage.sh run readlink -f /etc/localtime    # /usr/share/zoneinfo/Europe/Berlin
./claude-cage.sh run locale                        # de_DE.UTF-8 everywhere
```

In Firefox:

- `about:policies` → the policy is listed as **Active**;
- `about:support` → **Internationalization & Localization** shows the new
  locale;
- in the web console (`Ctrl+Shift+K`):

  ```js
  Intl.DateTimeFormat().resolvedOptions().timeZone  // "Europe/Berlin"
  navigator.languages                               // ["de-DE", "de"]
  "geolocation" in navigator                        // false while geolocation is blocked
  ```

In Brave:

- `brave://policy` → the six policies are listed with status **OK**;
- `brave://settings/languages` → the new language is at the top (a profile
  created before the change keeps its old list; add the language there by
  hand);
- in DevTools (`Ctrl+Shift+J`):

  ```js
  Intl.DateTimeFormat().resolvedOptions().timeZone  // "Europe/Berlin"
  navigator.languages                               // starts with "de-DE"
  ```

  Brave's fingerprinting protection may shorten `navigator.languages` to the
  first language. `navigator.geolocation` exists, but every request is denied.

### Limits

- These settings cannot change your public IP address: its geolocation is
  decided by the proxy's exit server.
- Google and similar services can still infer a location from account
  history, cookies or sign-in information. The container home in
  `~/.config/codespace/home` starts fresh, but signing in carries that history
  with you; use separate accounts if that matters.

## Hiding the tunnel from the exit host

The [2ip.io](https://2ip.io/) privacy test includes a check called
**"Defining tunnel (two way ping)"**. It does not run in the browser: the test
server pings the address it sees (your proxy's public address) and treats an ICMP
echo or timestamp reply as evidence of a tunnel. It also sends OpenVPN-style
UDP probes to well-known ports and treats an ICMP "unreachable" answer as a
sign of a blocking firewall. Nothing inside `claude-cage` can affect those
probes, so the exit VPS silently drops them:

- [`container/harden/lan-harden.nft`](container/harden/lan-harden.nft) adds a separate
  nftables table (`inet lan_harden`) that drops inbound `echo-request`,
  `timestamp-request` and `address-mask-request`, plus UDP probes on ports
  `500`, `1194`, `1701`, `1723`, `4500` and `51820`. None of these ports are
  in use; the AmneziaWG endpoint uses another UDP port and stays open.
- [`container/harden/lan-harden.service`](container/harden/lan-harden.service) loads that
  table at boot. It never flushes the ruleset, so Docker's tables and the real
  services are untouched.
- [`container/harden/install-harden.sh`](container/harden/install-harden.sh) copies both
  files to the VPS over SSH and enables the service.

Install it (and re-apply after rebuilding the VPS):

```bash
KEY=~/.ssh/vps.pem ./container/harden/install-harden.sh root@<VPS-IP>
```

`KEY` defaults to `container/harden/vps.pem`; that file is ignored by git,
never commit it. Then check from the host:

```bash
ping -c 2 -W 3 <VPS-IP>                             # 100% packet loss, no reply
./claude-cage.sh run curl -sS https://ipinfo.io/ip  # still <VPS-IP> through the proxy
```

## GUI and home directory

The container has its own home directory: the host's
`~/.config/codespace/home` is mounted at `/home/$USER`. The host X11/Wayland, D-Bus, audio and GPU devices are shared
with the container. Before launching an application, the wrapper allows the
current host user through `xhost` (X11 only) and exposes the host
`XAUTHORITY` file as a single read-only mount — never the whole home
directory.

Because the home is separate, container applications start with fresh
profiles: the first time you launch Claude Desktop, Firefox or Brave, you
will need to sign in again. Copy any configuration you want into
`~/.config/codespace/home` yourself; it stays on the host after the container
is removed. What appears there and how to reset it is described in
[docs/container-home.md](docs/container-home.md).

The host's `~/Codespace` is the only exception. It is bind-mounted read-write
at the same path (`/home/$USER/Codespace`) and bookmarked as
**Codespace (host)** in the standard file dialog (the entry is seeded in
`~/.config/gtk-3.0/bookmarks`). Files placed there on the host can be opened
and saved from Claude Desktop; no other host folder is visible.

Both folders are created by `./claude-cage.sh up` (and `restart`) if they do
not exist yet, owned by your host user.

> [!TIP]
> To give Claude read-only access to the hand-off folder, change `:rw` to
> `:ro` on the `~/Codespace` mount in `compose.yml`.

## Configuration

| What | Where |
|---|---|
| Upstream SOCKS5 port (`HOST_PROXY_PORT`) | environment variable or `.env`; see [Changing the proxy port](#changing-the-proxy-port) |
| Local mixed proxy port (`7890`) | `container/mihomo/config.yaml`, `compose.yml`, `compose.dockerfile` |
| Timezone, language, geolocation | see [Timezone, language and geolocation](#timezone-language-and-geolocation) |
| Container home (`~/.config/codespace/home`) | `compose.yml` → `volumes:`, `claude-cage.sh` → `ensure_home` |
| Brave release (`BRAVE_VERSION`, `BRAVE_SHA256`) | `compose.dockerfile` |
| Shared host folder (`~/Codespace`) | `compose.yml` → `volumes:`, `claude-cage.sh` → `ensure_home`, `container/mihomo/entrypoint.sh` (file-dialog bookmark) |
| GPU device (`/dev/dri`) | `compose.yml` → `devices:` |

If the host's SOCKS5 proxy requires authentication, add the credentials to
`host-proxy` in `container/mihomo/config.yaml`. `socat` forwards raw TCP, so
no other change is needed:

```yaml
proxies:
  - name: host-proxy
    type: socks5
    server: 127.0.0.1
    port: ${HOST_PROXY_PORT}
    username: <user>
    password: <password>
    udp: false
```

> [!WARNING]
> Do not commit real proxy credentials. Keep them in a local, uncommitted copy
> of the file.

## Changing the proxy port

The host's SOCKS5 port is set in one place: the `HOST_PROXY_PORT` environment
variable. When it is not set, `compose.yml` uses the default `7800`. The
entrypoint applies the value everywhere it is needed: the socat forward, the
egress firewall rule and the generated mihomo configuration.

**For one run** — set the variable when starting the container:

```bash
HOST_PROXY_PORT=1080 ./claude-cage.sh restart
```

**Permanently** — export it in your shell profile, or put it into `.env` next
to `compose.yml` (the file is ignored by git):

```bash
echo 'HOST_PROXY_PORT=1080' > .env
./claude-cage.sh restart
```

No image rebuild is needed: the port is read when the container starts. A
value set in the shell takes precedence over `.env`.

Check it:

```bash
./claude-cage.sh run printenv HOST_PROXY_PORT        # 1080
./claude-cage.sh run grep 'port:' /var/lib/mihomo/config.yaml
./claude-cage.sh run curl -sS https://ifconfig.me    # the proxy's public address
```

> [!NOTE]
> To change the default itself, edit the single line
> `HOST_PROXY_PORT: ${HOST_PROXY_PORT:-7800}` in `compose.yml`.

## Notes and limitations

- **Long first build.** The first build downloads a large KDE stack, compiles
  `arc-kde-git` and builds `claude-desktop` from the AUR. Expect a
  multi-gigabyte image. The Dockerfile pins a small set of Manjaro mirrors,
  because the mirror list in the base image can be stale relative to the other
  mirrors (pacman then requests package versions that no mirror still has).
- **Build needs direct internet.** Building `claude-desktop` downloads
  Anthropic's official `.deb` from `downloads.claude.ai` and verifies it
  against the PKGBUILD checksum; the Brave release ZIP comes from `github.com`
  and is checked against `BRAVE_SHA256`. The container proxy does not exist
  yet at that point.
- **Persistent home.** `~/.config/codespace/home` persists across
  `down`/`up`. It lives outside the project directory, so it never ends up in
  git.
- **Shared session bus.** Single-instance applications (Dolphin, Kate, …)
  share the host D-Bus session, so launching one from the container may focus
  an already-running host instance instead of opening a second one.
- **Not a sandbox for hostile code.** The container user has passwordless
  `sudo`; this is a convenience setup.
- **Brave runs without its own sandbox.** Brave starts with `--no-sandbox`,
  because Docker blocks the user namespaces its sandbox needs. The policy
  `CommandLineFlagSecurityWarningsEnabled: false` only hides the warning bar
  about this flag; the browser is still unsandboxed inside the container.
- **Wayland.** `XDG_RUNTIME_DIR`, `/tmp/.X11-unix` and the host Xauthority file
  are used for GUI access. On a pure Wayland session the `WAYLAND_DISPLAY`
  socket is shared through `XDG_RUNTIME_DIR`: Electron, Firefox and Brave use
  Wayland, while Qt/KDE applications use XWayland (`QT_QPA_PLATFORM=xcb`).
- **Device groups.** The `group_add` GIDs in `compose.yml` default to common
  values. The wrapper overrides them with the host's actual `video`, `render`,
  `audio` and `input` groups, and the image is built with matching GIDs, so
  `docker exec -u` can still open `/dev/dri` and audio devices.
- **No GPU.** On a host without `/dev/dri`, remove the `devices:` entry from
  the `claude-cage` service in `compose.yml`; rendering falls back to
  software.

## Project layout

```text
claude-cage/
├── claude-cage.sh           # host-side wrapper (lifecycle, GUI and shell commands)
├── compose.yml              # claude-cage desktop container
├── compose.dockerfile       # Manjaro KDE + AUR arc-kde-git/claude-desktop
├── .dockerignore            # build context: Dockerfile + container/mihomo/ only
├── docs/
│   ├── container-home.md    # contents of the container home, how to reset it
│   ├── logo.svg             # project logo (vector)
│   ├── logo.png             # project logo, 512 px raster
│   ├── social-preview.svg   # GitHub social preview source (needs the Inter font)
│   └── social-preview.png   # 1280 × 640 image for Settings → Social preview
└── container/
    ├── mihomo/
    │   ├── config.yaml      # embedded mihomo configuration template
    │   └── entrypoint.sh    # proxy helpers, egress firewall, desktop seeding
    └── harden/              # optional exit-VPS hardening (nftables + systemd)
        ├── install-harden.sh
        ├── lan-harden.nft
        └── lan-harden.service
```

## License

Distributed under the [MIT License](LICENSE).

## Disclaimer

This is an unofficial community project and is not affiliated with or
endorsed by Anthropic. "Claude" is a trademark of Anthropic. Claude Desktop is
downloaded from Anthropic's servers during the build and is subject to
Anthropic's own terms.
