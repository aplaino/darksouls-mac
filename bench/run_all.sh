#!/bin/zsh
# Three rounds of every configuration, interleaved so drift (heat, background
# load) spreads evenly; results in /tmp/ds1bench/results.
cd ${0:a:h}
mkdir -p /tmp/ds1bench/results
caffeinate -d -i -u -w $$ &
for r in ${=ROUNDS:-1 2 3}; do
  for m in ${=MODES:-port crossover port-enhanced crossover-dxvk}; do
    python3 -I bench.py $m /tmp/ds1bench/results/$m-$r.json
    cp /tmp/ds1bench/$m.log /tmp/ds1bench/results/$m-$r.log
    mv -f /tmp/ds1bench/$m.png /tmp/ds1bench/results/$m-$r.png 2>/dev/null
    sleep 10
  done
done
