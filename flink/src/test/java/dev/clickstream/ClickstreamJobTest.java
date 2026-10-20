package dev.clickstream;

import static org.junit.jupiter.api.Assertions.*;
import org.junit.jupiter.api.Test;
import org.apache.flink.types.Row;
import java.nio.file.Path;
import java.util.List;
import java.util.HashSet;
import java.util.Set;
import org.junit.jupiter.api.io.TempDir;
import org.apache.flink.streaming.api.environment.StreamExecutionEnvironment;
import org.apache.iceberg.Table;
import org.apache.iceberg.PartitionSpec;
import org.apache.iceberg.data.IcebergGenerics;
import org.apache.iceberg.data.Record;
import org.apache.iceberg.io.CloseableIterable;
import org.apache.iceberg.flink.FlinkSchemaUtil;
import org.apache.iceberg.flink.TableLoader;
import org.apache.iceberg.hadoop.HadoopTables;

class ClickstreamJobTest {
    @Test void initializesAwsCatalogDependenciesWithoutNetwork() {
        org.apache.iceberg.aws.AwsClientFactory factory = org.apache.iceberg.aws.AwsClientFactories.from(
            java.util.Map.of("client.region", "us-west-2"));
        try (software.amazon.awssdk.services.glue.GlueClient glue = factory.glue();
             software.amazon.awssdk.services.s3.S3Client s3 = factory.s3()) {
            assertNotNull(glue);
            assertNotNull(s3);
        }
    }

    private static final String EVENT = "{\"event_id\":\"97f57c18-d5a6-5f83-9034-8ac66c68d305\",\"run_id\":\"run-1\",\"impression_id\":\"97f57c18-d5a6-5f83-9034-8ac66c68d305\",\"user_id\":\"user-1\",\"app_id\":\"app-1\",\"campaign_id\":\"campaign-1\",\"event_type\":\"payment\",\"event_time\":\"2026-01-01T00:00:00.000Z\",\"amount_cents\":199}";

    @Test void preservesBusinessKeyAndMoney() throws Exception {
        Row row = ClickstreamJob.parse(EVENT);
        assertEquals(9, row.getArity());
        assertEquals("97f57c18-d5a6-5f83-9034-8ac66c68d305", row.getField(0));
        assertEquals(199L, row.getField(8));
        assertEquals(9, ClickstreamJob.schema().getFieldCount());
    }

    @Test void rejectsMalformedEventsInsteadOfDroppingThem() {
        assertThrows(Exception.class, () -> ClickstreamJob.parse("{}"));
        assertThrows(Exception.class, () -> ClickstreamJob.parse(EVENT.replace("199", "1.99")));
        assertThrows(Exception.class, () -> ClickstreamJob.parse(EVENT.replace("payment", "unknown")));
        assertThrows(Exception.class, () -> ClickstreamJob.parse(EVENT.replace("2026-01-01T00:00:00.000Z", "invalid")));
    }

    @Test void localFlinkCommitsIcebergAndPreservesExactBusinessKeys(@TempDir Path directory) throws Exception {
        String location = directory.resolve("events").toUri().toString();
        org.apache.hadoop.conf.Configuration hadoop = new org.apache.hadoop.conf.Configuration();
        Table table = new HadoopTables(hadoop).create(FlinkSchemaUtil.convert(ClickstreamJob.schema()), PartitionSpec.unpartitioned(), location);
        org.apache.flink.configuration.Configuration flink = new org.apache.flink.configuration.Configuration();
        flink.setInteger("rest.port", 0);
        flink.setString("rest.bind-port", "0");
        StreamExecutionEnvironment env = StreamExecutionEnvironment.getExecutionEnvironment(flink);
        env.setParallelism(1);
        String second = EVENT.replace("8ac66c68d305", "8ac66c68d306");
        ClickstreamJob.attachSink(env.fromCollection(List.of(EVENT, second)).map(ClickstreamJob::parse).returns(ClickstreamJob.rowType()), TableLoader.fromHadoopTable(location, hadoop));
        env.execute("local-iceberg-integration-test");
        table.refresh();
        assertEquals("2", table.currentSnapshot().summary().get("total-records"));
        Set<String> keys = new HashSet<>();
        try (CloseableIterable<Record> records = IcebergGenerics.read(table).build()) {
            for (Record record : records) {
                keys.add(record.getField("event_id").toString());
                assertEquals(199L, record.getField("amount_cents"));
            }
        }
        assertEquals(Set.of("97f57c18-d5a6-5f83-9034-8ac66c68d305", "97f57c18-d5a6-5f83-9034-8ac66c68d306"), keys);
    }
}
