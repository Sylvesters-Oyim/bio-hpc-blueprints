# usage: prep_ligands.py ligands.smi|sdf outdir chunk nchunks
import sys
from rdkit import Chem
from rdkit.Chem import AllChem
from meeko import MoleculePreparation

src, outdir, chunk, nchunks = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])

if src.endswith(".sdf"):
    mols = Chem.SDMolSupplier(src, removeHs=False)
else:
    mols = Chem.SmilesMolSupplier(src, titleLine=False)

prep = MoleculePreparation()
for i, mol in enumerate(mols):
    if i % nchunks != chunk or mol is None:
        continue
    name = mol.GetProp("_Name") if mol.HasProp("_Name") else f"lig{i}"
    try:
        mol = Chem.AddHs(mol, addCoords=True)
        if mol.GetNumConformers() == 0 or not mol.GetConformer().Is3D():
            AllChem.EmbedMolecule(mol, randomSeed=1)
            AllChem.MMFFOptimizeMolecule(mol)
        setups = prep.prepare(mol)
        if isinstance(setups, list):                      # meeko >= 0.6
            from meeko import PDBQTWriterLegacy
            pdbqt = PDBQTWriterLegacy.write_string(setups[0])[0]
        else:                                             # meeko 0.5
            pdbqt = prep.write_pdbqt_string()
        open(f"{outdir}/{name}.pdbqt", "w").write(pdbqt)
    except Exception as e:
        print(f"skip {name}: {e}")
