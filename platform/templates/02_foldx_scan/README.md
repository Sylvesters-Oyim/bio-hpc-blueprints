# Saturation mutagenesis (FoldX)
Mutates every residue to the 19 other amino acids and predicts the stability change (ΔΔG).

    ./submit.sh

Needs the FoldX binary at `/shared/apps/foldx/foldx` (free academic licence, foldxsuite.crg.eu).

Results: `results/ddg.tsv`, `results/ddg_matrix.tsv`, `results/ddg_heatmap.png`.
ΔΔG in kcal/mol: **positive = destabilising** (>1 destabilising, >2 strongly).
