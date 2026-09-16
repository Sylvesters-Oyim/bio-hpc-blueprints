# Mutation ΔΔG (Rosetta cartesian_ddg)
More accurate but ~50× slower than FoldX – use it on a shortlist.

    ./submit.sh

Needs Rosetta in `/shared/apps/rosetta` (free academic licence, rosettacommons.org).

- `input/mutations.txt`: one mutation per line, PDB numbering, e.g. `LA42G`.

Results: `results/ddg.tsv` (Rosetta units ≈ kcal/mol, **positive = destabilising**).
