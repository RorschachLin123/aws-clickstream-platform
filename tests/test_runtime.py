import unittest
from unittest.mock import Mock, patch
from clickstream.runtime import purge_demo, start, stop
from clickstream.reconcile import query_rows


class RuntimeTest(unittest.TestCase):
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


if __name__ == '__main__':
    unittest.main()
