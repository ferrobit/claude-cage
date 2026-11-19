# claude-cage for Dummies

A very slow, very detailed guide for people who have never touched Linux,
Docker or WSL. Every step says **what to do**, **where to do it** and **how
to check that it worked**. Do not skip steps.

- [Linux](#part-1-linux) — about 10 steps.
- [Windows](#part-2-windows) — about 15 steps, with more hand-holding.
- [Something went wrong](#part-3-something-went-wrong).
- [Words you will see](#part-4-words-you-will-see).

---

## Before you start (both systems)

You need **all** of this:

| What | Why |
|---|---|
| A 64-bit computer with at least 8 GB of RAM (16 GB is more comfortable) | The container runs a full desktop |
| About 20 GB of free disk space | The image is several gigabytes |
| A normal internet connection | The first build downloads a lot |
| A **SOCKS5 proxy** that already works on this computer, on port `7800` | All traffic of the container goes through it, and only through it |
| One to two hours of patience for the first time | The first build is slow; later starts take seconds |

> [!IMPORTANT]
> claude-cage does **not** give you a proxy. You must already have a proxy
> program (a VPN client, Clash, v2rayN, sing-box, ssh -D …) that listens on
> port `7800`. If yours uses another port, write it down — you will need it
> in step "Use another proxy port".

**How to type commands.** A block like this:

```bash
echo hello
```

means: click into the terminal window, type (or paste) the text exactly as
shown, press **Enter**, and wait until the terminal shows its prompt again
(usually a line ending in `$`). Lines starting with `#` are comments: you may
skip them.

**Passwords in the terminal are invisible.** When a command asks for your
password, type it and press Enter even though nothing appears on screen.
That is normal.

---

## Part 1. Linux

These steps are for Ubuntu, Debian, Fedora, Arch and Manjaro. On other
distributions the idea is the same; only the install command differs.

### Step 1. Open a terminal

Press **Ctrl + Alt + T**. If nothing happens, open the application menu and
search for **Terminal** (or **Konsole** on KDE).

### Step 2. Install git and Docker

Pick **one** block that matches your system.

**Ubuntu, Debian, Fedora:**

```bash
# Ubuntu / Debian: first make sure curl and git are there
sudo apt update && sudo apt install -y curl git
# Fedora instead: sudo dnf install -y curl git

# Docker's official install script (installs Docker and Docker Compose)
curl -fsSL https://get.docker.com | sudo sh
sudo systemctl enable --now docker
```

**Arch, Manjaro:**

```bash
sudo pacman -Syu --needed git docker docker-compose
sudo systemctl enable --now docker
```

✅ **Check:**

```bash
docker --version
docker compose version
```

Both commands must print a version. `docker compose` must be **2.x** or
newer.

### Step 3. Allow yourself to use Docker without sudo

```bash
sudo usermod -aG docker "$USER"
```

Now **log out and log in again** (or simply reboot). This is required: the
change does not apply to windows that are already open.

✅ **Check:**

```bash
docker run --rm hello-world
```

You must see `Hello from Docker!`. If you see `permission denied`, you did
not log out and back in.

> [!NOTE]
> Members of the `docker` group can do anything a root user can. That is
> normal for a personal computer; do not add other people to this group.

### Step 4. Check your proxy

```bash
curl --socks5-hostname 127.0.0.1:7800 https://ifconfig.me ; echo
```

✅ You must see an IP address, and it must be the address of your proxy, not
your home address.

Now check **where** the proxy listens:

```bash
ss -ltn | grep 7800
```

| You see | Meaning |
|---|---|
| `0.0.0.0:7800` or `*:7800` or `[::]:7800` | Good: the container can reach it |
| only `127.0.0.1:7800` | **Bad**: the container cannot reach it. In your proxy program, change the listen address from `127.0.0.1` to `0.0.0.0` (often called "Allow LAN" or "listen on all interfaces"), restart it and check again |
| nothing | The proxy is not running or uses another port |

### Step 5. Download claude-cage

```bash
cd ~
git clone https://github.com/ferrobit/claude-cage.git
cd claude-cage
```

✅ **Check:** `ls` must show `claude-cage.sh`, `compose.yml` and `README.md`.

> [!TIP]
> Every later command in this part is typed **inside this folder**. If you
> open a new terminal, first type `cd ~/claude-cage`.

### Step 6. Use another proxy port (only if yours is not 7800)

Replace `1080` with your port. This saves it for every future start:

```bash
echo 'HOST_PROXY_PORT=1080' > .env
```

### Step 7. Build the image (the long part)

```bash
./claude-cage.sh build
```

This downloads and compiles a lot. It can take from 20 minutes to more than
an hour. Lots of text scrolls by — that is fine. **Do not close the
terminal.**

✅ **Check:** the last lines must not contain `ERROR` or `failed`, and you get
the prompt back. If the build fails because of the network, just run the same
command again: it continues where it stopped.

### Step 8. Start the container

```bash
./claude-cage.sh up
```

✅ **Check:**

```bash
./claude-cage.sh ps
```

The `STATUS` column must say `Up`.

### Step 9. Open Claude Desktop

```bash
./claude-cage.sh claude
```

After a few seconds a Claude window appears. Sign in as usual. It is a fresh
profile, so you must sign in once even if you use Claude on this computer
already.

Other programs work the same way:

```bash
./claude-cage.sh firefox
./claude-cage.sh chromium
./claude-cage.sh dolphin     # file manager inside the container
```

### Step 10. Make sure the traffic really goes through the proxy

```bash
./claude-cage.sh run curl -sS https://ifconfig.me ; echo
```

✅ The address must be the **same** as in step 4.

### Step 11. Exchange files with Claude

The folder `~/Claude` in your normal home is shared with the container. Put a
file there, then in Claude Desktop attach a file and pick **Claude (host)** in
the left sidebar of the file dialog. Files Claude saves there appear in your
`~/Claude` too. No other folder of your computer is visible to the container.

### Everyday use (Linux)

| I want to | Type in `~/claude-cage` |
|---|---|
| Open Claude | `./claude-cage.sh claude` |
| Stop everything | `./claude-cage.sh down` |
| Start again | `./claude-cage.sh up` |
| See what is wrong | `./claude-cage.sh logs` (exit with Ctrl + C) |
| Update claude-cage | `git pull && ./claude-cage.sh up` |

After a reboot the container starts by itself. You only need
`./claude-cage.sh claude` to open the window.

---

## Part 2. Windows

Here Linux runs inside Windows (this is called **WSL**), Docker runs on top
of it (**Docker Desktop**), and the Claude window appears on your normal
Windows desktop. It sounds complicated; it is just many small steps.

### What your Windows must have

| What | How to check |
|---|---|
| Windows 11 version 23H2 or newer, or Windows 10 version 22H2, 64-bit | Press **Win + R**, type `winver`, press Enter |
| Administrator rights | You can install programs yourself |
| Virtualization turned on | **Ctrl + Shift + Esc** → **Performance** → **CPU** → bottom right: `Virtualization: Enabled` |

If **Virtualization** says `Disabled`, it must be switched on in the BIOS/UEFI
setup of your computer (the option is called "Intel VT-x", "Intel
Virtualization Technology", "SVM" or "AMD-V"). Search the web for
"enable virtualization" plus your computer model. Without it nothing below
will work.

### Step 1. Open PowerShell as administrator

1. Click **Start**.
2. Type `powershell`.
3. On **Windows PowerShell**, click **Run as administrator**.
4. Answer **Yes** to the question "Do you want to allow this app to make
   changes".

A blue or black window opens. Its title contains "Administrator".

### Step 2. Install WSL and Ubuntu

In that window type:

```powershell
wsl --install -d Ubuntu
```

Wait until it finishes, then **restart the computer**.

### Step 3. Create your Linux user

After the restart an **Ubuntu** window opens by itself. If it does not:
**Start** → type `Ubuntu` → click it.

It asks for a **username** (small letters, no spaces, e.g. `anna`) and a
**password** twice. The password is invisible while you type — that is
normal. **Write both down**; you will need the password for `sudo`.

✅ When you see a line like `anna@PC:~$`, Ubuntu is ready.

### Step 4. Update WSL

Open PowerShell again (a normal one is fine) and type:

```powershell
wsl --update
wsl --version
```

✅ The output must contain a line starting with `WSLg version`. That is the
part that shows Linux windows on your Windows desktop.

### Step 5. Install Docker Desktop

1. Download **Docker Desktop for Windows** from
   <https://www.docker.com/products/docker-desktop/>.
2. Run the installer. On the configuration page keep **Use WSL 2 instead of
   Hyper-V** checked.
3. When it finishes, log out of Windows and log in again (or restart).
4. Start **Docker Desktop** from the Start menu. Accept the license. You can
   skip the sign-in and the survey.

### Step 6. Connect Docker Desktop to Ubuntu

In Docker Desktop click the **gear icon** (Settings) at the top:

1. **General** → if you see **Use the WSL 2 based engine**, make sure it is
   checked. (If the option is missing, it is already on.)
2. **General** → check **Start Docker Desktop when you sign in to your
   computer**. Then claude-cage is ready after every reboot.
3. **Resources** → **WSL integration** → switch on **Ubuntu**.
4. Click **Apply & restart**.

✅ **Check** — in the **Ubuntu** window (not PowerShell!) type:

```bash
docker run --rm hello-world
docker compose version
```

You must see `Hello from Docker!` and a version **2.24 or newer**.

### Step 7. Check your proxy (in Windows)

Start your proxy program on Windows. Then in **PowerShell**:

```powershell
curl.exe --socks5-hostname 127.0.0.1:7800 https://ifconfig.me
```

✅ You must see the IP address of your proxy. (Write `curl.exe`, not `curl`.)

On Windows the proxy may listen on `127.0.0.1` — Docker Desktop can reach
that. If your port is not `7800`, remember it for step 9.

### Step 8. Download claude-cage — inside Ubuntu

> [!WARNING]
> Do this in the **Ubuntu** window, **not** in PowerShell, and **not** in a
> folder on `C:\`. A copy on `C:\` breaks the scripts and is very slow.

```bash
sudo apt update && sudo apt install -y git
cd ~
git clone https://github.com/ferrobit/claude-cage.git
cd claude-cage
```

✅ **Check:** `ls` shows `claude-cage.cmd`, `claude-cage.sh` and `README.md`.

Remember your Linux username: type `whoami`. Below it is written as
`<you>`.

### Step 9. Other proxy port (only if yours is not 7800)

Still in Ubuntu, in the `claude-cage` folder (replace `1080`):

```bash
echo 'HOST_PROXY_PORT=1080' > .env
```

### Step 10. Find the launcher in Windows Explorer

1. Open **File Explorer** (Win + E).
2. Click into the address bar at the top, type exactly this (with your
   username) and press Enter:

   ```text
   \\wsl.localhost\Ubuntu\home\<you>\claude-cage
   ```

3. You see the claude-cage files. One of them is **claude-cage.cmd** (it may be
   shown as just `claude-cage` with the type "Windows Command Script").

### Step 11. Make a desktop shortcut

Right-click **claude-cage.cmd** → (on Windows 11 first **Show more options**)
→ **Send to** → **Desktop (create shortcut)**.

You can rename the shortcut to `Claude` if you like.

### Step 12. First start (the long part)

Double-click the shortcut. If Windows asks whether you really want to run the
file, click **Run**.

A black window opens and:

1. starts Docker Desktop if it is not running;
2. **builds the image — this takes from 20 minutes to more than an hour the
   first time**. Lots of text scrolls by. **Do not close the window.**
3. starts the container;
4. opens Claude Desktop.

✅ A Claude window appears on your Windows desktop. It looks like a normal
Windows program, but its icon in the taskbar is a Linux penguin. Sign in.

If the black window stops with an error, it stays open — read the last
lines and see [Part 3](#part-3-something-went-wrong).

### Step 13. Make sure the traffic really goes through the proxy

In **Ubuntu**:

```bash
cd ~/claude-cage
./claude-cage.sh run curl -sS https://ifconfig.me ; echo
```

✅ The address must be the same as in step 7.

### Step 14. Exchange files with Claude

The shared folder lives inside Ubuntu. Open it in File Explorer:

```text
\\wsl.localhost\Ubuntu\home\<you>\Claude
```

Right-click **Claude** in the left panel → **Pin to Quick access**. Now it is
always one click away. Put files there; in Claude Desktop pick **Claude
(host)** in the file dialog.

<details>
<summary>I want a normal Windows folder instead (for example <code>C:\Users\Anna\Claude</code>)</summary>

In Ubuntu (replace `Anna` with your Windows user folder name):

```bash
mkdir -p /mnt/c/Users/Anna/Claude
echo 'export CLAUDE_SHARE_DIR=/mnt/c/Users/Anna/Claude' >> ~/.bashrc
source ~/.bashrc
cd ~/claude-cage && ./claude-cage.sh up
```

This works but is slower. If Claude cannot save files there, use the folder
inside Ubuntu instead.

</details>

### Step 15. Other programs

Run these in Ubuntu inside `~/claude-cage`:

```bash
./claude-cage.sh firefox
./claude-cage.sh chromium
./claude-cage.sh dolphin
```

### Everyday use (Windows)

| I want to | Do this |
|---|---|
| Open Claude | Double-click the desktop shortcut |
| Open Firefox / Chromium | In Ubuntu: `cd ~/claude-cage && ./claude-cage.sh firefox` (or `chromium`) |
| Stop everything | In Ubuntu: `cd ~/claude-cage && ./claude-cage.sh down` |
| Update claude-cage | In Ubuntu: `cd ~/claude-cage && git pull`, then double-click the shortcut |

After a Windows restart Docker Desktop starts by itself (step 6) and brings
the container back. The shortcut also starts Docker Desktop when needed.

---

## Part 3. Something went wrong

| You see | What to do |
|---|---|
| `permission denied while trying to connect to the Docker daemon` (Linux) | You skipped "log out and log in" in step 3 of Part 1 |
| `./claude-cage.sh: Permission denied` | `chmod +x claude-cage.sh`, then try again |
| `$'\r': command not found` | The folder was copied through Windows. Delete it and clone again **inside Ubuntu** (step 8) |
| `error: claude-cage is not running` | Start it first: `./claude-cage.sh up` |
| Build stops with a download or mirror error | Run the same command again; the network was unlucky |
| `WslRegisterDistribution failed with error: 0x80370102` | Virtualization is off in the BIOS/UEFI; see "What your Windows must have" |
| `'wsl' is not recognized` | Windows is too old; install all Windows updates |
| `docker: command not found` in Ubuntu | Docker Desktop is not running, or **WSL integration → Ubuntu** is off (step 6) |
| `error: WSLg is not available` | In PowerShell: `wsl --update`, then `wsl --shutdown`, then open Ubuntu again |
| `claude-cage.sh not found in ...` (black window) | The repository is not in `~/claude-cage` inside Ubuntu; repeat step 8 |
| The window never appears (Windows) | In Ubuntu: `ls /mnt/wslg/.X11-unix` must show `X0`. If not: `wsl --update` and restart Windows |
| The window never appears (Linux) | Install `xhost` (`sudo apt install x11-xserver-utils`, on Arch `sudo pacman -S xorg-xhost`) and try again |
| Claude opens but cannot load anything | The proxy is off or unreachable: repeat the proxy check (step 4 on Linux, step 7 on Windows), then `./claude-cage.sh restart`. On Linux a firewall such as `ufw` may also block containers from reaching the port |
| Everything is slow on Windows | Normal: on Windows the container has no graphics card and draws with the CPU |

Still stuck? Run `./claude-cage.sh logs`, wait 10 seconds, press Ctrl + C and
send the last 50 lines together with what you did to the project's issue
tracker.

### Remove everything

In the terminal (Ubuntu on Windows):

```bash
cd ~/claude-cage
./claude-cage.sh down
docker image rm claude-cage
cd ~ && rm -rf ~/claude-cage
```

This also deletes `~/claude-cage/home`, which holds your sign-ins inside the
container. Your shared `~/Claude` folder is kept.

---

## Part 4. Words you will see

| Word | Meaning |
|---|---|
| Terminal | A window where you type commands instead of clicking |
| `sudo` | "Do this as administrator"; asks for your password |
| Docker | A program that runs other programs in sealed boxes |
| Image | The prepared box (built once in "build") |
| Container | A running copy of the image |
| WSL | "Windows Subsystem for Linux": real Linux inside Windows |
| WSLg | The part of WSL that shows Linux windows on the Windows desktop |
| Proxy / SOCKS5 | A middleman for internet traffic; here it is the only way out |
| Port | A number that tells which program on a computer gets the traffic, like an apartment number |
| Repository | The project folder you downloaded with `git clone` |
