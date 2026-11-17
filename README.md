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
`12005`. Any other outbound connection is dropped by a firewall.

The container's timezone and language are set explicitly instead of being
inherited from the host, and geolocation and WebRTC leaks are blocked, so
websites cannot recover the host's real position.

## Features

- 🖥️ **Full KDE desktop stack** — Dolphin, Konsole, Kate, Ark and Firefox,
  rendered on the host's X11 or Wayland display.
- 🔒 **Single egress path** — mihomo → socat → host SOCKS5; everything else is
  dropped by an `iptables` `OUTPUT` policy.
- 🌎 **Configurable location** — timezone, language and geolocation are set
  explicitly and can be matched to any proxy; see the
  [step-by-step guide](#timezone-language-and-geolocation).
- 🏠 **Isolated home** — a dedicated `./home` instead of your host home;
  only `~/Claude` is shared as a hand-off folder.
- 👤 **Same UID/GID as the host user** — files written by the container belong
  to you.
- 🛡️ **Exit-host hardening** — optional nftables rules for the VPS that hide
  the tunnel from "two-way ping" privacy tests.

## Requirements

- Linux host with Docker Engine and the Docker Compose v2 plugin.
- An X11 or Wayland desktop session; `xhost` is used on X11.
- A SOCKS5 proxy on host port `12005`, reachable from the Docker bridge
  (for example a port published by another container). A service bound only
  to the host's `127.0.0.1` is **not** reachable through
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
# 127.0.0.1:12005  socat
# 127.0.0.1:7890   mihomo

./claude-cage.sh run curl -sS https://ifconfig.me
# the public address of your proxy, not the host's own address
```

**Check installed package versions:**

```bash
./claude-cage.sh run pacman -Q arc-kde-git claude-desktop
```

**Hand a file to Claude Desktop:**

```bash
cp ~/Documents/report.pdf ~/Claude/
./claude-cage.sh claude
# In Claude Desktop: attach a file → "Claude (host)" in the sidebar → report.pdf
```

**Update Claude Desktop to the latest AUR version:**

```bash
./claude-cage.sh build --pull --no-cache
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
        apps["Claude Desktop<br/>Firefox<br/>CLI tools"] -->|"HTTP / SOCKS5<br/>127.0.0.1:7890"| mihomo["mihomo"]
        mihomo -->|"SOCKS5<br/>127.0.0.1:12005"| socat["socat"]
        other["Direct connections"] -.->|"dropped by iptables"| drop(("✕"))
    end
    socat -->|"TCP<br/>host.docker.internal:12005"| host["Host SOCKS5 proxy"]
    host --> vps["Exit server"]
    vps --> net(("Internet"))
```

### What the image contains

- `manjarolinux/base:latest` with the `plasma-meta` KDE desktop stack,
  Dolphin, Konsole, Kate, Ark and Firefox.
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
- A non-root user whose UID/GID match the host user, so files in `./home` are
  owned by you on the host.
- The static `mihomo` binary copied from `metacubex/mihomo:latest`, plus
  `socat`, the configuration in `mihomo/config.yaml` and the entrypoint in
  `mihomo/entrypoint.sh`. Both helpers start with the container and restart
  automatically if they exit.

### Network model

mihomo is embedded in `claude-cage`: it is not a separate service, and the
container does not join another container's network. No ports are published,
and no extra Docker networks are used.

- `mihomo/config.yaml` defines exactly one proxy, `host-proxy`, a SOCKS5
  upstream at `127.0.0.1:12005`, and the single rule `MATCH,host-proxy`.
- The entrypoint runs
  `socat TCP-LISTEN:12005,bind=127.0.0.1 ... TCP:host.docker.internal:12005`,
  so container loopback port `12005` is the host's published SOCKS5 service.
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
  TCP to the host gateway on port `12005`, and drops everything else. A
  process that ignores the proxy settings cannot fall back to the host's
  internet connection.
- Claude Desktop is started with `--proxy-server=http://127.0.0.1:7890`,
  because Electron/Chromium does not read the proxy environment variables.
  Firefox gets an enterprise policy at
  `/usr/lib/firefox/distribution/policies.json` that sends HTTP and HTTPS to
  the same listener and locks DNS over HTTPS off.

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
| KDE `~/.config/plasma-localerc` | `${LANG}`, `${LANGUAGE}` (seeded by `mihomo/entrypoint.sh`) | first container start |

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

- **Claude Desktop.** Electron (the framework Claude Desktop is built on) has
  no location source of its own: it needs a Google API key, which is not set.
  The wrapper adds `--force-webrtc-ip-handling-policy=disable_non_proxied_udp`,
  so WebRTC cannot send UDP past the proxy.

Keeping geolocation blocked is the recommended setup. If a site needs a
location, Firefox can report **fixed coordinates** instead. Replace the
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
rm -f home/.config/plasma-localerc   # let the entrypoint seed the new KDE locale
./claude-cage.sh build
./claude-cage.sh restart
```

`seed_kde_locale` never overwrites an existing `plasma-localerc`, so delete it
first. Restart Claude Desktop and Firefox after the container is recreated.

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

### Limits

- These settings cannot change your public IP address: its geolocation is
  decided by the proxy's exit server.
- Google and similar services can still infer a location from account
  history, cookies or sign-in information. The container home in `./home`
  starts fresh, but signing in carries that history with you; use separate
  accounts if that matters.

## Hiding the tunnel from the exit host

The [2ip.io](https://2ip.io/) privacy test includes a check called
**"Defining tunnel (two way ping)"**. It does not run in the browser: the test
server pings the address it sees (your proxy's public address) and treats an ICMP
echo or timestamp reply as evidence of a tunnel. It also sends OpenVPN-style
UDP probes to well-known ports and treats an ICMP "unreachable" answer as a
sign of a blocking firewall. Nothing inside `claude-cage` can affect those
probes, so the exit VPS silently drops them:

- [`tools/vps/lan-harden.nft`](tools/vps/lan-harden.nft) adds a separate
  nftables table (`inet lan_harden`) that drops inbound `echo-request`,
  `timestamp-request` and `address-mask-request`, plus UDP probes on ports
  `500`, `1194`, `1701`, `1723`, `4500` and `51820`. None of these ports are
  in use; the AmneziaWG endpoint uses another UDP port and stays open.
- [`tools/vps/lan-harden.service`](tools/vps/lan-harden.service) loads that
  table at boot. It never flushes the ruleset, so Docker's tables and the real
  services are untouched.
- [`tools/vps/install-harden.sh`](tools/vps/install-harden.sh) copies both
  files to the VPS over SSH and enables the service.

Install it (and re-apply after rebuilding the VPS):

```bash
KEY=~/.ssh/vps.pem ./tools/vps/install-harden.sh root@<VPS-IP>
```

`KEY` defaults to `tools/vps/vps.pem`; that file is ignored by git, never
commit it. Then check from the host:

```bash
ping -c 2 -W 3 <VPS-IP>                             # 100% packet loss, no reply
./claude-cage.sh run curl -sS https://ipinfo.io/ip  # still <VPS-IP> through the proxy
```

## GUI and home directory

The container has its own home directory: `./home` is mounted at
`/home/$USER`. The host X11/Wayland, D-Bus, audio and GPU devices are shared
with the container. Before launching an application, the wrapper allows the
current host user through `xhost` (X11 only) and exposes the host
`XAUTHORITY` file as a single read-only mount — never the whole home
directory.

Because the home is separate, container applications start with fresh
profiles: the first time you launch Claude Desktop or Firefox, you will need
to sign in again. Copy any configuration you want into `./home` yourself; it
stays on the host after the container is removed.

The host's `~/Claude` is the only exception. It is bind-mounted read-write at
the same path (`/home/$USER/Claude`) and bookmarked as **Claude (host)** in the
standard file dialog (the entry is seeded in `~/.config/gtk-3.0/bookmarks`).
Files placed there on the host can be opened and saved from Claude Desktop; no
other host folder is visible.

> [!TIP]
> To give Claude read-only access to the hand-off folder, change `:rw` to
> `:ro` on the `~/Claude` mount in `compose.yml`.

## Configuration

| What | Where |
|---|---|
| Upstream SOCKS5 port (`12005`) | `mihomo/config.yaml`, `mihomo/entrypoint.sh` |
| Local mixed proxy port (`7890`) | `mihomo/config.yaml`, `compose.yml`, `compose.dockerfile` |
| Timezone, language, geolocation | see [Timezone, language and geolocation](#timezone-language-and-geolocation) |
| Shared host folder (`~/Claude`) | `compose.yml` |
| GPU device (`/dev/dri`) | `compose.yml` → `devices:` |

If the host's SOCKS5 proxy requires authentication, add the credentials to
`host-proxy` in `mihomo/config.yaml`. `socat` forwards raw TCP, so no other
change is needed:

```yaml
proxies:
  - name: host-proxy
    type: socks5
    server: 127.0.0.1
    port: 12005
    username: <user>
    password: <password>
    udp: false
```

> [!WARNING]
> Do not commit real proxy credentials. Keep them in a local, uncommitted copy
> of the file.

## Notes and limitations

- **Long first build.** The first build downloads a large KDE stack, compiles
  `arc-kde-git` and builds `claude-desktop` from the AUR. Expect a
  multi-gigabyte image. The Dockerfile pins a small set of Manjaro mirrors,
  because the mirror list in the base image can be stale relative to the other
  mirrors (pacman then requests package versions that no mirror still has).
- **Build needs direct internet.** Building `claude-desktop` downloads
  Anthropic's official `.deb` from `downloads.claude.ai` and verifies it
  against the PKGBUILD checksum. The container proxy does not exist yet at that
  point.
- **Persistent home.** `./home` persists across `down`/`up`, and its contents
  are ignored by git.
- **Shared session bus.** Single-instance applications (Dolphin, Kate, …)
  share the host D-Bus session, so launching one from the container may focus
  an already-running host instance instead of opening a second one.
- **Not a sandbox for hostile code.** The container user has passwordless
  `sudo`; this is a convenience setup.
- **Wayland.** `XDG_RUNTIME_DIR`, `/tmp/.X11-unix` and the host Xauthority file
  are used for GUI access. On a pure Wayland session the `WAYLAND_DISPLAY`
  socket is shared through `XDG_RUNTIME_DIR`: Electron and Firefox use Wayland,
  while Qt/KDE applications use XWayland (`QT_QPA_PLATFORM=xcb`).
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
├── .dockerignore            # build context: Dockerfile + mihomo/ only
├── docs/
│   ├── logo.svg             # project logo (vector)
│   ├── logo.png             # project logo, 512 px raster
│   ├── social-preview.svg   # GitHub social preview source (needs the Inter font)
│   └── social-preview.png   # 1280 × 640 image for Settings → Social preview
├── home/                    # dedicated container home (not the host home)
├── mihomo/
│   ├── config.yaml          # embedded mihomo configuration
│   └── entrypoint.sh        # proxy helpers, egress firewall, desktop seeding
└── tools/vps/               # optional exit-VPS hardening (nftables + systemd)
```

## License

Distributed under the [MIT License](LICENSE).

## Disclaimer

This is an unofficial community project and is not affiliated with or
endorsed by Anthropic. "Claude" is a trademark of Anthropic. Claude Desktop is
downloaded from Anthropic's servers during the build and is subject to
Anthropic's own terms.
