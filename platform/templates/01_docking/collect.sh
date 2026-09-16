#!/bin/bash
cd "$(dirname "$0")"
{ printf 'ligand\tscore_kcal_mol\n'
  for f in results/poses/*.pdbqt; do
      printf '%s\t%s\n' "$(basename "$f" .pdbqt)" "$(awk '/VINA RESULT/{print $4; exit}' "$f")"
  done | sort -t$'\t' -k2,2g
} > results/ranking.tsv
head -11 results/ranking.tsv | column -t
