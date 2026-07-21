# BioLab Platform — Architecture & Operations Manual

**Version:** 1.0 → 1.1 (execution-complete; reproducibility hardening in progress)
**Intended home:** `biolab-cookbook/manual/BioLab_Platform_Manual.md`
**Companion to:** `BioLab_Cluster_Manual.md` (the hardware/OS/Slurm/Ansible layer)
**Purpose:** Record how the software platform on top of the cluster is designed, why it's designed that way, and the rule that decides when platform work is allowed to resume after the freeze.

> **Read the cluster manual first.** That one gets you from bare metal to a working Slurm + Apptainer + NFS cluster. This one covers everything above it: containers, workflows, modules, provenance, and the decision to stop building infrastructure and start doing science.

---

## 0. The one mental model that governs everything here

**An execution platform runs jobs. A research platform proves them.** These are different goals, and the whole v1.0 → v1.1 story is the move from the first to the second.

| | Execution platform (v1.0) | Research platform (v1.1) |
|---|---|---|
| Question it answers | "Can I run this?" | "What exactly did I run, and can I reproduce it in two years?" |
| Made of | Slurm, Apptainer, Nextflow, shared config, modules | + automatic provenance, versioned reference data, committed container recipes |
| Maturity measured by | what executes | what it can **prove** |

For pharmacogenomics specifically, "provable" is the point. A docking result is only science if you can say which structure, which variant set, which tool version, and which database release produced it — because CYP variant annotations change between database releases. A result you can't defend isn't a result.

### The four principles carried up from the cluster manual

1. **Own the science, rent the plumbing.** Nextflow orchestrates; we don't write orchestrators.
2. **Centralize, don't standardize.** You can't standardize your way out of duplication — you remove the need for copies. One source of truth per concern.
3. **Trust the verified thing over the plausible thing.** A checkmark means "verified by a real run," never "decided" or "written in a config."
4. **Build infrastructure only when it benefits every future pipeline.** Everything else is a research project, built pipeline-by-pipeline from real biological need.

---

## 1. The architecture (v1.0 — execution-complete)

### The layers, each a single source of truth

```
/srv/biolab/shared/
├── containers/     ← software        (Apptainer .sif + committed .def recipes)
├── modules/        ← workflow LOGIC   (one reusable DSL2 process per tool)
├── workflows/      ← compositions     (pipelines that IMPORT modules)
│   └── nextflow.global.config  ← execution POLICY (Slurm, Apptainer, resource labels)
└── reference/      ← scientific DATA  (versioned by release — added in v1.1)
```

**Why this shape.** Every kind of thing that can drift has exactly one home, so a fix has exactly one place to happen:

- **Execution policy** (how jobs hit Slurm, where Apptainer caches, what a resource label means) lives once in `nextflow.global.config`. Every workflow inherits it. Change the Slurm resource policy in one file; the whole library obeys.
- **Tool logic** lives once per tool in `modules/`. A workflow does `include { IQTREE } from '../modules/iqtree.nf'` instead of copying the process. Fix IQ-TREE once; every pipeline that imports it inherits the fix.
- **Compositions** in `workflows/` are thin — they wire modules together and declare inputs/outputs, nothing more.

### Why modules, not a scaffold generator

This was a real fork in the road. A scaffold generator (`new_workflow.sh`, cookiecutter, template repo — all the same tool) fixes only **structural** drift: uniform folder layout and boilerplate. It does nothing for **logic** drift, because it fills each new skeleton with *copied* process code — so every workflow is still a fork that diverges over time.

The insight: **the unit of reuse must be the tool, not the workflow.** Modules make the tool the shared thing; workflows just compose them. That kills logic drift at the source. A generator, if ever built, comes last and only scaffolds a pipeline that *imports* modules — by then there's almost nothing left to scaffold, because the substance lives in modules + config.

Counter-intuitive but load-bearing: **more files, fewer places to edit, is simpler than fewer files, edit everywhere.** Complexity isn't file count; it's the number of places you must change when one thing changes. Eight self-contained workflows look simpler and are the more complex system.

### v1.0 status (verified)

Eight workflows run end-to-end under Slurm + Apptainer, results publish correctly, and module reuse is verified — `sequence_to_tree` and `blast_to_tree` import the **same** MAFFT and IQ-TREE modules, so a single fix propagates to both. Tools with modules: BLAST, MAFFT, IQ-TREE, MMseqs2, HMMER, AutoDock Vina.

---

## 2. v1.1 — Reproducibility hardening (the last infrastructure debt)

Three capabilities that are **cross-cutting** — they must hold across every pipeline, so they must be built into the architecture *before* pipelines multiply, not bolted onto each one. This is a short phase (1–2 sessions). It defines **rules**, it does not download databases.

> **Rules and data decay at different rates.** A convention (`reference/<db>/<release>/`) is permanent and cheap. A database dump is perishable and expensive — stale within a quarter. So they don't share a release. v1.1 locks the durable rules; v1.2 fills the shelves only when a real project pulls a specific dataset.

### Task 1 — Automatic provenance (config-level, inherited library-wide)

**Why:** Provenance is a cross-cutting concern exactly like shared config and modules. It must not be added per-workflow (it'd be captured inconsistently and results wouldn't compare). It goes once into `nextflow.global.config` and every run inherits it.

**What:** Enable `trace`, `report`, `timeline`, `dag` by default; capture container digests; record the **reference-database release** used (the pharmacogenomics-specific field that plain Nextflow won't capture for you); publish these per-run so they travel with the output.

**Verify:** Run a workflow, then open its trace/report and read the tool version and container hash back out of a completed run. Provenance earns its checkmark only when you can read a version out of a trace file — not when the config block exists.

### Task 2 — Reference-data convention (empty structure + docs, no downloads)

**Why:** The architecture has one source of truth for compute (config) and logic (modules) but not yet for *data*. A pharmacogenomics platform's validity rests on which genome build, variant DB, and structure a run used — and two pipelines must agree on those or their results can't be compared.

**What:** Create `/srv/biolab/shared/reference/<db>/<release>/` with a README stating the rule (every dataset lives under a versioned release folder; provenance must record which release a run used). Create the top-level folders empty: `blast/ pdb/ clinvar/ pharmvar/ gnomad/ alphafold/`. Download nothing.

**Verify:** `tree /srv/biolab/shared/reference` shows the versioned convention; the README explains the release rule.

### Task 3 — Container recipe policy

**Why:** An `.sif` you can't rebuild from a versioned definition is a reproducibility hole. (This gap already appeared once — images that existed with no committed Dockerfile/def.) The rule is architectural policy, cheap now, painful to retrofit across a grown library.

**What:** Rule — no `.sif` in the library without a version-controlled `.def` beside it. Audit `/srv/biolab/shared/containers`, list any `.sif` lacking a `.def`, and locate or reconstruct the recipe for each. Don't rebuild images needlessly; just ensure a committed recipe exists.

**Verify:** A command listing every `.sif` confirms a matching `.def` for each; output shows zero missing recipes (or an explicit gap list to close).

---

## 3. Architecture Freeze

After v1.1 verifies, **the platform is frozen.**

### The freeze rule (write this down; it protects thesis time from engineering enthusiasm)

> Platform work resumes **only** when a genuine *cross-cutting* concern appears — something that must hold across every pipeline. Everything else is a research project, built pipeline-by-pipeline from a real biological use case.

**Why this rule is load-bearing.** "Just one more platform feature" will always feel reasonable in the moment. Without a written rule, platform-polishing becomes a permanent, comfortable procrastination surface that quietly displaces the science the platform exists for. The freeze converts "should I build this?" from a mood into a test: *is it cross-cutting, or is it a pipeline?* If it's a pipeline, you don't touch the platform — you build the pipeline.

**Building vs. closing are different acts.** Building is open-ended and seductive. Closing is a deliberate decision that the thing is good enough to stand on and that further effort belongs one layer up. v1.1 is the last honest infrastructure debt. Pay it, freeze, and go do pharmacogenomics.

### What lives above the freeze (research projects, built per use case)

Protein preparation, ligand preparation, docking, molecular dynamics, homology modeling, CYP450 / African-variant analysis. Each arrives as: one new **module** per new tool (Foldseek, GROMACS, AlphaFold, OpenBabel…) plus a thin **composition** that imports it — never a new fork to maintain. Each inherits config, provenance, and the reference-data convention automatically.

---

## 4. How to add things after the freeze (quick reference)

**A new tool** → write one module in `/srv/biolab/shared/modules/<tool>.nf` with a resource `label` (not a hardcoded resource block). Commit its `.def` beside its `.sif` in `containers/`. Done — it's now reusable everywhere.

**A new pipeline** → a thin workflow in `workflows/` that `include`s the modules it needs and loads `nextflow.global.config`. No process logic copied in.

**A new reference dataset** → drop it under `reference/<db>/<release>/`, and ensure the pipeline's provenance records that release. (This is v1.2 territory — pulled by a real project, not pre-staged.)

**A GPU node** (from the cluster manual) → driver on the box, `Gres=gpu:N` on its inventory line, `gres.conf` on that node, uncomment `GresTypes=gpu`. No rebuild of existing nodes.

---

## Appendix — Version history

- **v1.0 — Execution-complete.** Cluster up (see cluster manual); Slurm + Apptainer + Nextflow; shared config + DSL2 module library; 8 workflows verified with module reuse.
- **v1.1 — Reproducibility hardening (in progress).** Automatic provenance; reference-data convention (empty + documented); container-recipe policy. Rules, not downloads.
- **Freeze.** After v1.1 verifies. Platform reopens only for genuine cross-cutting concerns; all else is research, pipeline-by-pipeline.
- **v1.2+ — Research assets.** Reference datasets populated on demand, driven by actual projects.
