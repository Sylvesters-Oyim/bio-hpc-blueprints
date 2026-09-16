#!/bin/bash
#SBATCH -J repair
#SBATCH --mem=2G
#SBATCH -t 04:00:00
#SBATCH -o logs/%x_%j.out
source settings.env
cp "input/$PDB" results/wt.pdb
cd results && /shared/apps/foldx/foldx --command=RepairPDB --pdb=wt.pdb
