# Container home

This folder is the home directory of the `claude-cage` container: it is
mounted at `/home/$USER` inside it. Only this README is tracked by git;
everything else here is ignored (see `.gitignore`).

## What appears here

After the first `./claude-cage.sh up` and a few application launches you
will find:

| Path | Created by | Contents |
|---|---|---|
| `.config/plasma-localerc` | entrypoint, first start | KDE language and formats, taken from `LANG` and `LANGUAGE` |
| `.Xauthority` | `claude-cage.sh`, every GUI launch | copy of the host X11 cookie (mode 600) |
| `.config/gtk-3.0/bookmarks` | entrypoint, first start | the **Claude (host)** entry in the file dialog |
| `Claude/` | Docker | mount point of the host's `~/Claude` (or `CLAUDE_SHARE_DIR`); on this side it stays empty |
| `.config/Claude/` | Claude Desktop | settings, sign-in session, local data |
| `.config/mozilla/firefox/` | Firefox | browser profile: cookies, history, saved logins |
| `.config/chromium/` | Chromium | browser profile: cookies, history, saved logins |
| `.config/`, `.local/share/` | KDE applications | settings and data of Dolphin, Konsole, Kate, KWallet, … |
| `.cache/` | all applications | caches; safe to delete, can grow large |
| `.bash_history` | `./claude-cage.sh shell` | shell history |

## After the container stops

`./claude-cage.sh down` removes the container, not this folder: everything
listed above stays here and is reused on the next `up`. Files are owned by
your host user, because the container runs with your UID/GID.

> [!WARNING]
> This folder holds sign-in sessions and cookies. Do not share it, copy it to
> other machines or commit it.

## Reset to a clean state

Stop the container first, then delete everything except this README:

```bash
./claude-cage.sh down
find home -mindepth 1 -maxdepth 1 ! -name README.md -exec rm -rf {} +
```

If `rm` reports `Permission denied` for `home/Claude`, Docker created that
mount point as root; remove it with `sudo rmdir home/Claude`.
