from pymongo import MongoClient
import json
import pandas as pd
import os

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

# Define sample questions for each intent based on collections
def generate_training_data():
    data = []
    
    # Performance intent samples
    print("Generating performance intent samples...")
    try:
        # Get a few performance samples to generate realistic questions
        performance_samples = list(db.performance3.find().limit(5))
        monthly_samples = list(db.monthly_performance.find().limit(5))
        
        performance_questions = [
            "What is the production performance last month?",
            "Show me the production data for workshop 1",
            "How many units were produced yesterday?",
            "What was the production rate per hour last week?",
            "Show me the production efficiency for workshop 2",
            "What's the current month's production output?",
            "I need to see today's production statistics",
            "Show performance for Workshop 1 this month",
            "What's the production trend for this week?",
            "Give me the hourly production rate"
        ]
        
        # Add samples with real values if available
        if performance_samples:
            for sample in performance_samples:
                if 'workshop' in sample:
                    workshop = sample.get('workshop', '')
                    data.append({"text": f"What is the production for {workshop}?", "intent": "performance"})
        
        # Add generic performance questions
        for question in performance_questions:
            data.append({"text": question, "intent": "performance"})
    except Exception as e:
        print(f"Error generating performance samples: {e}")
    
    # Defects intent samples
    print("Generating defects intent samples...")
    try:
        defect_samples = list(db.defect_types.find().limit(5))
        
        defect_questions = [
            "How many defects were found yesterday?",
            "Show me the defect count by type",
            "What are the most common defects?",
            "Show defect rate for workshop 1",
            "Which defect type occurred the most last month?",
            "Show me the total defects found today",
            "What's the current defect rate?",
            "Give me stats on quality issues this week",
            "How many quality problems were reported yesterday?",
            "Show defect distribution by type"
        ]
        
        # Add samples with real values if available
        if defect_samples:
            for sample in defect_samples:
                defect_type = sample.get('name', '')
                if defect_type:
                    data.append({"text": f"How many {defect_type} defects were found?", "intent": "defects"})
                    data.append({"text": f"Show me information about {defect_type}", "intent": "defects"})
        
        # Add generic defect questions
        for question in defect_questions:
            data.append({"text": question, "intent": "defects"})
    except Exception as e:
        print(f"Error generating defect samples: {e}")
    
    # Machine failures intent samples
    print("Generating failures intent samples...")
    try:
        failure_samples = list(db["new_data.machinefailures"].find().limit(5))
        
        failure_questions = [
            "Show me the machine failures from last week",
            "How many machines broke down yesterday?",
            "What's the most common reason for machine failures?",
            "Give me the machine maintenance records",
            "Show me equipment breakdown statistics",
            "When was the last machine intervention?",
            "How often do machines fail per month?",
            "Show machine failure distribution by type",
            "What machines need maintenance soon?",
            "Give me stats on equipment downtime"
        ]
        
        # Add samples with real values if available
        if failure_samples:
            for sample in failure_samples:
                machine = sample.get('machineReference', sample.get('machine_id', ''))
                if machine:
                    data.append({"text": f"Show me failures for machine {machine}", "intent": "failures"})
                    data.append({"text": f"When did machine {machine} last break down?", "intent": "failures"})
        
        # Add generic failure questions
        for question in failure_questions:
            data.append({"text": question, "intent": "failures"})
    except Exception as e:
        print(f"Error generating failure samples: {e}")
    
    # Orders intent samples
    print("Generating orders intent samples...")
    try:
        order_samples = list(db.order_references.find().limit(5))
        
        order_questions = [
            "Show me the status of order #12345",
            "When will order #54321 be completed?",
            "List all current orders",
            "What's the status of yesterday's orders?",
            "Show me orders from last week",
            "Which orders are delayed?",
            "Give me information about the latest orders",
            "Track order #98765",
            "Show me pending orders",
            "What's the completion rate of this month's orders?"
        ]
        
        # Add samples with real values if available
        if order_samples:
            for sample in order_samples:
                order_id = sample.get('orderRef', sample.get('order_id', ''))
                if order_id:
                    data.append({"text": f"What's the status of order {order_id}?", "intent": "orders"})
                    data.append({"text": f"Give me details about order {order_id}", "intent": "orders"})
        
        # Add generic order questions
        for question in order_questions:
            data.append({"text": question, "intent": "orders"})
    except Exception as e:
        print(f"Error generating order samples: {e}")
    
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
print(df.head(10))
print(f"\nIntent distribution:\n{df['intent'].value_counts()}") 