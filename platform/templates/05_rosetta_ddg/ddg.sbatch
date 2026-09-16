#!/bin/bash
#SBATCH -J ddg
#SBATCH --mem=3G
#SBATCH -t 12:00:00
#SBATCH -o logs/%x_%A_%a.out
source settings.env
bin=$(ls /shared/apps/rosetta/main/source/bin/cartesian_ddg.*linuxgccrelease | head -1)

mutfile=$(ls "$PWD"/results/mutfiles/*.mut | sed -n "${SLURM_ARRAY_TASK_ID}p")
work=results/$(basename "$mutfile" .mut)
mkdir -p "$work" && cd "$work"
$bin -s ../relaxed.pdb -ddg:mut_file "$mutfile" -ddg:iterations "$ITERATIONS" \
     -ddg::cartesian -ddg::dump_pdbs false -bbnbrs 1 -fa_max_dis 9.0 \
     -score:weights ref2015_cart -relax:cartesian -relax:min_type lbfgs_armijo_nonmonotone > rosetta.log
