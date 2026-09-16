#!/bin/bash
#SBATCH -J farm
#SBATCH -o logs/%x_%A_%a.out
source /shared/apps/sbio/bin/activate
source settings.env
export OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK

cmd=$(grep . "input/$COMMANDS" | sed -n "${SLURM_ARRAY_TASK_ID}p")
echo "$cmd"
bash -c "$cmd" || echo "$cmd" >> results/failed.txt
