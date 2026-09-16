#!/bin/bash
set -e; cd "$(dirname "$0")"; source settings.env; mkdir -p logs results
n=$(grep -c '>' "input/$FASTA")
sbatch --array=1-$n esm.sbatch
