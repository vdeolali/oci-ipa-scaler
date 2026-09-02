#!/usr/bin/env bash
set -euo pipefail
# Run on the workload-generator VM, not on the target pool.
sudo stress-ng --cpu "$(nproc)" --cpu-method matrixprod --timeout 10m --metrics-brief
