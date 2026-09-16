#!/bin/bash
set -e; cd "$(dirname "$0")"; source settings.env; mkdir -p logs results
[ -x /shared/apps/foldx/foldx ] || { echo "FoldX missing: copy it to /shared/apps/foldx/foldx"; exit 1; }

/shared/apps/sbio/bin/python positions.py "input/$PDB" "$CHAIN" $FIRST $LAST > results/positions.txt
n=$(wc -l < results/positions.txt)

repair=$(sbatch --parsable repair.sbatch)
scan=$(sbatch --parsable --dependency=afterok:$repair --array=1-$n scan.sbatch)
sbatch -J collect -o logs/collect_%j.out --dependency=afterany:$scan \
       --wrap "/shared/apps/sbio/bin/python collect.py"
echo "Submitted repair $repair, scan $scan ($n positions)"
