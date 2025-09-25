package main

import (
	"log"
	"strings"
	"time"

	"github.com/Shopify/sarama"
)

func waitForKafka(brokers string, maxRetries int, retryInterval time.Duration) error {
	brokerList := strings.Split(brokers, ",")

	config := sarama.NewConfig()
	config.Version = sarama.V2_4_0_0
	config.Net.DialTimeout = 10 * time.Second
	config.Net.ReadTimeout = 10 * time.Second
	config.Net.WriteTimeout = 10 * time.Second

	for i := 0; i < maxRetries; i++ {
		log.Printf("Attempting to connect to Kafka (attempt %d/%d)...", i+1, maxRetries)

		client, err := sarama.NewClient(brokerList, config)
		if err != nil {
			log.Printf("Failed to connect to Kafka: %v", err)
			if i < maxRetries-1 {
				log.Printf("Retrying in %v...", retryInterval)
				time.Sleep(retryInterval)
				continue
			}
			return err
		}

		// Test if we can fetch brokers
		brokers := client.Brokers()
		if len(brokers) == 0 {
			client.Close()
			log.Printf("No Kafka brokers available")
			if i < maxRetries-1 {
				log.Printf("Retrying in %v...", retryInterval)
				time.Sleep(retryInterval)
				continue
			}
			return err
		}

		// Test if we can fetch topics
		topics, err := client.Topics()
		if err != nil {
			client.Close()
			log.Printf("Failed to get Kafka topics: %v", err)
			if i < maxRetries-1 {
				log.Printf("Retrying in %v...", retryInterval)
				time.Sleep(retryInterval)
				continue
			}
			return err
		}

		log.Printf("Kafka is ready with %d brokers and %d topics", len(brokers), len(topics))

		// Test connection successful
		client.Close()
		log.Println("Successfully connected to Kafka!")
		return nil
	}

	return nil
}

func testKafkaConnectivity(brokers string) error {
	log.Println("Testing Kafka connectivity...")

	// Wait for Kafka to be ready with retries
	return waitForKafka(brokers, 10, 5*time.Second)
}
