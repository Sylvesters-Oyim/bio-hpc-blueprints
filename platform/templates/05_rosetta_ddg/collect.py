import glob, os
from statistics import mean

rows = []
for ddg in glob.glob("results/*/*.ddg"):
    wt, mut = [], []
    for line in open(ddg):                   # COMPLEX: Round1: WT_: -512.3 ...  /  MUT_42GLY: ...
        f = line.split()
        if f and f[0] == "COMPLEX:":
            (wt if f[2].startswith("WT") else mut).append(float(f[3]))
    if wt and mut:
        rows.append((os.path.basename(os.path.dirname(ddg)), mean(mut) - mean(wt)))

with open("results/ddg.tsv", "w") as out:
    out.write("mutation\tddG\n")
    for m, d in sorted(rows, key=lambda r: -r[1]):
        out.write(f"{m}\t{d:.2f}\n")
print(len(rows), "mutations -> results/ddg.tsv")
