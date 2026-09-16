#!/bin/bash
#SBATCH -J relax
#SBATCH --mem=4G
#SBATCH -t 12:00:00
#SBATCH -o logs/%x_%j.out
source settings.env
bin=$(ls /shared/apps/rosetta/main/source/bin/relax.*linuxgccrelease | head -1)

cd results
$bin -s "../input/$PDB" -nstruct 1 -overwrite \
     -score:weights ref2015_cart -relax:cartesian -relax:min_type lbfgs_armijo_nonmonotone \
     -relax:constrain_relax_to_start_coords -relax:ramp_constraints false
mv "$(basename "$PDB" .pdb)_0001.pdb" relaxed.pdb
