# usage: esm_scan.py sequences.fasta N model.pt   (N = 1 for first sequence)
import os, sys
import esm, torch, pandas as pd, matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

fasta, n, model_path = sys.argv[1], int(sys.argv[2]), sys.argv[3]
name, seq = [(r.split()[0], "".join(r.split("\n", 1)[1].split()))
             for r in open(fasta).read().split(">")[1:]][n - 1]
AA = "ACDEFGHIKLMNPQRSTVWY"

weights = torch.load(model_path, map_location="cpu", weights_only=False)
model, alphabet = esm.pretrained.load_model_and_alphabet_core(os.path.basename(model_path)[:-3], weights)
model.eval()
tokens = alphabet.get_batch_converter()([(name, seq)])[2]
aa_idx = [alphabet.get_idx(a) for a in AA]

# mask each position in turn, read the model's amino acid probabilities there
scores = []
with torch.no_grad():
    for i in range(len(seq)):
        masked = tokens.clone()
        masked[0, i + 1] = alphabet.mask_idx
        logp = model(masked)["logits"][0, i + 1].log_softmax(-1)[aa_idx]
        scores.append((logp - logp[AA.index(seq[i])]).tolist())

matrix = pd.DataFrame(scores, columns=list(AA), index=[f"{a}{i + 1}" for i, a in enumerate(seq)])
matrix.round(3).to_csv(f"results/{name}_matrix.tsv", sep="\t")
long = matrix.stack().reset_index()
long.columns = ["position", "mutant", "score"]
long = long[long.position.str[0] != long.mutant]
long.insert(0, "mutation", long.position + long.mutant)
long.round(3).sort_values("score").to_csv(f"results/{name}.tsv", sep="\t", index=False)

plt.figure(figsize=(max(6, len(seq) * 0.12), 4))
plt.imshow(matrix.T, aspect="auto", cmap="RdBu", vmin=-10, vmax=4)
plt.yticks(range(20), AA); plt.xlabel("Position"); plt.colorbar(label="ESM score")
plt.title(name); plt.tight_layout(); plt.savefig(f"results/{name}.png", dpi=150)
print(f"{name}: {len(seq)} positions -> results/{name}.tsv")
