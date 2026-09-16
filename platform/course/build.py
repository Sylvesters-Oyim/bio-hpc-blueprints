import json, sys
d = sys.argv[1] if len(sys.argv) > 1 else "."
rows = lambda f: [l.rstrip("\n").split("\t") for l in open(f"{d}/{f}")]

rank = [(r[0], float(r[1])) for r in rows("ranking.tsv")[1:]]
pockets = rows("pockets.tsv")[1:]
esm = rows("ubiquitin_matrix.tsv")
tm = rows("tm_matrix.tsv")
num = lambda f: [[float(x) for x in r[:2]] for r in rows(f)[1:]]
rmsd, rmsf = num("rmsd.tsv"), num("rmsf.tsv")
data = {
    "ranking": rank,
    "pockets": pockets,
    "esm": {"aa": esm[0][1:], "rows": [{"p": r[0], "v": [float(x) for x in r[1:]]} for r in esm[1:]]},
    "tm": {"names": tm[0][1:], "m": [[float(x) for x in r[1:]] for r in tm[1:]]},
    "rmsd": rmsd, "rmsf": rmsf,
    "mdnote": f"Real result: ubiquitin in water, {rmsd[-1][0]:g} ns on guy (19 000 atoms, 80 ns/day).",
    "pose": open(f"{d}/pose.pdb").read(),
}
html = open(f"{d}/cluster101.src.html").read()
html = html.replace("/*DATA*/", json.dumps(data, separators=(",", ":")).replace("</", "<\\/"))
html = html.replace("<script>/*3DMOL*/</script>", "<script>" + open(sys.argv[2]).read().replace("</script", "<\\/script") + "</script>")
open(f"{d}/cluster101.html", "w").write(html)
print("cluster101.html", len(html) // 1024, "kB")

# PBS course: same look, no data
pbs = open(f"{d}/pbs101.src.html").read().replace("<!--STYLE-->", html[html.index("<style>"):html.index("</style>") + 8])
open(f"{d}/pbs101.html", "w").write(pbs)
print("pbs101.html", len(pbs) // 1024, "kB")
