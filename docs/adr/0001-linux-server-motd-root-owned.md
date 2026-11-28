# Install server-motd root-owned on Linux servers

On a Linux Server the `/etc/update-motd.d/50-server-motd` hook runs as root at every login. If `server-motd` lived under the installing user's home (the default `uv tool install` location), root would be running a file that user can rewrite, which is a privilege escalation. So bootstrap and `update` install it with sudo into `UV_TOOL_DIR=/opt/nowhere/uv-tools` with the binary in `/usr/local/bin`, both root-owned, and the hook calls it by absolute path. The hook also exits quietly when the binary is missing, so a broken install cannot break a login.

This replaces the per-user install described in the wayfinder map (issue #1).
