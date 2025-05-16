from pymongo import MongoClient
import json
import pandas as pd
import os
import random
from datetime import datetime, timedelta

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

# Generate date phrases for more realistic questions
def generate_date_phrases():
    today = datetime.now()
    yesterday = today - timedelta(days=1)
    last_week = today - timedelta(days=7)
    last_month = today - timedelta(days=30)
    
    # Month names
    months = ["January", "February", "March", "April", "May", "June", 
              "July", "August", "September", "October", "November", "December"]
    current_month = months[today.month - 1]
    prev_month = months[(today.month - 2) % 12]
    
    date_phrases = [
        "today", "yesterday", "this week", "last week", 
        "this month", "last month", f"in {current_month}", 
        f"during {prev_month}", f"{prev_month} {today.year}",
        f"between {prev_month} and {current_month}"
    ]
    
    # Add some specific dates
    date_phrases.extend([
        yesterday.strftime("%Y-%m-%d"),
        last_week.strftime("%Y-%m-%d"),
        last_month.strftime("%Y-%m-%d")
    ])
    
    return date_phrases

# Generate more question templates
def generate_question_templates():
    # Generic question starters
    question_starters = [
        "What is", "What was", "Show me", "Can you tell me", "I want to know",
        "How many", "Give me information about", "Please provide", "I need to see",
        "Tell me about", "Could you show", "Query", "Find", "Get"
    ]
    
    # Collection-specific keywords
    performance_keywords = [
        "production", "output", "efficiency", "performance", "units produced",
        "production rate", "manufacturing output", "yield", "productivity",
        "manufacturing performance", "production statistics"
    ]
    
    defect_keywords = [
        "defects", "quality issues", "defective units", "quality problems",
        "defect rate", "quality metrics", "rejection rate", "defect statistics",
        "quality performance", "defect distribution", "defect types", "defect categories"
    ]
    
    failure_keywords = [
        "machine failures", "equipment breakdowns", "machine issues", "maintenance records",
        "repair history", "machine problems", "equipment failures", "downtime records",
        "machine maintenance", "technical issues", "machinery breakdowns"
    ]
    
    order_keywords = [
        "orders", "order status", "shipments", "order tracking", "delivery status",
        "order details", "order information", "order processing", "order fulfillment",
        "order management", "order references"
    ]
    
    return {
        "starters": question_starters,
        "performance": performance_keywords,
        "defects": defect_keywords,
        "failures": failure_keywords,
        "orders": order_keywords
    }

# Generate a question by combining templates with real data
def generate_question(starter, keyword, entity=None, date_phrase=None, intent="", workshop=None):
    question = f"{starter} {keyword}"
    
    # Add entity if provided
    if entity:
        if "order" in keyword.lower():
            question = f"{starter} {keyword} for order {entity}"
        elif "machine" in keyword.lower() or "equipment" in keyword.lower():
            question = f"{starter} {keyword} for machine {entity}"
        elif "defect" in keyword.lower() or "quality" in keyword.lower():
            if random.random() > 0.5:
                question = f"{starter} {entity} {keyword}"
            else:
                question = f"{starter} {keyword} of type {entity}"
    
    # Add workshop if provided
    if workshop:
        workshop_phrase = f"for workshop {workshop}"
        if random.random() > 0.5:
            workshop_phrase = f"in workshop {workshop}"
        question = f"{question} {workshop_phrase}"
    
    # Add date phrase if provided
    if date_phrase:
        date_phrases = [
            f"for {date_phrase}",
            f"during {date_phrase}",
            f"in {date_phrase}",
            f"from {date_phrase}"
        ]
        question = f"{question} {random.choice(date_phrases)}"
    
    # Add question mark (sometimes)
    if random.random() > 0.3:
        question += "?"
    
    return {"text": question, "intent": intent}

# Generate training data with more variety and realistic examples
def generate_training_data():
    data = []
    
    # Get date phrases for more realistic questions
    date_phrases = generate_date_phrases()
    
    # Get question templates
    templates = generate_question_templates()
    
    # Performance intent samples
    print("Generating performance intent samples...")
    try:
        # Get performance samples to generate realistic questions
        performance_samples = list(db.performance3.find().limit(20))
        monthly_samples = list(db.monthly_performance.find().limit(10))
        
        # Combine samples
        all_performance_samples = performance_samples + monthly_samples
        
        # Extract workshops and dates
        workshops = set()
        for sample in all_performance_samples:
            if 'workshop' in sample:
                workshops.add(str(sample.get('workshop', '')))
            elif 'workshopId' in sample:
                workshops.add(str(sample.get('workshopId', '')))
        
        # Generate questions from real data
        for workshop in workshops:
            if not workshop:
                continue
                
            for starter in random.sample(templates["starters"], min(5, len(templates["starters"]))):
                for keyword in random.sample(templates["performance"], min(3, len(templates["performance"]))):
                    # With date
                    if random.random() > 0.5:
                        date_phrase = random.choice(date_phrases)
                        data.append(generate_question(starter, keyword, date_phrase=date_phrase, intent="performance", workshop=workshop))
                    # Without date
                    else:
                        data.append(generate_question(starter, keyword, intent="performance", workshop=workshop))
        
        # Add some questions without specific workshop
        for i in range(10):
            starter = random.choice(templates["starters"])
            keyword = random.choice(templates["performance"])
            date_phrase = random.choice(date_phrases) if random.random() > 0.5 else None
            data.append(generate_question(starter, keyword, date_phrase=date_phrase, intent="performance"))
            
    except Exception as e:
        print(f"Error generating performance samples: {e}")
    
    # Defects intent samples
    print("Generating defects intent samples...")
    try:
        # Start with explicit defect type extraction
        defect_types = set()
        
        # Try dedicated defect_types collection
        defect_samples = list(db.defect_types.find())
        if defect_samples:
            for sample in defect_samples:
                defect_type = sample.get('name', sample.get('type', ''))
                if defect_type:
                    defect_types.add(defect_type)
        
        # If no dedicated collection, try to extract defect types from performance data
        if not defect_types:
            for collection_name in ['performance3', 'monthly_performance']:
                try:
                    # Look for fields that might contain defect information
                    sample_doc = db[collection_name].find_one()
                    if not sample_doc:
                        continue
                    
                    potential_defect_fields = [
                        field for field in sample_doc.keys() 
                        if 'defect' in field.lower() or 'quality' in field.lower() or 'issue' in field.lower()
                    ]
                    
                    if potential_defect_fields:
                        print(f"Found potential defect fields in {collection_name}: {potential_defect_fields}")
                except Exception:
                    continue
        
        # If still no defect types found, use predefined common types
        if not defect_types:
            defect_types = {
                "Stain", "Tear", "Size issue", "Color issue", "Missing component",
                "Loose thread", "Fabric damage", "Seam defect", "Button defect",
                "Zipper issue", "Print defect", "Quality issue"
            }
            print(f"Using predefined defect types: {defect_types}")
        
        # Generate defect-related questions
        for defect_type in defect_types:
            for starter in random.sample(templates["starters"], min(3, len(templates["starters"]))):
                for keyword in random.sample(templates["defects"], min(3, len(templates["defects"]))):
                    # With date
                    if random.random() > 0.5:
                        date_phrase = random.choice(date_phrases)
                        data.append(generate_question(starter, keyword, entity=defect_type, date_phrase=date_phrase, intent="defects"))
                    # Without date
                    else:
                        data.append(generate_question(starter, keyword, entity=defect_type, intent="defects"))
        
        # Add general defect questions without specific defect type
        for i in range(15):
            starter = random.choice(templates["starters"])
            keyword = random.choice(templates["defects"])
            date_phrase = random.choice(date_phrases) if random.random() > 0.5 else None
            data.append(generate_question(starter, keyword, date_phrase=date_phrase, intent="defects"))
            
        # Add specific questions about defect types
        defect_type_questions = [
            "What are the defect types?",
            "List all defect types",
            "Show me all defect categories",
            "Can you list the types of defects?",
            "What defect types do we track?",
            "Give me the list of all quality issues",
            "Show the categories of defects we monitor"
        ]
        
        for question in defect_type_questions:
            data.append({"text": question, "intent": "defects"})
        
    except Exception as e:
        print(f"Error generating defect samples: {e}")
    
    # Machine failures intent samples
    print("Generating failures intent samples...")
    try:
        machine_ids = set()
        technicians = set()
        
        # Try to get failure data from machinefailures collection
        failure_collections = ['new_data.machinefailures', 'machinefailures', 'equipment_failures', 'maintenance']
        
        for collection_name in failure_collections:
            if collection_name in db.list_collection_names():
                failure_samples = list(db[collection_name].find().limit(20))
                
                for sample in failure_samples:
                    # Extract machine IDs using various possible field names
                    for field in ['machineReference', 'machine_id', 'machine', 'machineId', 'equipment_id']:
                        if field in sample and sample[field]:
                            machine_ids.add(str(sample[field]))
                    
                    # Extract technician names using various possible field names
                    for field in ['technicianName', 'technician_name', 'technician', 'repairTechnician', 'engineer']:
                        if field in sample and sample[field]:
                            technicians.add(str(sample[field]))
        
        # If no real data found, use some sample IDs
        if not machine_ids:
            machine_ids = {'M001', 'M002', 'M003', 'M101', 'M102'}
        
        if not technicians:
            technicians = {'John', 'Sarah', 'Ahmed', 'Maria', 'Carlos'}
        
        # Generate questions for each machine
        for machine_id in machine_ids:
            for starter in random.sample(templates["starters"], min(3, len(templates["starters"]))):
                for keyword in random.sample(templates["failures"], min(3, len(templates["failures"]))):
                    # With date
                    if random.random() > 0.5:
                        date_phrase = random.choice(date_phrases)
                        data.append(generate_question(starter, keyword, entity=machine_id, date_phrase=date_phrase, intent="failures"))
                    # Without date
                    else:
                        data.append(generate_question(starter, keyword, entity=machine_id, intent="failures"))
        
        # Add questions about technicians
        for technician in technicians:
            for i in range(2):
                question = f"{random.choice(templates['starters'])} {random.choice(templates['failures'])} handled by {technician}"
                if random.random() > 0.5:
                    question += "?"
                data.append({"text": question, "intent": "failures"})
        
        # Add general failure questions
        for i in range(10):
            starter = random.choice(templates["starters"])
            keyword = random.choice(templates["failures"])
            date_phrase = random.choice(date_phrases) if random.random() > 0.5 else None
            data.append(generate_question(starter, keyword, date_phrase=date_phrase, intent="failures"))
            
    except Exception as e:
        print(f"Error generating failure samples: {e}")
    
    # Orders intent samples
    print("Generating orders intent samples...")
    try:
        order_ids = set()
        
        # Look for order references in different collections
        order_collections = ['order_references', 'orders', 'production_orders']
        
        for collection_name in order_collections:
            if collection_name in db.list_collection_names():
                order_samples = list(db[collection_name].find().limit(20))
                
                for sample in order_samples:
                    # Extract order IDs using various possible field names
                    for field in ['orderRef', 'order_id', 'orderReference', 'orderId', 'order_reference', 'order']:
                        if field in sample and sample[field]:
                            order_ids.add(str(sample[field]))
        
        # If no real data found, use some sample IDs
        if not order_ids:
            order_ids = {'101', '102', '103', '104', '105', '201', '202'}
        
        # Generate questions for each order
        for order_id in order_ids:
            for starter in random.sample(templates["starters"], min(3, len(templates["starters"]))):
                for keyword in random.sample(templates["orders"], min(2, len(templates["orders"]))):
                    data.append(generate_question(starter, keyword, entity=order_id, intent="orders"))
        
        # Add general order questions
        for i in range(10):
            starter = random.choice(templates["starters"])
            keyword = random.choice(templates["orders"])
            date_phrase = random.choice(date_phrases) if random.random() > 0.5 else None
            data.append(generate_question(starter, keyword, date_phrase=date_phrase, intent="orders"))
            
    except Exception as e:
        print(f"Error generating order samples: {e}")
    
    # Add mixed/complex questions that combine multiple aspects
    print("Generating complex mixed questions...")
    try:
        mixed_templates = [
            "Compare {metric} between workshop {workshop1} and {workshop2}",
            "What's the defect rate in workshop {workshop} during {date}?",
            "How does production in {date1} compare to {date2}?",
            "Show me the relationship between machine failures and production output",
            "What workshop has the highest production with the lowest defect rate?",
            "Compare the defect rates before and after the maintenance in {date}",
            "What's the efficiency trend for workshop {workshop} over the last three months?",
            "Analyze the impact of machine failures on monthly production targets",
            "Which defect type is most common in high-production workshops?",
            "Compare order completion rates between {date1} and {date2}"
        ]
        
        workshops = list(range(1, 6))  # Assuming workshops 1-5
        dates = [d for d in date_phrases if not d.startswith("20")]  # Remove explicit dates
        
        for template in mixed_templates:
            # Replace placeholders with random values
            question = template
            if "{workshop}" in template:
                question = question.replace("{workshop}", str(random.choice(workshops)))
            if "{workshop1}" in template and "{workshop2}" in template:
                w1, w2 = random.sample(workshops, 2)
                question = question.replace("{workshop1}", str(w1)).replace("{workshop2}", str(w2))
            if "{date}" in template:
                question = question.replace("{date}", random.choice(dates))
            if "{date1}" in template and "{date2}" in template:
                d1, d2 = random.sample(dates, 2)
                question = question.replace("{date1}", d1).replace("{date2}", d2)
            if "{metric}" in template:
                metrics = ["production", "efficiency", "defect rate", "quality", "performance"]
                question = question.replace("{metric}", random.choice(metrics))
                
            # Determine the primary intent based on keywords
            intent = "performance"  # Default
            if "defect" in question.lower():
                intent = "defects"
            elif "machine" in question.lower() or "failure" in question.lower():
                intent = "failures"
            elif "order" in question.lower():
                intent = "orders"
                
            data.append({"text": question, "intent": intent})
            
    except Exception as e:
        print(f"Error generating mixed samples: {e}")
    
    return data

# Generate and save the training data
training_data = generate_training_data()
df = pd.DataFrame(training_data)

# Save to CSV for training
os.makedirs('data', exist_ok=True)
df.to_csv('data/intent_training_data.csv', index=False)
print(f"Saved {len(df)} training examples to data/intent_training_data.csv")

# Print sample of data
print("\nSample training data:")
print(df.sample(min(10, len(df))))
print(f"\nIntent distribution:\n{df['intent'].value_counts()}") 