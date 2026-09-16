# usage: positions.py protein.pdb CHAIN [first last]  ->  KA42 per line
import sys
from Bio.PDB import PDBParser
from Bio.SeqUtils import seq1

chain = PDBParser(QUIET=True).get_structure("p", sys.argv[1])[0][sys.argv[2]]
first, last = (int(sys.argv[3]), int(sys.argv[4])) if len(sys.argv) > 4 else (-10**9, 10**9)
for res in chain:
    het, num, icode = res.id
    if het == " " and icode == " " and first <= num <= last and seq1(res.get_resname()) != "X":
        print(f"{seq1(res.get_resname())}{sys.argv[2]}{num}")
