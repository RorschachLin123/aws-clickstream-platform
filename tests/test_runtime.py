import unittest
from unittest.mock import Mock, patch
from clickstream.runtime import purge_demo, start, stop, wait_status
from clickstream.reconcile import query_rows
from clickstream.runtime import verify_deadline
from datetime import datetime, timezone
import json


class RuntimeTest(unittest.TestCase):
    def test_cloud_deadline_is_required_to_be_enabled_and_near_future(self):
        client = Mock()
        schedule = dict(State='ENABLED', ScheduleExpression='at(2026-10-20T03:10:00)',
            ScheduleExpressionTimezone='UTC', FlexibleTimeWindow={'Mode': 'OFF'},
            Target={'Arn': 'arn:aws:scheduler:::aws-sdk:kinesisanalyticsv2:stopApplication',
                    'Input': json.dumps({'ApplicationName': 'clickstream-dev-pipeline', 'Force': True})})
        client.get_schedule.return_value = schedule
        now = datetime(2026, 10, 20, 3, 0, tzinfo=timezone.utc)
        verify_deadline(client, 'clickstream-dev-pipeline', now=now)
        for mutation in [dict(State='DISABLED'), dict(ScheduleExpression='at(2026-10-20T02:50:00)'),
                         dict(ScheduleExpression='at(2026-10-20T04:00:00)'),
                         dict(Target={'Arn': schedule['Target']['Arn'], 'Input': json.dumps({'ApplicationName': 'other', 'Force': True})})]:
            client.get_schedule.return_value = {**schedule, **mutation}
            with self.assertRaises(RuntimeError):
                verify_deadline(client, 'clickstream-dev-pipeline', now=now)

    def test_failed_start_returns_immediately_instead_of_waiting_full_timeout(self):
        client = Mock()
        client.describe_application.side_effect = [
            {'ApplicationDetail': {'ApplicationStatus': status}} for status in ['STARTING', 'READY']
        ]
        with self.assertRaisesRegex(RuntimeError, 'returned to READY'):
            wait_status(client, 'app', 'RUNNING', sleep=lambda _: None)

    def test_start_only_from_ready(self):
        client = Mock()
        client.describe_application.return_value = {'ApplicationDetail': {'ApplicationStatus': 'STARTING'}}
        with self.assertRaises(RuntimeError):
            start(client, 'app')
        client.start_application.assert_not_called()

    def test_stop_ready_is_noop(self):
        client = Mock()
        client.describe_application.return_value = {'ApplicationDetail': {'ApplicationStatus': 'READY'}}
        stop(client, 'app')
        client.stop_application.assert_not_called()

    def test_cleanup_refuses_wrong_bucket_and_running_job(self):
        aws = Mock(region_name='us-west-2')
        aws.client.return_value.get_caller_identity.return_value = {'Account': '123456789012'}
        bucket = 'clickstream-dev-lake-123456789012-us-west-2'
        with self.assertRaises(ValueError):
            purge_demo(aws, 'clickstream-dev-pipeline', 'clickstream_dev', 'other', 'other')
        aws.client.return_value.describe_application.return_value = {'ApplicationDetail': {'ApplicationStatus': 'RUNNING'}}
        with self.assertRaises(RuntimeError):
            purge_demo(aws, 'clickstream-dev-pipeline', 'clickstream_dev', bucket, bucket)
        aws.client.return_value.delete_table.assert_not_called()
        aws.client.return_value.delete_objects.assert_not_called()

    def test_athena_timeout_cancels_query(self):
        client = Mock()
        client.start_query_execution.return_value = {'QueryExecutionId': 'query-1'}
        client.get_query_execution.return_value = {'QueryExecution': {'Status': {'State': 'RUNNING'}}}
        with patch('clickstream.reconcile.time.monotonic', side_effect=[0, 100]):
            with self.assertRaises(TimeoutError):
                query_rows(client, 'wg', 'clickstream_dev', 'events', 'run', timeout=1)
        client.stop_query_execution.assert_called_once_with(QueryExecutionId='query-1')

    def test_cleanup_refuses_versioned_lake_before_any_deletion(self):
        aws = Mock(region_name='us-west-2')
        clients = {name: Mock() for name in ['sts', 'kinesisanalyticsv2', 's3', 'glue']}
        aws.client.side_effect = lambda name: clients[name]
        clients['sts'].get_caller_identity.return_value = {'Account': '123456789012'}
        clients['kinesisanalyticsv2'].describe_application.return_value = {'ApplicationDetail': {'ApplicationStatus': 'READY'}}
        clients['s3'].get_bucket_versioning.return_value = {'Status': 'Enabled'}
        bucket = 'clickstream-dev-lake-123456789012-us-west-2'
        with self.assertRaises(RuntimeError):
            purge_demo(aws, 'clickstream-dev-pipeline', 'clickstream_dev', bucket, bucket)
        clients['glue'].delete_table.assert_not_called()
        clients['s3'].delete_objects.assert_not_called()


if __name__ == '__main__':
    unittest.main()
