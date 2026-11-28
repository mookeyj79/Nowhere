# A user role for computers that are neither DevBox nor Server

Family desktops and laptops (Windows 11 Pro and Linux Mint) fit neither existing role: `server` shows the server MOTD, and `devbox` adds the dev layer. So a third role, `user`, loads the core layer only, shows no MOTD and installs no server-only uv tools.

- **Name:** `user`, the homelab's own term for these machines ("user computers").
- **`EDITOR`:** `nano`, as on a server. Nowhere does not install VS Code on this role, so `code --wait` could fail. The local override can change it per machine.
- **Bare `update` on Windows:** every step except WSL. Windows Update, winget, Tools and disk cleanup all apply to a desktop. A family computer has no WSL distro to update, so WSL is opt-in through `-WSL`. On Linux, `update` is the same on every role.
- **Fallback:** a missing or unknown role still behaves as `server`. Bootstrap always writes the role, so the fallback matters only for a broken stub. On a server, falling back to `user` would lose the MOTD and the server's update steps.

Linux Mint is not added to the supported list until bootstrap and the zsh harness pass on it (see the real-machine checklist). When they do, add it to the supported list in the README and in `shared/tools.json` (`$comment`).

This settles issue #35.
