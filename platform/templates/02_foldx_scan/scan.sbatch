#!/bin/bash
#SBATCH -J scan
#SBATCH --mem=1G
#SBATCH -t 12:00:00
#SBATCH -o logs/%x_%A_%a.out
source settings.env

pos=$(sed -n "${SLURM_ARRAY_TASK_ID}p" results/positions.txt)      # e.g. KA42
mkdir -p "results/$pos" && cd "results/$pos"
cp ../wt_Repair.pdb .
for aa in A C D E F G H I K L M N P Q R S T V W Y; do
    [ "$aa" != "${pos:0:1}" ] && echo "$pos$aa;"
done > individual_list.txt

/shared/apps/foldx/foldx --command=BuildModel --pdb=wt_Repair.pdb \
    --mutant-file=individual_list.txt --numberOfRuns="$RUNS" --out-pdb=false > foldx.log
rm -f wt_Repair.pdb
