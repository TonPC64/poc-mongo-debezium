#!/bin/bash

# Start MongoDB in the background
mongod --replSet rs0 --bind_ip_all --auth &
MONGOD_PID=$!

# Wait for MongoDB to be ready
echo "Waiting for MongoDB to start..."
while ! mongo --eval "print('MongoDB is ready')" >/dev/null 2>&1; do
    sleep 2
done

echo "MongoDB started, initializing replica set..."

# Initialize replica set
mongo --eval "
print('Initializing MongoDB replica set...');
var config = {
    '_id': 'rs0',
    'version': 1,
    'members': [
        {
            '_id': 1,
            'host': 'mongodb:27017'
        }
    ]
};
try {
    var result = rs.initiate(config, { force: true });
    print('Replica set initialization result:', JSON.stringify(result));
    sleep(3000);
    print('Replica set initialized successfully');
} catch (e) {
    print('Error initializing replica set:', e);
}
"

echo "Creating admin user..."
mongo --eval "
db.getSiblingDB('admin').createUser({
    user: 'root',
    pwd: 'root',
    roles: [{ role: 'root', db: 'admin' }]
});
"

echo "Creating test data..."
mongo -u root -p root --authenticationDatabase admin --eval "
db.getSiblingDB('testdb').users.insertOne({
    name: 'John Doe',
    email: 'john@example.com',
    age: 30,
    created_at: new Date(),
    metadata: {
        source: 'startup-script',
        version: '1.0'
    }
});
print('Test document inserted');
"

echo "MongoDB initialization complete!"

# Keep MongoDB running in foreground
wait $MONGOD_PID