#!/bin/bash
# Install the web portal on the head node.   sudo bash install.sh
# Runs as an unprivileged user; people log in with their cluster password and every action runs as them.
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
cd "$(dirname "$0")"

id portal >/dev/null 2>&1 || useradd --system --no-create-home --shell /usr/sbin/nologin portal
rm -rf /opt/cluster-portal && mkdir -p /opt/cluster-portal
cp -r app.py templates static /opt/cluster-portal/
cp ../course/cluster101.html ../course/pbs101.html /opt/cluster-portal/static/ 2>/dev/null || true
rm -rf /shared/template && cp -r ../templates /shared/template && chmod -R a+rX /shared/template

install -m 644 cluster-portal.service /etc/systemd/system/
systemctl daemon-reload && systemctl enable --now cluster-portal
echo "Portal on http://localhost:8080 (head node only). From a laptop: ssh -L 8080:localhost:8080 you@head-node"
