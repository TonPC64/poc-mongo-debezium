#!/bin/bash

echo "Stopping all services..."
docker-compose down

echo "Cleaning up volumes..."
docker-compose down -v

echo "Cleanup complete!"