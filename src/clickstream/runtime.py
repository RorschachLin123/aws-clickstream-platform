"""Bounded application lifecycle and explicitly confirmed demo-data cleanup."""
import time


def wait_status(client, application: str, desired: str, timeout: int = 900, *, sleep=time.sleep):
    deadline = time.monotonic() + timeout
    previous = None
    while True:
        detail = client.describe_application(ApplicationName=application)["ApplicationDetail"]
        status = detail["ApplicationStatus"]
        if status != previous:
            print(f"{application}: {status}", flush=True)
            previous = status
        if status == desired:
            return detail
        if time.monotonic() >= deadline:
            raise TimeoutError(f"{application} did not reach {desired}; current state {status}. Inspect logs and stop it.")
        sleep(5)


def start(client, application: str):
    status = client.describe_application(ApplicationName=application)["ApplicationDetail"]["ApplicationStatus"]
    if status != "READY":
        raise RuntimeError(f"Expected READY before starting, got {status}")
    client.start_application(ApplicationName=application, RunConfiguration={"ApplicationRestoreConfiguration": {"ApplicationRestoreType": "SKIP_RESTORE_FROM_SNAPSHOT"}})
    return wait_status(client, application, "RUNNING")


def stop(client, application: str):
    status = client.describe_application(ApplicationName=application)["ApplicationDetail"]["ApplicationStatus"]
    if status == "READY":
        return
    if status != "RUNNING":
        raise RuntimeError(f"Application is {status}; resolve transition before stopping or use the documented operator recovery procedure")
    client.stop_application(ApplicationName=application)
    wait_status(client, application, "READY")


def purge_demo(session, application: str, database: str, bucket: str, confirmed_bucket: str):
    account = session.client("sts").get_caller_identity()["Account"]
    expected = f"clickstream-dev-lake-{account}-{session.region_name}"
    if bucket != expected or confirmed_bucket != bucket or database != "clickstream_dev" or application != "clickstream-dev-pipeline":
        raise ValueError("Cleanup is limited to the explicitly confirmed clickstream-dev demo bucket, app and database")
    client = session.client("kinesisanalyticsv2")
    if client.describe_application(ApplicationName=application)["ApplicationDetail"]["ApplicationStatus"] != "READY":
        raise RuntimeError("Stop Flink and verify READY before deleting Iceberg data")
    s3 = session.client("s3")
    versioning = s3.get_bucket_versioning(Bucket=bucket)
    if versioning.get("Status") in ("Enabled", "Suspended"):
        raise RuntimeError("Refusing versioned bucket purge; this demo expects a nonversioned lake")
    glue = session.client("glue")
    try:
        glue.delete_table(DatabaseName=database, Name="events")
    except glue.exceptions.EntityNotFoundException:
        pass
    removed = 0
    for page in s3.get_paginator("list_objects_v2").paginate(Bucket=bucket):
        objects = [{"Key": obj["Key"]} for obj in page.get("Contents", [])]
        if objects:
            result = s3.delete_objects(Bucket=bucket, Delete={"Objects": objects, "Quiet": True})
            if result.get("Errors"):
                raise RuntimeError(f"S3 object cleanup failed: {result['Errors']}")
            removed += len(objects)
    print(f"Deleted {removed} demo objects; now generate/review the Terraform destroy plan")
