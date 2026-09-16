#!/bin/bash
#SBATCH -J fpocket
#SBATCH --mem=1G
#SBATCH -t 01:00:00
#SBATCH -o logs/%x_%A_%a.out
source /shared/apps/sbio/bin/activate

pdb=$(sed -n "${SLURM_ARRAY_TASK_ID}p" results/structures.txt)
cp "$pdb" results/
fpocket -f "results/$(basename "$pdb")"
rm "results/$(basename "$pdb")"
