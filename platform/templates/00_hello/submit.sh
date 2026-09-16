#!/bin/bash
set -e; cd "$(dirname "$0")"; source settings.env; mkdir -p logs results
sbatch -N "$NODES" hello.sbatch
