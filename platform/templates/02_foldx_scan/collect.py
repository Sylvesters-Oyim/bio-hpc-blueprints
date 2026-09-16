import os
import pandas as pd, matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

rows = []
for pos in open("results/positions.txt").read().split():
    dif = f"results/{pos}/Dif_wt_Repair.fxout"
    if not os.path.exists(dif):
        continue
    muts = [l.strip(";\n")[-1] for l in open(f"results/{pos}/individual_list.txt")]
    header = next(i for i, l in enumerate(open(dif)) if l.startswith("Pdb\t"))
    df = pd.read_csv(dif, sep="\t", skiprows=header)
    df["mut"] = [muts[int(p.split("_")[-2]) - 1] for p in df["Pdb"]]      # wt_Repair_<mutant>_<run>.pdb
    for mut, ddg in df.groupby("mut")["total energy"]:
        rows.append({"position": pos, "wt": pos[0], "resnum": int(pos[2:]), "mutant": mut,
                     "ddG": round(ddg.mean(), 3), "sd": round(ddg.std(), 3)})

df = pd.DataFrame(rows)
df.to_csv("results/ddg.tsv", sep="\t", index=False)
matrix = df.pivot(index="position", columns="mutant", values="ddG")
matrix = matrix.loc[sorted(matrix.index, key=lambda p: int(p[2:]))]
matrix.to_csv("results/ddg_matrix.tsv", sep="\t")

plt.figure(figsize=(8, 2 + 0.15 * len(matrix)))
plt.imshow(matrix, aspect="auto", cmap="RdBu_r", vmin=-4, vmax=4)
plt.xticks(range(20), matrix.columns); plt.yticks(range(len(matrix)), matrix.index, fontsize=6)
plt.colorbar(label="ΔΔG (kcal/mol)"); plt.tight_layout()
plt.savefig("results/ddg_heatmap.png", dpi=150)
print(len(df), "mutations -> results/ddg.tsv")
