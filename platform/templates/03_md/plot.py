import numpy as np, matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

plots = {"rmsd": ("Time (ns)", "Backbone RMSD (nm)"),
         "rmsf": ("Residue", "RMSF (nm)"),
         "gyration": ("Time (ps)", "Radius of gyration (nm)")}
for name, (xlabel, ylabel) in plots.items():
    data = np.loadtxt(f"md/{name}.xvg", comments=("#", "@"))[:, :2]
    np.savetxt(f"results/{name}.tsv", data, delimiter="\t", header=f"{xlabel}\t{ylabel}", comments="")
    plt.figure(figsize=(6, 3))
    plt.plot(data[:, 0], data[:, 1], lw=1)
    plt.xlabel(xlabel); plt.ylabel(ylabel); plt.tight_layout()
    plt.savefig(f"results/{name}.png", dpi=150); plt.close()
print("plots in results/")
