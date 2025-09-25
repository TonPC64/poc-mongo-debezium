package main

import (
	"context"
	"encoding/json"
	"log"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/Shopify/sarama"
)

type DebeziumMessage struct {
	Before interface{} `json:"before"`
	After  interface{} `json:"after"`
	Patch  interface{} `json:"patch"`
	Filter interface{} `json:"filter"`
	Source struct {
		Version    string `json:"version"`
		Connector  string `json:"connector"`
		Name       string `json:"name"`
		TsMs       int64  `json:"ts_ms"`
		Snapshot   string `json:"snapshot"`
		Db         string `json:"db"`
		Rs         string `json:"rs"`
		Collection string `json:"collection"`
	} `json:"source"`
	Op          string      `json:"op"`
	TsMs        int64       `json:"ts_ms"`
	Transaction interface{} `json:"transaction"`
}

func main() {
	brokers := getEnv("KAFKA_BROKERS", "kafka:29092")
	topic := getEnv("KAFKA_TOPIC", "mongodb.testdb.users")
	groupID := getEnv("KAFKA_GROUP_ID", "go-consumer-group")

	// Wait for Kafka to be healthy before starting consumer
	log.Println("Checking Kafka health before starting consumer...")
	if err := testKafkaConnectivity(brokers); err != nil {
		log.Fatalf("Kafka health check failed: %v", err)
	}

	config := sarama.NewConfig()
	config.Consumer.Group.Rebalance.Strategy = sarama.BalanceStrategyRoundRobin
	config.Consumer.Offsets.Initial = sarama.OffsetOldest
	config.Version = sarama.V2_4_0_0

	consumer := Consumer{
		ready: make(chan bool),
	}

	ctx, cancel := context.WithCancel(context.Background())
	client, err := sarama.NewConsumerGroup([]string{brokers}, groupID, config)
	if err != nil {
		log.Panicf("Error creating consumer group client: %v", err)
	}

	go func() {
		for {
			if err := client.Consume(ctx, []string{topic}, &consumer); err != nil {
				log.Panicf("Error from consumer: %v", err)
			}
			if ctx.Err() != nil {
				return
			}
			consumer.ready = make(chan bool)
		}
	}()

	<-consumer.ready
	log.Println("Sarama consumer up and running!...")

	sigterm := make(chan os.Signal, 1)
	signal.Notify(sigterm, syscall.SIGINT, syscall.SIGTERM)
	select {
	case <-ctx.Done():
		log.Println("terminating: context cancelled")
	case <-sigterm:
		log.Println("terminating: via signal")
	}
	cancel()

	if err = client.Close(); err != nil {
		log.Panicf("Error closing client: %v", err)
	}
}

type Consumer struct {
	ready chan bool
}

func (consumer *Consumer) Setup(sarama.ConsumerGroupSession) error {
	close(consumer.ready)
	return nil
}

func (consumer *Consumer) Cleanup(sarama.ConsumerGroupSession) error {
	return nil
}

func (consumer *Consumer) ConsumeClaim(session sarama.ConsumerGroupSession, claim sarama.ConsumerGroupClaim) error {
	for {
		select {
		case message := <-claim.Messages():
			if message == nil {
				return nil
			}

			log.Printf("Message claimed: value = %s, timestamp = %v, topic = %s, partition = %d, offset = %d",
				string(message.Value), message.Timestamp, message.Topic, message.Partition, message.Offset)

			// Check for empty or null messages (common with deletes)
			if len(message.Value) == 0 {
				log.Printf("Received empty message (tombstone) - likely a delete operation")
				session.MarkMessage(message, "")
				continue
			}

			// Check for null messages
			if string(message.Value) == "null" {
				log.Printf("Received null message (tombstone) - delete operation completed")
				session.MarkMessage(message, "")
				continue
			}

			// Parse Debezium message
			var debeziumMsg DebeziumMessage
			if err := json.Unmarshal(message.Value, &debeziumMsg); err != nil {
				log.Printf("Error parsing Debezium message: %v", err)
				log.Printf("Raw message content: %s", string(message.Value))
				
				// Try to handle as a simple string or different format
				handleUnparsableMessage(message.Value, message.Topic, message.Partition, message.Offset)
			} else {
				handleDebeziumMessage(debeziumMsg)
			}

			session.MarkMessage(message, "")

		case <-session.Context().Done():
			return nil
		}
	}
}



func handleDebeziumMessage(msg DebeziumMessage) {
	log.Printf("=== Debezium Message ===")
	log.Printf("Operation: %s", msg.Op)
	log.Printf("Database: %s", msg.Source.Db)
	log.Printf("Collection: %s", msg.Source.Collection)
	log.Printf("Timestamp: %s", time.Unix(msg.TsMs/1000, 0))

	switch msg.Op {
	case "c": // Create
		log.Printf("Document created: %+v", msg.After)
		
	case "u": // Update
		log.Printf("Document updated:")
		if msg.Before != nil {
			log.Printf("  Before: %+v", msg.Before)
		}
		if msg.After != nil {
			log.Printf("  After: %+v", msg.After)
		}
		if msg.Patch != nil {
			log.Printf("  Patch: %+v", msg.Patch)
		}
		if msg.Filter != nil {
			log.Printf("  Filter: %+v", msg.Filter)
		}
		
	case "d": // Delete
		log.Printf("Document deleted - Before: %+v", msg.Before)
		log.Printf("Delete Filter: %+v", msg.Filter)
		
	case "r": // Read (snapshot)
		log.Printf("Document read (snapshot): %+v", msg.After)
		
	default:
		log.Printf("Unknown operation: %s", msg.Op)
	}
	log.Printf("========================")
}

func handleUnparsableMessage(messageValue []byte, topic string, partition int32, offset int64) {
	log.Printf("=== Unparsable Message ===")
	log.Printf("Topic: %s, Partition: %d, Offset: %d", topic, partition, offset)
	log.Printf("Raw content length: %d bytes", len(messageValue))
	
	// Try to detect if it's a tombstone message (common for deletes)
	if len(messageValue) == 0 {
		log.Printf("Type: Empty tombstone message (delete completion)")
	} else if string(messageValue) == "null" {
		log.Printf("Type: Null tombstone message (delete completion)")
	} else {
		// Try to parse as a simple JSON object
		var genericMsg map[string]interface{}
		if err := json.Unmarshal(messageValue, &genericMsg); err == nil {
			log.Printf("Type: Generic JSON message")
			log.Printf("Content: %+v", genericMsg)
		} else {
			log.Printf("Type: Non-JSON message")
			log.Printf("Content: %s", string(messageValue))
		}
	}
	log.Printf("==========================")
}

func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}
