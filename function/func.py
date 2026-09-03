"""OCI Notifications-triggered instance-pool scaler POC."""
import io
import json
import logging
import os
from typing import Any, Mapping

import oci
from fdk import response

LOG = logging.getLogger(__name__)
LOG.setLevel(logging.INFO)


def _json(data: io.BytesIO) -> Mapping[str, Any]:
    value: Any = json.loads(data.getvalue().decode("utf-8") if data else "{}")
    for key in ("body", "message"):
        if isinstance(value, dict) and isinstance(value.get(key), str):
            try:
                value = json.loads(value[key])
            except json.JSONDecodeError:
                pass
    if not isinstance(value, dict):
        raise ValueError("notification must be a JSON object")
    return value


def _alarm_id(payload: Mapping[str, Any]) -> str | None:
    metadata = payload.get("alarmMetaData", [])
    if isinstance(metadata, list) and metadata and isinstance(metadata[0], dict):
        return metadata[0].get("id")
    return payload.get("alarmId")


def _reply(ctx, status: int, body: Mapping[str, Any]):
    return response.Response(ctx, status_code=status, response_data=json.dumps(body), headers={"Content-Type": "application/json"})


def _scaling_action(alarm_id: str | None) -> tuple[str, str, int] | None:
    """Return the configured action for an approved alarm transition."""
    actions = (
        (
            "scale_out",
            "increment",
            os.environ.get("SCALE_OUT_ALARM_OCID"),
            os.environ.get("SCALE_OUT_STEP_SIZE", "1"),
        ),
        (
            "scale_in",
            "target",
            os.environ.get("SCALE_IN_ALARM_OCID"),
            os.environ.get("SCALE_IN_TARGET_POOL_SIZE", "0"),
        ),
    )
    for action, adjustment, approved_alarm_id, configured_size in actions:
        if alarm_id and alarm_id == approved_alarm_id:
            size = int(configured_size)
            if adjustment == "increment" and size < 1:
                raise ValueError("scale-out step size must be at least one")
            if adjustment == "target" and size < 0:
                raise ValueError("target pool size cannot be negative")
            return action, adjustment, size
    return None


def handler(ctx, data: io.BytesIO = None):
    try:
        payload = _json(data)
    except (UnicodeDecodeError, json.JSONDecodeError, ValueError) as error:
        LOG.warning("Rejecting malformed notification: %s", error)
        return _reply(ctx, 400, {"result": "rejected", "reason": "invalid_notification"})

    if payload.get("type") != "OK_TO_FIRING":
        return _reply(ctx, 200, {"result": "ignored", "reason": "not_ok_to_firing"})
    try:
        scaling_action = _scaling_action(_alarm_id(payload))
    except ValueError as error:
        LOG.error("Invalid scaling configuration: %s", error)
        return _reply(ctx, 500, {"result": "error", "reason": "invalid_target_size"})
    if scaling_action is None:
        return _reply(ctx, 200, {"result": "ignored", "reason": "unapproved_alarm"})

    pool_id = os.environ["TARGET_INSTANCE_POOL_OCID"]
    action, adjustment, configured_size = scaling_action

    signer = oci.auth.signers.get_resource_principals_signer()
    client = oci.core.ComputeManagementClient({}, signer=signer)
    pool_response = client.get_instance_pool(pool_id)
    pool = pool_response.data
    # A second alarm transition can arrive while an earlier resize is still
    # being reconciled. OCI accepts an update while the pool is SCALING, and
    # this keeps the low-CPU transition from being unnecessarily discarded.
    if pool.lifecycle_state not in {"RUNNING", "SCALING"}:
        return _reply(ctx, 409, {"result": "rejected", "reason": "pool_not_running"})
    target = pool.size + configured_size if adjustment == "increment" else configured_size
    if pool.size == target:
        return _reply(
            ctx,
            200,
            {
                "result": "no_op",
                "action": action,
                "currentSize": pool.size,
                "targetSize": target,
            },
        )

    update = client.update_instance_pool(
        pool_id,
        oci.core.models.UpdateInstancePoolDetails(size=target),
        if_match=pool_response.headers.get("etag"),
    )
    work_request_id = update.headers.get("opc-work-request-id")
    LOG.info(
        "Submitted %s (%s %s) resize to %s; work request %s",
        action,
        adjustment,
        configured_size,
        target,
        work_request_id,
    )
    return _reply(
        ctx,
        202,
        {
            "result": "submitted",
            "action": action,
            "currentSize": pool.size,
            "stepSize": configured_size if adjustment == "increment" else None,
            "targetSize": target,
            "workRequestId": work_request_id,
        },
    )
