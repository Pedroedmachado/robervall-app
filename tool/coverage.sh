#!/usr/bin/env bash
# Resume coverage/lcov.info: % de linhas cobertas por arquivo e no total.
f=${1:-coverage/lcov.info}
[ -f "$f" ] || { echo "sem $f"; exit 0; }
awk -F: '
/^SF:/ {file=$2; sub(/^.*lib\//,"lib/",file)}
/^LF:/ {lf[file]+=$2; tlf+=$2}
/^LH:/ {lh[file]+=$2; tlh+=$2}
END {
  for (k in lf) printf "%6.1f%%  %5d/%-5d  %s\n", (lf[k]?100*lh[k]/lf[k]:0), lh[k], lf[k], k | "sort -n"
  close("sort -n")
  printf "TOTAL  %.1f%%  (%d de %d linhas)\n", (tlf?100*tlh/tlf:0), tlh, tlf
}' "$f"
