from pymongo import MongoClient
import json

# Connect to MongoDB
print("Connecting to MongoDB...")
try:
    client = MongoClient("mongodb+srv://nour:nour123@cluster0.vziu9.mongodb.net/clothing_factory?retryWrites=true&w=majority",
                      serverSelectionTimeoutMS=5000)
    client.admin.command('ping')
    db = client["clothing_factory"]
    print("MongoDB connection successful!")
except Exception as e:
    print(f"MongoDB connection error: {e}")
    exit(1)

# Helper function to print JSON
def print_json(data):
    return json.dumps(data, indent=2, default=str)

# Check all collections for workshop data
collections = db.list_collection_names()
print(f"Available collections: {collections}")

for collection_name in collections:
    try:
        # Look at one sample document to understand schema
        sample = db[collection_name].find_one()
        if not sample:
            print(f"No documents in {collection_name}")
            continue
            
        print(f"\n=== Sample document from {collection_name} ===")
        
        # Check if this collection has workshop-related fields
        has_workshop_field = False
        for field in sample.keys():
            if 'workshop' in field.lower():
                has_workshop_field = True
                print(f"Found workshop field: {field} = {sample[field]}")
                
        if not has_workshop_field:
            workshop_related = False
            # Check if any field looks like it could be a workshop ID
            for field, value in sample.items():
                if isinstance(value, str) and value.isdigit() and len(value) <= 2:
                    print(f"Potential workshop ID field: {field} = {value}")
                    workshop_related = True
                    
            if not workshop_related:
                print(f"No workshop-related fields found in {collection_name}")
                continue
        
        # Try to find data for workshop 1 and 2 using various field patterns
        potential_fields = [
            'workshop',
            'workshopId',
            'workshop_id',
            'Workshop',
            'workshop_name',
            'line',
            'line_id'
        ]
        
        for field in potential_fields:
            # Try exact match on potential fields
            count1 = db[collection_name].count_documents({field: "1"})
            count2 = db[collection_name].count_documents({field: "2"})
            count1_num = db[collection_name].count_documents({field: 1})
            count2_num = db[collection_name].count_documents({field: 2})
            
            if count1 > 0 or count2 > 0 or count1_num > 0 or count2_num > 0:
                print(f"Found workshop data in field '{field}':")
                print(f"  Workshop 1 (string): {count1} records")
                print(f"  Workshop 2 (string): {count2} records")
                print(f"  Workshop 1 (number): {count1_num} records")
                print(f"  Workshop 2 (number): {count2_num} records")
                
                # Get a sample document for each workshop
                if count1 > 0:
                    sample1 = db[collection_name].find_one({field: "1"})
                    print(f"\nSample for Workshop 1:")
                    print(print_json(sample1))
                elif count1_num > 0:
                    sample1 = db[collection_name].find_one({field: 1})
                    print(f"\nSample for Workshop 1:")
                    print(print_json(sample1))
                    
                if count2 > 0:
                    sample2 = db[collection_name].find_one({field: "2"})
                    print(f"\nSample for Workshop 2:")
                    print(print_json(sample2))
                elif count2_num > 0:
                    sample2 = db[collection_name].find_one({field: 2})
                    print(f"\nSample for Workshop 2:")
                    print(print_json(sample2))
                
                break
                
    except Exception as e:
        print(f"Error analyzing collection {collection_name}: {e}")

print("\nSample data search complete.") 