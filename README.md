# Debezium MongoDB + Kafka + Golang Consumer POC

This is a proof of concept demonstrating Change Data Capture (CDC) from MongoDB 3.6 to a Golang consumer application using Debezium and Kafka 2.4.

## Architecture

```
MongoDB 3.6 (Replica Set) → Debezium Connector → Kafka 3.4.1 (KRaft) → Golang Consumer
```

## Components

- **MongoDB 3.6**: Source database with replica set enabled (required for Debezium)
- **Kafka 3.4.1 (Bitnami)**: Message broker with KRaft mode (no Zookeeper required)
- **Debezium**: MongoDB connector for change data capture
- **Golang Consumer**: Application consuming and processing change events

## Key Features

- **KRaft Mode**: Uses Kafka's native metadata management (no Zookeeper dependency)
- **Health Checks**: Services wait for dependencies to be healthy before starting
- **Simplified Architecture**: Fewer moving parts, faster startup
- **Better Performance**: Improved metadata handling and cluster coordination
- **Reliable Startup**: Built-in connectivity verification and retry logic

## Prerequisites

- Docker and Docker Compose
- curl (for API calls)
- jq (optional, for pretty JSON output)

## Quick Start

1. **Start the entire stack:**
   ```bash
   ./start.sh
   ```

2. **Insert test data to see changes:**
   ```bash
   ./test-data.sh
   ```

3. **View the Golang consumer logs:**
   ```bash
   docker-compose logs -f go-consumer
   ```

4. **Clean up when done:**
   ```bash
   ./cleanup.sh
   ```

## Manual Setup

If you prefer manual setup:

1. **Start all services:**
   ```bash
   docker-compose up -d
   ```

2. **Wait for services to be ready (about 30 seconds)**

3. **Create the Debezium connector:**
   ```bash
   curl -X POST -H "Content-Type: application/json" \
     --data @debezium-config/mongodb-connector.json \
     http://localhost:8083/connectors
   ```

4. **Check connector status:**
   ```bash
   curl http://localhost:8083/connectors/mongodb-connector/status
   ```

## Testing the Setup

### Insert Data into MongoDB

Connect to MongoDB and insert test documents:

```bash
docker exec -it mongodb mongo -u root -p root --authenticationDatabase admin
```

```javascript
use testdb;

// Insert a new document
db.users.insertOne({
  name: "Jane Doe",
  email: "jane@example.com",
  age: 28,
  created_at: new Date()
});

// Update a document
db.users.updateOne(
  { name: "John Doe" },
  { $set: { age: 36 } }
);

// Delete a document
db.users.deleteOne({ name: "Jane Doe" });
```

### Monitor Changes

Watch the Golang consumer logs to see the change events:

```bash
docker-compose logs -f go-consumer
```

You should see output like:
```
=== Debezium Message ===
Operation: c
Database: testdb
Collection: users
Timestamp: 2025-09-25 10:58:13
Document created: map[_id:map[...] name:Jane Doe email:jane@example.com ...]
========================
```

## Health Check Configuration

This POC includes comprehensive health checks to ensure reliable service startup:

### Service Dependencies
- **MongoDB**: Health check using `mongo --eval "db.adminCommand('ping')"`
- **Kafka**: Health check using `kafka-topics.sh --bootstrap-server kafka:29092 --list`
- **Kafka Connect**: Waits for both MongoDB and Kafka to be healthy
- **Go Consumer**: Waits for Kafka health + includes internal connectivity verification

### Health Check Benefits
- **Reliable Startup**: Services only start when their dependencies are ready
- **Faster Debugging**: Clear visibility into which services are healthy
- **Production Ready**: Health checks can be used with orchestrators like Kubernetes
- **Reduced Race Conditions**: Eliminates timing issues during startup

### Health Check Timing
- **MongoDB**: 30s start period, 10s intervals, 3 retries
- **Kafka**: 45s start period, 15s intervals, 5 retries
- **Services**: Automatically wait for health checks to pass

## Configuration Details

### MongoDB Configuration
- **Version**: 3.6
- **Replica Set**: rs0 (required for Debezium)
- **Port**: 27017
- **Admin User**: root/root
- **Test Database**: testdb
- **Test Collection**: users

### Kafka Configuration
- **Version**: 3.4.1 (Bitnami with KRaft mode)
- **Platform**: linux/amd64 (explicit platform support)
- **Port**: 9092 (external), 29092 (internal)
- **Mode**: KRaft (no Zookeeper required)
- **Controller Port**: 9093
- **Topics**: Auto-created by Debezium
  - `mongodb.testdb.users` - Main change events
  - `dbhistory.mongodb` - Database history

### Debezium Connector Configuration
- **Connector Class**: `io.debezium.connector.mongodb.MongoDbConnector`
- **MongoDB Host**: mongodb:27017
- **Monitored Database**: testdb
- **Monitored Collection**: testdb.users
- **Transform**: ExtractNewRecordState (unwraps the Debezium envelope)

### Golang Consumer
- **Kafka Library**: Shopify/sarama
- **Consumer Group**: go-consumer-group
- **Auto Offset Reset**: earliest
- **Hot Reload**: Air for development
- **Features**:
  - Graceful shutdown handling
  - Debezium message parsing
  - Operation type detection (create, update, delete, read)
  - Structured logging
  - Hot reload for development

## Monitoring and Debugging

### Check Kafka Connect Status
```bash
curl http://localhost:8083/connectors
curl http://localhost:8083/connectors/mongodb-connector/status
```

### List Kafka Topics
```bash
docker exec kafka kafka-topics.sh --bootstrap-server localhost:9092 --list
```

### View Kafka Messages Directly
```bash
docker exec kafka kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic mongodb.testdb.users \
  --from-beginning
```

### Check Service Logs
```bash
# All services
docker-compose logs

# Specific service
docker-compose logs mongodb
docker-compose logs kafka
docker-compose logs connect
docker-compose logs go-consumer
```

### MongoDB Replica Set Status
```bash
docker exec mongodb mongo --eval "rs.status()"
```

## Troubleshooting

### Common Issues

1. **Connector fails to start**: 
   - Ensure MongoDB replica set is initialized
   - Check MongoDB authentication credentials
   - Verify network connectivity

2. **No messages in Kafka**:
   - Check if MongoDB operations are happening on the monitored collection
   - Verify connector is running: `curl http://localhost:8083/connectors/mongodb-connector/status`
   - Check connector logs: `docker-compose logs connect`

3. **Golang consumer not receiving messages**:
   - Verify Kafka broker is accessible
   - Check topic exists: `docker exec kafka kafka-topics --bootstrap-server localhost:9092 --list`
   - Ensure consumer group is not blocked

### Reset Everything
```bash
./cleanup.sh
./start.sh
```

## Development

### Modifying the Golang Consumer (Hot Reload)

The Golang consumer now supports hot reload using Air! Simply edit the code in `go-consumer/main.go` and the changes will be automatically reloaded.

**Hot Reload Features:**
- Automatic rebuild on file changes
- No need to restart containers
- Fast development cycle
- Live logs showing rebuild status

**Development Workflow:**
1. Edit `go-consumer/main.go` or any Go files
2. Save the file
3. Air automatically detects changes and rebuilds
4. New version runs immediately

**Manual Rebuild (if needed):**
1. Rebuild the container:
   ```bash
   docker-compose build go-consumer
   ```

2. Restart the consumer:
   ```bash
   docker-compose restart go-consumer
   ```

### Adding New Collections

To monitor additional MongoDB collections:

1. Update the connector configuration in `debezium-config/mongodb-connector.json`
2. Add the new collection to `collection.whitelist`
3. Restart the connector:
   ```bash
   curl -X PUT -H "Content-Type: application/json" \
     --data @debezium-config/mongodb-connector.json \
     http://localhost:8083/connectors/mongodb-connector/config
   ```

## Production Considerations

This setup is for POC/development purposes. For production:

1. **Security**: Enable SSL/TLS, proper authentication, network isolation
2. **Scalability**: Multiple Kafka brokers, partitioned topics, multiple consumer instances
3. **Reliability**: Persistent volumes, backup strategies, monitoring and alerting
4. **Performance**: Tune Kafka and Debezium configurations for your workload
5. **Monitoring**: Add proper metrics collection and monitoring (Prometheus, Grafana, etc.)

## References

- [Debezium MongoDB Connector Documentation](https://debezium.io/documentation/reference/connectors/mongodb.html)
- [Apache Kafka Documentation](https://kafka.apache.org/documentation/)
- [Sarama Kafka Client for Go](https://github.com/Shopify/sarama)
- [MongoDB Replica Set Documentation](https://docs.mongodb.com/manual/replication/)