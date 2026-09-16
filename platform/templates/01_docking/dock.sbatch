#!/bin/bash
#SBATCH -J dock
#SBATCH --mem=1G
#SBATCH -t 24:00:00
#SBATCH -o logs/%x_%A_%a.out
source /shared/apps/sbio/bin/activate
source settings.env

tmp=$(mktemp -d)
python prep_ligands.py "input/$LIGANDS" "$tmp" "$SLURM_ARRAY_TASK_ID" "$CHUNKS"

for lig in "$tmp"/*.pdbqt; do
    name=$(basename "$lig" .pdbqt)
    vina --receptor results/receptor.pdbqt --ligand "$lig" \
         --center_x "$CENTER_X" --center_y "$CENTER_Y" --center_z "$CENTER_Z" \
         --size_x "$BOX_SIZE" --size_y "$BOX_SIZE" --size_z "$BOX_SIZE" \
         --exhaustiveness "$EXHAUSTIVENESS" --cpu 1 --seed 1 \
         --out "results/poses/$name.pdbqt" > /dev/null || echo "FAILED $name"
done
rm -rf "$tmp"
