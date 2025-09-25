print("Initializing MongoDB replica set...");

var config = {
    "_id": "rs0",
    "version": 1,
    "members": [
        {
            "_id": 1,
            "host": "mongodb:27017"
        }
    ]
};

try {
    var result = rs.initiate(config, { force: true });
    print("Replica set initialization result:", JSON.stringify(result));
    
    // Wait for replica set to be ready
    sleep(5000);
    
    // Check replica set status
    var status = rs.status();
    print("Replica set status:", status.ok);
    
} catch (e) {
    print("Error initializing replica set:", e);
}

print("MongoDB replica set initialization complete!");