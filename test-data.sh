#!/bin/bash

echo "Inserting test data into MongoDB..."

# Insert Alice Smith
echo "Inserting Alice Smith..."
docker exec mongodb mongo -u root -p root --authenticationDatabase admin --eval "db.getSiblingDB('testdb').users.insertOne({name: 'Alice Smith', email: 'alice@example.com', age: 30, created_at: new Date()}); print('Alice inserted');"

# Insert Bob Johnson  
echo "Inserting Bob Johnson..."
docker exec mongodb mongo -u root -p root --authenticationDatabase admin --eval "db.getSiblingDB('testdb').users.insertOne({name: 'Bob Johnson', email: 'bob@example.com', age: 25, created_at: new Date()}); print('Bob inserted');"

# Update John Doe (if exists)
echo "Updating John Doe..."
docker exec mongodb mongo -u root -p root --authenticationDatabase admin --eval "db.getSiblingDB('testdb').users.updateOne({name: 'John Doe'}, {\$set: {age: 35, updated_at: new Date()}}); print('John updated');"

echo "All test data operations completed!"

echo "Test data has been inserted. Check the Golang consumer logs to see the changes being processed."
echo "Run: docker-compose logs -f go-consumer"