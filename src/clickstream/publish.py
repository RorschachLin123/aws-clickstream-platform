"""Publish baseline data. Ambiguous transport failures abort instead of blindly replaying."""
import json
import time


def publish(client, stream_name: str, events: list[dict], *, sleep=time.sleep, attempts: int = 6) -> int:
    sent = 0
    for offset in range(0, len(events), 100):
        pending = [{"Data": json.dumps(e, sort_keys=True, separators=(",", ":")).encode(), "PartitionKey": e["impression_id"]} for e in events[offset:offset + 100]]
        for attempt in range(attempts):
            # SDK transport retries must be disabled by the caller: uncertain acknowledgement can duplicate data.
            response = client.put_records(StreamName=stream_name, Records=pending)
            outcomes = response["Records"]
            if len(outcomes) != len(pending):
                raise RuntimeError("Kinesis returned an unexpected result count")
            failed = []
            for record, result in zip(pending, outcomes):
                error = result.get("ErrorCode")
                if error in ("ProvisionedThroughputExceededException", "InternalFailure"):
                    failed.append(record)
                elif error:
                    raise RuntimeError(f"Kinesis rejected a record: {error}")
                elif "SequenceNumber" not in result:
                    raise RuntimeError("Kinesis returned neither success nor a retriable failure")
                else:
                    sent += 1
            pending = failed
            if not pending:
                break
            sleep(min(2 ** attempt / 10, 2))
        if pending:
            raise RuntimeError(f"Kinesis retries exhausted: {len(pending)} unacknowledged records; do not replay the run blindly")
    return sent
