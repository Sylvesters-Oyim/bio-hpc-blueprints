#!/bin/bash
set -e; cd "$(dirname "$0")"; source settings.env; mkdir -p logs results
n=$(grep -c . "input/$COMMANDS")
(( n <= 1000 )) || { echo "Max 1000 commands per submit (have $n)"; exit 1; }
sbatch --array=1-$n -c "$CPUS" --mem="$MEM" -t "$TIME" farm.sbatch
