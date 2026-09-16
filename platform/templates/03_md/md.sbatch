#!/bin/bash
#SBATCH -J md
#SBATCH --mem=12G
#SBATCH -t 7-00:00:00
#SBATCH -o logs/%x_%j.out
set -e
source /shared/apps/sbio/bin/activate
source settings.env
mdrun="gmx mdrun -ntmpi 1 -ntomp $SLURM_CPUS_PER_TASK -cpt 15"

mkdir -p md && cd md
if [ ! -f ions.gro ]; then
    for f in ../mdp/*.mdp; do
        sed -e "s/@TEMP@/$TEMPERATURE/g" -e "s/@NSTEPS@/$(awk "BEGIN{print int($LENGTH_NS * 500000)}")/" "$f" > "$(basename "$f")"
    done
    grep '^ATOM' "../input/$PDB" > clean.pdb
    gmx pdb2gmx -f clean.pdb -o protein.gro -ff "$FORCEFIELD" -water tip3p -ignh
    gmx editconf -f protein.gro -o box.gro -c -d 1.0 -bt dodecahedron
    gmx solvate -cp box.gro -cs spc216.gro -o solv.gro -p topol.top
    gmx grompp -f em.mdp -c solv.gro -p topol.top -o ions.tpr -maxwarn 1
    echo SOL | gmx genion -s ions.tpr -o ions.gro -p topol.top -pname NA -nname CL -neutral -conc 0.15
fi

[ -f em.gro ]  || { gmx grompp -f em.mdp  -c ions.gro -p topol.top -o em.tpr && $mdrun -deffnm em; }
[ -f nvt.gro ] || { gmx grompp -f nvt.mdp -c em.gro  -r em.gro  -p topol.top -o nvt.tpr && $mdrun -deffnm nvt; }
[ -f npt.gro ] || { gmx grompp -f npt.mdp -c nvt.gro -r nvt.gro -t nvt.cpt -p topol.top -o npt.tpr && $mdrun -deffnm npt; }
[ -f md.tpr ]  || gmx grompp -f md.mdp -c npt.gro -t npt.cpt -p topol.top -o md.tpr
[ -f md.gro ]  || $mdrun -deffnm md -cpi md.cpt

# analysis
echo "Protein System" | gmx trjconv -s md.tpr -f md.xtc -o md_center.xtc -pbc mol -center
echo "Backbone Backbone" | gmx rms -s md.tpr -f md_center.xtc -o rmsd.xvg -tu ns
echo "C-alpha" | gmx rmsf -s md.tpr -f md_center.xtc -o rmsf.xvg -res
echo "Protein" | gmx gyrate -s md.tpr -f md_center.xtc -o gyration.xvg
cd .. && python plot.py
