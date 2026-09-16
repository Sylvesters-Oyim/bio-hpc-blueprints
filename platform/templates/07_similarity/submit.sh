#!/bin/bash
set -e; cd "$(dirname "$0")"; mkdir -p logs results/parts
ls "$PWD"/input/*.pdb > results/structures.txt
n=$(wc -l < results/structures.txt)
job=$(sbatch --parsable --array=1-$n align.sbatch)
sbatch -J collect -o logs/collect_%j.out --dependency=afterany:$job \
       --wrap "/shared/apps/sbio/bin/python collect.py"
echo "Submitted $job ($n structures, $((n * (n - 1) / 2)) pairs)"
