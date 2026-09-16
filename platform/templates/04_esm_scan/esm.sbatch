#!/bin/bash
#SBATCH -J esm
#SBATCH -c 8
#SBATCH --mem=8G
#SBATCH -t 12:00:00
#SBATCH -o logs/%x_%A_%a.out
source /shared/apps/sbio/bin/activate
source settings.env
export OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK
python esm_scan.py "input/$FASTA" "$SLURM_ARRAY_TASK_ID" "/shared/models/esm/$MODEL.pt"
