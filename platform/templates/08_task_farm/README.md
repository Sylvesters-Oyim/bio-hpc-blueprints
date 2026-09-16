# Task farm
Runs every line of `input/commands.txt` as its own job step, spread over the cluster.

    ./submit.sh

Commands run inside this folder with the science software loaded.
Failed commands are written to `results/failed.txt`.
