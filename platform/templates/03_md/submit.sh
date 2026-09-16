#!/bin/bash
set -e; cd "$(dirname "$0")"; source settings.env; mkdir -p logs results
# MD is fastest on one node, so pick one and use all its CPUs
[ -n "$NODE" ] || NODE=$(sinfo -h -N -t idle,mixed -o "%c %N" | sort -rn | head -1 | cut -d" " -f2)
cpus=$(sinfo -h -N -n "$NODE" -o %c | head -1)
sbatch -w "$NODE" -c "$cpus" md.sbatch
