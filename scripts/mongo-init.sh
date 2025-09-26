#!/bin/bash

KEYFILE_PATH=/data/keyfile

# Create keyfile if it doesn't exist (required for replica set auth)
if [ ! -f "$KEYFILE_PATH" ]; then
    echo "Generating keyfile for replica set auth at $KEYFILE_PATH"
    mkdir -p /data
    # Generate a 756-byte base64 key (MongoDB recommends 768-bit key or similar)
    openssl rand -base64 756 > "$KEYFILE_PATH"
    chmod 600 "$KEYFILE_PATH"
fi

# Start MongoDB in the background WITHOUT auth for initial bootstrap
# Start mongod WITHOUT supplying the keyFile so the localhost exception is available
# (we generated the keyfile on disk but will not pass it to mongod until after
# creating the admin user). Passing --keyFile at startup can disable the
# localhost exception and require authentication for replSetInitiate.
mongod --replSet rs0 --bind_ip_all &
MONGOD_PID=$!

# Wait for MongoDB to be reachable (no auth yet)
echo "Waiting for mongod to accept connections..."
# Use mongosh (modern shell). If not present, fall back to mongo.
SHELL_CMD="mongosh"
if ! command -v "$SHELL_CMD" >/dev/null 2>&1; then
  SHELL_CMD="mongo"
fi
until $SHELL_CMD --quiet --eval "db.adminCommand('ping')" >/dev/null 2>&1; do
  sleep 1
done

echo "mongod is accepting connections. Initializing replica set..."

# Initialize replica set (single-node). Use container hostname so rs config matches connect string.
$SHELL_CMD --quiet --eval "
var config = { _id: 'rs0', version: 1, members: [{ _id: 1, host: 'mongodb:27017' }] };
try {
  var res = rs.initiate(config, { force: true });
  try { print('rs.initiate result: ' + JSON.stringify(res)); } catch(e) { print('rs.initiate result (stringify failed): ' + res); }
} catch (e) {
  try { print('rs.initiate error: ' + JSON.stringify(e)); } catch(err) { print('rs.initiate error: ' + e); }
}
"

# Wait until this node becomes PRIMARY
echo "Waiting for replica set to elect PRIMARY..."
for i in {1..60}; do
  state=$($SHELL_CMD --quiet --eval "rs.status().myState" 2>/dev/null || echo "")
    if [ "$state" = "1" ]; then
        echo "This node is PRIMARY"
        break
    fi
    echo "  current rs state: ${state:-unknown}, retrying..."
    sleep 2
done
echo "Creating test data and enabling changeStreamPreAndPostImages..."
$SHELL_CMD --quiet --eval "
db = db.getSiblingDB('testdb');
var collNames = db.getCollectionNames();
if (collNames.indexOf('users') === -1) {
  db.createCollection('users');
  print('Created collection users');
}
try {
  var info = db.getCollectionInfos({name: 'users'})[0];
  try { print('Collection info before collMod: ' + JSON.stringify(info)); } catch(e) { print('Collection info before collMod: ' + info); }
  db.runCommand({ collMod: 'users', changeStreamPreAndPostImages: { enabled: true } });
  print('Enabled changeStreamPreAndPostImages on users collection');
} catch (e) {
  try { print('collMod error: ' + JSON.stringify(e)); } catch(err) { print('collMod error: ' + e); }
}
db.users.insertOne({ name: 'John Doe', email: 'john@example.com', age: 30, created_at: new Date(), metadata: { source: 'startup-script', version: '1.0' } });
print('Test document inserted');
"

echo "Creating admin user..."
$SHELL_CMD --quiet --eval "
db.getSiblingDB('admin').createUser({ user: 'root', pwd: 'root', roles: [{ role: 'root', db: 'admin' }] });
print('admin user created');
"

echo "Shutting down mongod to restart with auth enabled..."
# Shutdown cleanly using the selected shell
$SHELL_CMD --quiet --eval "db.getSiblingDB('admin').shutdownServer()" >/dev/null 2>&1 || true
wait $MONGOD_PID 2>/dev/null || true

echo "Restarting mongod with --auth and keyFile enabled (foreground)..."
# Start mongod with auth enabled in foreground so container keeps running
exec mongod --replSet rs0 --bind_ip_all --keyFile "$KEYFILE_PATH" --auth