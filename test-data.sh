#!/bin/bash

echo "Inserting test data into MongoDB..."

# Helper: run eval using mongosh if available, otherwise fall back to mongo
run_eval() {
	local js="$1"
	# Pipe the JS to the container's mongosh/mongo via stdin to avoid multilayer shell-quoting issues.
	# Using docker exec -i so the JS is sent on stdin and executed by the chosen shell inside the container.
	printf '%s\n' "$js" | docker exec -i mongodb bash -c "if command -v mongosh >/dev/null 2>&1; then mongosh --username root --password root --authenticationDatabase admin --quiet; else mongo -u root -p root --authenticationDatabase admin --quiet; fi"
}

echo "Inserting Alice Smith..."
run_eval "db.getSiblingDB('testdb').users.insertOne({name: 'Alice Smith', email: 'alice@example.com', age: 30, created_at: new Date()}); print('Alice inserted')"

echo "Inserting Bob Johnson..."
run_eval "db.getSiblingDB('testdb').users.insertOne({name: 'Bob Johnson', email: 'bob@example.com', age: 25, created_at: new Date()}); print('Bob inserted')"

echo "Updating John Doe..."
run_eval "db.getSiblingDB('testdb').users.updateOne({name: 'John Doe'}, {\$set: {age: 35, updated_at: new Date()}}); print('John updated')"

echo "Deleting Bob Johnson..."
run_eval "var res = db.getSiblingDB('testdb').users.deleteOne({name: 'Bob Johnson'}); print('Bob deleted, deletedCount=' + res.deletedCount)"

echo "All test data operations completed!"

echo "Test data operations ran. Check the Golang consumer logs to see the changes being processed."
echo "Run: docker-compose logs -f go-consumer"