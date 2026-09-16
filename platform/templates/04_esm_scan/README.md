# Variant effect scan (ESM protein language model)
Scores every possible single mutation from sequence alone (no structure needed).
Score = log P(mutant) − log P(wild type); **negative = likely harmful**.

    ./submit.sh

Example: ubiquitin (76 aa, ~2 min).

- `input/sequences.fasta`: one or more sequences (max 1022 aa each).

Results per sequence: `results/<name>.tsv`, `results/<name>_matrix.tsv`, `results/<name>.png`.
