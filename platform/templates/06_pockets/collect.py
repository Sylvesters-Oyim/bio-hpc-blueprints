import glob, os, re

rows = []
for info in sorted(glob.glob("results/*_out/*_info.txt")):
    name = os.path.basename(info)[:-9]
    for block in re.split(r"\nPocket ", "\n" + open(info).read())[1:]:
        num = block.split()[0]
        val = dict(l.split(":", 1) for l in block.splitlines()[1:] if ":" in l)
        val = {k.strip(): v.strip() for k, v in val.items()}
        pqr = f"results/{name}_out/pockets/pocket{num}_vert.pqr"
        xyz = [[float(l[i:i + 8]) for i in (30, 38, 46)] for l in open(pqr) if l.startswith("ATOM")]
        c = [round(sum(p[i] for p in xyz) / len(xyz), 2) for i in range(3)]
        rows.append([name, num, val["Score"], val["Druggability Score"], val["Volume"], *c])

with open("results/pockets.tsv", "w") as f:
    f.write("structure\tpocket\tscore\tdruggability\tvolume\tcenter_x\tcenter_y\tcenter_z\n")
    for r in rows:
        f.write("\t".join(map(str, r)) + "\n")
print(len(rows), "pockets -> results/pockets.tsv")
