# OCI IPA Scaler POC

This package implements an isolated sandbox POC:

`workload VM (stress-ng) -> OCI Monitoring alarm -> Notifications topic -> OCI Function -> UpdateInstancePool`

The test pool starts at `0`. When the approved CPU alarm transitions from `OK` to `FIRING`, the Function sets it to the configured POC target (`5` by default). It does not touch the customer pool or scheduled autoscaling policy.

## Package contents

- `function/`: OCI Function source and container definition.
- `terraform/`: Resource Manager Terraform configuration.
- `scripts/run-stress.sh`: workload-generator test command.

## POC validation

1. Apply the stack in `sanjpill_sandbox`, K8s compartment, `us-phoenix-1`.
2. Run `scripts/run-stress.sh` on the separate workload-generator VM.
3. Verify alarm firing, Function log entry, Compute work request, and target-pool size `0 -> 5`.

For production, IPA must invoke the Function when its desired pool size changes, passing the approved pool key and desired size. The CPU alarm is POC-only.
