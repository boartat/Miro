#!/bin/zsh
# miroe W1: each case of Engine/tests/c/dep-off-exec-test.c in its own process with a 15 s limit.
# usage: w1-depexec.sh <name> <wine binary> <WINE_LAZY_EXEC> <nonx|nx>
L=/Users/Shared/MiroEngineLab O=/Users/Shared/miroe-lab/logs/w1/depexec; mkdir -p $O
name=$1 bin=$2 lazy=$3 v=$4
for c in 1 2 3 4 5 6 7 8 9; do
  log=$O/$name-$v-$c.log
  WINE_LAZY_EXEC=$lazy WINEPREFIX=$L/prefix WINEDLLOVERRIDES="winedbg.exe=d;winemenubuilder.exe=d" WINEDEBUG=-all "$bin" /Users/Shared/miroe-lab/tests/depexec-x86-$v.exe $c > $log 2>&1 &
  pid=$!; t=0
  while kill -0 $pid 2>/dev/null && (( t < 150 )); do sleep 0.1; (( t++ )); done
  if kill -0 $pid 2>/dev/null; then res=HANG; WINEPREFIX=$L/prefix "$(dirname $bin)/wineserver" -k 2>/dev/null; kill -9 $pid 2>/dev/null
  else wait $pid; rc=$?; res=$(grep -E " (ok|WRONG) \(" $log | tail -1 | awk '{print $(NF-1)}'); [[ -z "$res" ]] && res="CRASH($rc)"; fi
  printf "%s %s case %d: %s\n" $name $v $c "$res"
done
WINEPREFIX=$L/prefix "$(dirname $bin)/wineserver" -k 2>/dev/null
