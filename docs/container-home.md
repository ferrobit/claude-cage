# Container home

The home directory of the `claude-cage` container lives on the host in
`~/.config/codespace/home` and is mounted at `/home/$USER` inside the
container. `./claude-cage.sh up` creates it on the first start. It is outside
the project directory, so nothing in it can end up in git.

## What appears here

After the first `./claude-cage.sh up` and a few application launches you
will find:

| Path | Created by | Contents |
|---|---|---|
| `.config/plasma-localerc` | entrypoint, first start | KDE language and formats, taken from `LANG` and `LANGUAGE` |
| `.config/gtk-3.0/bookmarks` | entrypoint, first start | the **Codespace (host)** entry in the file dialog |
| `Codespace/` | `claude-cage.sh` | mount point of the host's `~/Codespace`; on this side it stays empty |
| `.config/Claude/` | Claude Desktop | settings, sign-in session, local data |
| `.config/mozilla/firefox/` | Firefox | browser profile: cookies, history, saved logins |
| `.config/BraveSoftware/Brave-Browser/` | Brave | browser profile: cookies, history, saved logins |
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

Stop the container first, then delete the folder; the next `up` creates it
again:

```bash
./claude-cage.sh down
rm -rf ~/.config/codespace/home
./claude-cage.sh up
```

The host's `~/Codespace` is not affected: only its empty mount point inside
the container home is removed. If `rm` reports `Permission denied` for
`Codespace`, Docker created that mount point as root (this happens when
Compose is run without the wrapper); remove it with
`sudo rmdir ~/.config/codespace/home/Codespace`.
