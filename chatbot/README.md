# Clothing Factory Chatbot with PyTorch Intent Classification

This project implements a chatbot for a clothing factory that uses PyTorch for intent classification. The chatbot can understand natural language questions about production performance, defects, machine failures, and orders by querying MongoDB collections.

## Features

- **PyTorch-based Intent Classification**: Uses a neural network to classify user intents
- **Entity Extraction**: Automatically extracts entities like defect types, workshop numbers, etc.
- **Natural Language Understanding**: Handles variations in how users phrase questions
- **Fallback Mechanisms**: Falls back to keyword matching when confidence is low
- **MongoDB Integration**: Queries multiple collections based on intent
- **Specialized Handlers**: Custom handlers for specific query types (defects, comparisons, etc.)

## Setup

### Prerequisites

- Python 3.8+
- MongoDB connection (configured in the app)
- Required Python packages:

```
pip install flask flask-cors pymongo torch nltk scikit-learn numpy matplotlib seaborn pandas
```

### Training the Model

1. Extract training data from MongoDB:
   ```
   python data_extractor.py
   ```

2. Train the intent classifier:
   ```
   python intent_classifier.py
   ```

3. Or use the combined training script:
   ```
   python train_model.py
   ```

   Options:
   - `--skip-data-extraction`: Skip the data extraction step
   - `--no-augment`: Disable data augmentation
   - `--use-count`: Use CountVectorizer instead of TF-IDF
   - `--max-features N`: Set maximum features for vectorization (default: 2000)

### Running the Chatbot

Start the Flask server:
```
python app.py
```

The chatbot will be available at `http://localhost:5001/chatbot` as a POST endpoint.

## How It Works

1. **Intent Classification**: The PyTorch model classifies the user's question into one of these intents:
   - `performance`: Questions about production performance
   - `defects`: Questions about defects and quality issues
   - `failures`: Questions about machine failures and maintenance
   - `orders`: Questions about order status and tracking

2. **Entity Extraction**: The system extracts relevant entities:
   - Workshop numbers
   - Machine IDs
   - Defect types
   - Order references
   - Dates

3. **Query Generation**: Based on the intent and entities, the system builds MongoDB queries

4. **Response Formatting**: Results are formatted into readable responses

## Example Queries

- "What is the production performance for workshop 1 last month?"
- "How many defects were found yesterday?"
- "Show me machine failures from last week"
- "What's the status of order #12345?"
- "What are the main defect types?"
- "How many stain defects were found in workshop 2?"
- "Compare production between workshop 1 and 2"
- "What's the efficiency rate per hour?"

## Extending the Model

To add new intents or improve existing ones:

1. Add more training examples in `data_extractor.py`
2. Retrain the model using `python train_model.py`
3. Update entity patterns in `predict_intent.py` if needed
4. Add specialized handlers in `app.py` for new intents

## Troubleshooting

- **Low confidence predictions**: Add more diverse training examples
- **Entity extraction issues**: Update the entity patterns in `ENTITY_PATTERNS`
- **MongoDB connection issues**: Check connection string and network
- **Missing dependencies**: Install required packages with pip 