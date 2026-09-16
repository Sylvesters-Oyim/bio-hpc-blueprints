# Pocket detection (fpocket)
Finds and ranks cavities on every structure in `input/`.

    ./submit.sh

Result: `results/pockets.tsv` – score, druggability (0–1, >0.5 likely druggable),
volume and centre (paste into `01_docking/settings.env`).
Pocket files for PyMOL: `results/<name>_out/`.
