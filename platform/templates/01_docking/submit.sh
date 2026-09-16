#!/bin/bash
set -e; cd "$(dirname "$0")"; source settings.env; mkdir -p logs results/poses
source /shared/apps/sbio/bin/activate

obabel "input/$RECEPTOR" -xr -O results/receptor.pdbqt 2>/dev/null
if [[ $LIGANDS == *.sdf ]]; then n=$(grep -c '^\$\$\$\$' "input/$LIGANDS"); else n=$(grep -c . "input/$LIGANDS"); fi
chunks=$(( n < 1000 ? n : 1000 ))

job=$(sbatch --parsable --array=0-$((chunks - 1)) --export=ALL,CHUNKS=$chunks dock.sbatch)
sbatch -J collect -o logs/collect_%j.out --dependency=afterany:$job --wrap "bash collect.sh"
echo "Submitted $job: $n ligands in $chunks tasks"
