from pymongo import MongoClient
import json
import sys

# Connect to MongoDB
print("Connecting to MongoDB...")
try:
    client = MongoClient("mongodb+srv://nour:nour123@cluster0.vziu9.mongodb.net/clothing_factory?retryWrites=true&w=majority",
                         serverSelectionTimeoutMS=5000)
    # Test connection
    client.admin.command('ping')
    db = client["clothing_factory"]
    print("MongoDB connection successful!")
except Exception as e:
    print(f"MongoDB connection error: {e}")
    sys.exit(1)

# Helper function to print JSON
def print_json(data):
    return json.dumps(data, indent=2, default=str)

# List all collections
print("\n=== Collections in database ===")
collections = db.list_collection_names()
print(collections)

# Analyze all collections to understand their structure
for collection_name in collections:
    print(f"\n\n{'='*20} Collection: {collection_name} {'='*20}")
    
    try:
        # Count documents
        count = db[collection_name].count_documents({})
        print(f"Total documents: {count}")
        
        # Get a sample document
        if count > 0:
            sample = db[collection_name].find_one()
            print("\nSample document structure:")
            print(print_json(sample))
            
            # Show all field names in this collection
            print("\nField names in collection:")
            for field in sample.keys():
                print(f"  - {field}")
                
            # Show some statistics for common fields
            print("\nUnique values in common fields:")
            common_fields = ['technicianName', 'technician_name', 'technician', 
                            'machineReference', 'machine_id', 'machine',
                            'orderRef', 'order_reference', 'workshop']
            
            for field in common_fields:
                if field in sample:
                    values = db[collection_name].distinct(field)
                    print(f"  {field}: {len(values)} unique values")
                    # Print up to 5 examples
                    if values:
                        print(f"    Examples: {values[:5]}")
    except Exception as e:
        print(f"Error analyzing collection {collection_name}: {e}")

print("\nDatabase analysis complete.")

# If a search term is provided, use it to test queries
if len(sys.argv) > 1:
    search_term = sys.argv[1]
    print(f"\n\n===== Testing search for: {search_term} =====")
    
    # Try to search across all collections with different query patterns
    for collection_name in collections:
        print(f"\n--- Searching in {collection_name} ---")
        
        try:
            # Get a sample document to inspect fields
            sample = db[collection_name].find_one()
            if not sample:
                print(f"No documents in {collection_name}")
                continue
                
            # Try different fields that might contain the search term
            fields_to_try = ['technicianName', 'technician_name', 'technician', 
                            'machineReference', 'machine_id', 'machine',
                            'description', 'issue', 'orderRef', 'date']
            
            for field in fields_to_try:
                if field in sample:
                    # Try exact match
                    query = {field: search_term}
                    results = list(db[collection_name].find(query).limit(2))
                    if results:
                        print(f"Found {len(results)} results with exact match on {field}")
                    
                    # Try case-insensitive match
                    query = {field: {"$regex": search_term, "$options": "i"}}
                    results = list(db[collection_name].find(query).limit(2))
                    if results:
                        print(f"Found {len(results)} results with regex match on {field}")
                        print("First match:")
                        print(print_json(results[0]))
        except Exception as e:
            print(f"Error searching in {collection_name}: {e}")
else:
    print("\nTip: Run with a search term to test queries, e.g., 'python check_db.py nourelhouda'") 