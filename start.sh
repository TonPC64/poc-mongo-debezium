#!/bin/bash

echo "Starting Debezium MongoDB POC with Kafka KRaft (no Zookeeper)..."

# Start all services
docker-compose up -d

echo "Waiting for services to be ready..."
echo "Note: Using Kafka with KRaft mode - no Zookeeper required!"

# Wait for Kafka Connect to be ready
echo "Waiting for Kafka Connect to be ready..."
while ! curl -f -s http://localhost:8083/connectors >/dev/null; do
  echo "Kafka Connect is not ready yet..."
  sleep 1
done

echo "Kafka Connect is ready!"

# MongoDB replica set is initialized during Docker startup
echo "MongoDB replica set initialization happens during container startup..."
echo "Waiting for MongoDB to be fully ready with replica set..."

# Delete existing connector if it exists (in case of previous failed attempts)
echo "Cleaning up any existing connector..."
curl -X DELETE http://localhost:8083/connectors/mongodb-connector 2>/dev/null || true
sleep 5

# Create MongoDB connector
echo "Creating Debezium MongoDB connector..."
CONNECTOR_RESPONSE=$(curl -X POST -H "Content-Type: application/json" --data @debezium-config/mongodb-connector.json http://localhost:8083/connectors 2>/dev/null)

echo "Connector creation response: $CONNECTOR_RESPONSE"

# Wait for connector to initialize
sleep 10

echo ""
echo "Checking connector status..."
curl -s http://localhost:8083/connectors/mongodb-connector/status | jq . || echo "Failed to get connector status"

echo ""
echo "Setup complete! The system is now ready."
echo ""
echo "🎉 Services available:"
echo "📊 Redpanda Console (Kafka Web UI): http://localhost:8080"
echo "🔌 Kafka Connect API: http://localhost:8083"
echo "🍃 MongoDB: mongodb://root:root@localhost:27017"
echo ""
echo "You can:"
echo "1. Open Redpanda Console: http://localhost:8080"
echo "2. Insert test data: ./test-data.sh"
echo "3. View consumer logs: docker-compose logs -f go-consumer"
echo "4. Check connector: curl http://localhost:8083/connectors/mongodb-connector/status"