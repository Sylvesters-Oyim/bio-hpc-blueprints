#!/bin/bash
set -e; cd "$(dirname "$0")"; source settings.env; mkdir -p logs results/mutfiles
ls /shared/apps/rosetta/main/source/bin/cartesian_ddg.* >/dev/null 2>&1 \
    || { echo "Rosetta missing: install it in /shared/apps/rosetta"; exit 1; }

/shared/apps/sbio/bin/python mutfiles.py "input/$PDB" "input/$MUTATIONS" results/mutfiles
n=$(ls results/mutfiles | wc -l)

relax=$(sbatch --parsable relax.sbatch)
ddg=$(sbatch --parsable --dependency=afterok:$relax --array=1-$n ddg.sbatch)
sbatch -J collect -o logs/collect_%j.out --dependency=afterany:$ddg \
       --wrap "/shared/apps/sbio/bin/python collect.py"
echo "Submitted relax $relax, ddg $ddg ($n mutations)"
