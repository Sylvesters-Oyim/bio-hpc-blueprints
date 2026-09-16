# Molecular dynamics (GROMACS)
Protein in water with 0.15 M NaCl: setup → minimisation → equilibration → production → analysis.

    ./submit.sh

Example: ubiquitin (1UBQ), 1 ns (~25 min on a 20-thread node).

- `input/protein.pdb`: protein only, no missing residues.
- Stopped by the time limit? Run `./submit.sh` again – it continues from the checkpoint.
- Compare mutant vs wild type: copy the folder, change `input/`, submit both.

Results: `results/rmsd.png`, `results/rmsf.png`, `results/gyration.png` (+ `.tsv`),
trajectory `md/md_center.xtc` with `md/md.gro` (open both in PyMOL/VMD).
