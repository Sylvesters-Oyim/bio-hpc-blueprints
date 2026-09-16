# usage: mutfiles.py protein.pdb mutations.txt outdir
# Rosetta numbers residues 1..N in file order, so PDB numbers are converted.
import sys
from Bio.PDB import PDBParser
from Bio.SeqUtils import seq1

pdb, mutations, outdir = sys.argv[1:4]
residues = [r for r in PDBParser(QUIET=True).get_structure("p", pdb).get_residues()]
pose = {(r.get_parent().id, r.id[1]): (i + 1, seq1(r.get_resname())) for i, r in enumerate(residues)}

for m in open(mutations).read().split():
    wt, chain, num, mut = m[0], m[1], int(m[2:-1]), m[-1]
    n, actual = pose[(chain, num)]
    assert actual == wt, f"{m}: structure has {actual} at {chain}{num}"
    open(f"{outdir}/{m}.mut", "w").write(f"total 1\n1\n{wt} {n} {mut}\n")
