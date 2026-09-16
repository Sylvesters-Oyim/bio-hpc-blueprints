#!/bin/bash
#SBATCH -J hello
#SBATCH --ntasks-per-node=1
#SBATCH --mem=500M
#SBATCH -t 00:05:00
#SBATCH -o logs/%x_%j.out
source /shared/apps/sbio/bin/activate

srun bash -c 'printf "%s\t%s\t%s\t%s\t%s\n" $(hostname) $(nproc --all) \
  "$(free -g | awk "/Mem/{print \$2}")GB" \
  "$(command -v vina >/dev/null && echo ok || echo MISSING)" \
  "$(command -v gmx  >/dev/null && echo ok || echo MISSING)"' | sort \
  | { printf "node\tthreads\tram\tvina\tgromacs\n"; cat; } > results/nodes.tsv
column -t results/nodes.tsv
