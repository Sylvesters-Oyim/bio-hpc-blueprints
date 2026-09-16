#!/bin/bash
# Copy the packed software to the head node and unpack it into /shared (seen by every node).
#   bash install.sh admin@10.0.0.1
set -euo pipefail
HEAD="${1:?usage: bash install.sh admin@head-node-ip}"
cd "$(dirname "$0")/out"

scp sbio.tar.gz esm/*.pt "$HEAD:/tmp/"
ssh -t "$HEAD" 'sudo bash -c "
  set -e
  mkdir -p /shared/apps/sbio /shared/models/esm
  tar -xzf /tmp/sbio.tar.gz -C /shared/apps/sbio
  /shared/apps/sbio/bin/python /shared/apps/sbio/bin/conda-unpack   # fix paths for the new location
  mv /tmp/esm2_t33_650M_UR50D*.pt /shared/models/esm/
  chmod -R a+rX /shared/apps /shared/models
  rm /tmp/sbio.tar.gz
  echo export PATH=\\\$PATH:/shared/apps/sbio/bin > /etc/profile.d/sbio.sh   # tools on everyone PATH
"'
echo "Installed. Also copy /etc/profile.d/sbio.sh to each compute node for terminal users."
