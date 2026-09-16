#!/bin/bash
# Build the science software on a PC WITH internet, pack it into one file for the offline cluster.
# Output in ./out: sbio.tar.gz (software) and esm/ (protein language model weights).
set -euo pipefail
cd "$(dirname "$0")" && mkdir -p out && cd out
export MAMBA_ROOT_PREFIX=$PWD/mamba
export CONDA_OVERRIDE_CUDA=""    # CPU builds only: the cluster has no GPUs

PKGS="python=3.11 numpy scipy pandas matplotlib biopython mdanalysis
      openbabel rdkit meeko autodock-vina gromacs fpocket usalign pdbfixer openmm
      pytorch=*=cpu* flask waitress paramiko"

retry() { for i in 1 2 3 4 5; do "$@" && return; sleep 20; done; return 1; }   # flaky Wi-Fi

# micromamba: a small conda that needs no install
[ -x bin/micromamba ] || curl -Ls https://micro.mamba.pm/api/micromamba/linux-64/latest | tar -xj bin/micromamba

rm -rf sbio
retry ./bin/micromamba create -y -p ./sbio -c conda-forge -c bioconda --override-channels --strict-channel-priority $PKGS
retry ./sbio/bin/pip install --no-deps fair-esm

# conda-pack turns the environment into a tarball that works in another folder on another machine
[ -x packer/bin/conda-pack ] || retry ./bin/micromamba create -y -p ./packer -c conda-forge --override-channels conda-pack
rm -f sbio.tar.gz && ./packer/bin/conda-pack -p ./sbio -o sbio.tar.gz

# ESM-2 weights (the cluster can't download them itself)
retry env TORCH_HOME=$PWD/torch ./sbio/bin/python -c "import esm; esm.pretrained.esm2_t33_650M_UR50D()"
mkdir -p esm && cp torch/hub/checkpoints/esm2_t33_650M_UR50D*.pt esm/

ls -lh sbio.tar.gz esm/
