#!/bin/bash
# One-time setup of the D-248 queue on the PC (idempotent): the pueued user service and the
# two groups. pueue itself is a static release binary in ~/.local/bin (v4.0.4, checksums from
# the GitHub release). Does not touch ~/actions-runner or any existing job.
set -eu
P=$HOME/.local/bin/pueue
mkdir -p "$HOME/.config/systemd/user" "$HOME/.config/pueue"
# One fixed socket: the daemon (systemd, XDG_RUNTIME_DIR set) and a non-interactive ssh client
# (XDG_RUNTIME_DIR unset) would otherwise look in different places.
cat > "$HOME/.config/pueue/pueue.yml" <<CONF
shared:
  unix_socket_path: $HOME/.local/share/pueue/pueue.socket
CONF
cat > "$HOME/.config/systemd/user/pueued.service" <<UNIT
[Unit]
Description=pueue daemon (Potts PC queue, D-248)

[Service]
ExecStart=$HOME/.local/bin/pueued -v
Restart=on-failure

[Install]
WantedBy=default.target
UNIT
systemctl --user daemon-reload
systemctl --user enable pueued.service
systemctl --user restart pueued.service
sleep 1
for g in suites ab; do "$P" group add "$g" 2>/dev/null || true; "$P" parallel 1 --group "$g"; done
"$P" group
