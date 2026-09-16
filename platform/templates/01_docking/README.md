# Docking / virtual screening (AutoDock Vina)
Docks every ligand into one receptor pocket, spread over the cluster.

    ./submit.sh

Example: HIV protease (1HSG) with indinavir and a few other drugs.

- `input/receptor.pdb` – protein only (remove waters and ligands).
- `input/ligands.smi` – one `SMILES name` per line (or an `.sdf` file).
- Box centre: from a known ligand, or from `06_pockets/results/pockets.tsv`.

Results: `results/ranking.tsv` (best first, kcal/mol, more negative = better)
and poses in `results/poses/`.
