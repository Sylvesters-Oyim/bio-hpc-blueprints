import glob, os
import numpy as np, matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

name = lambda p: os.path.basename(p.split(":")[0])[:-4]
names = [name(l.strip()) for l in open("results/structures.txt")]
tm = np.eye(len(names))

with open("results/pairs.tsv", "w") as out:
    out.write("structure1\tstructure2\tTM1\tTM2\tRMSD\taligned\n")
    for part in glob.glob("results/parts/*.tsv"):
        for line in open(part):
            f = line.split("\t")
            a, b = names.index(name(f[0])), names.index(name(f[1]))
            tm[a, b] = tm[b, a] = max(float(f[2]), float(f[3]))
            out.write(f"{names[a]}\t{names[b]}\t{f[2]}\t{f[3]}\t{f[4]}\t{f[10].strip()}\n")

with open("results/tm_matrix.tsv", "w") as out:
    out.write("structure\t" + "\t".join(names) + "\n")
    for n, row in zip(names, tm):
        out.write(n + "\t" + "\t".join(f"{v:.3f}" for v in row) + "\n")
plt.figure(figsize=(1 + 0.4 * len(names), 0.8 + 0.4 * len(names)))
plt.imshow(tm, vmin=0, vmax=1, cmap="viridis")
plt.xticks(range(len(names)), names, rotation=90); plt.yticks(range(len(names)), names)
plt.colorbar(label="TM-score"); plt.tight_layout()
plt.savefig("results/tm_heatmap.png", dpi=150)
print("results/pairs.tsv, results/tm_matrix.tsv, results/tm_heatmap.png")
