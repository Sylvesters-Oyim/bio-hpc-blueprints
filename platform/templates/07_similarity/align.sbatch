#!/bin/bash
#SBATCH -J usalign
#SBATCH --mem=1G
#SBATCH -t 12:00:00
#SBATCH -o logs/%x_%A_%a.out
source /shared/apps/sbio/bin/activate

# structure i vs every structure after it
i=$SLURM_ARRAY_TASK_ID
query=$(sed -n "${i}p" results/structures.txt)
for target in $(tail -n +$((i + 1)) results/structures.txt); do
    USalign "$query" "$target" -outfmt 2 | grep -v '^#'
done > results/parts/$i.tsv
