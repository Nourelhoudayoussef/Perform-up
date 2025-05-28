import torch
import pickle
import os
import json
import re
import numpy as np
from nltk.tokenize import word_tokenize
from nltk.corpus import stopwords
from nltk.stem import WordNetLemmatizer
import nltk

# Download NLTK data if not already downloaded
try:
    nltk.download('punkt', quiet=True)
    nltk.download('stopwords', quiet=True)
    nltk.download('wordnet', quiet=True)
except Exception as e:
    print(f"Warning: Could not download NLTK data: {e}")

# Entity extraction patterns
ENTITY_PATTERNS = {
    'workshop': r'workshop\s*(\d+)',
    'machine': r'machine\s+(?:id|reference|ref|number)?\s*([a-zA-Z0-9\-]+)',
    'defect_type': r'(stain|tear|size issue|color issue|missing component|loose thread|fabric damage|seam defect|button defect|zipper issue|print defect|quality issue)',
    'order': r'order\s*(?:reference|ref)?\s*#?\s*(\d+)',
    'date': r'(\d{4}-\d{2}-\d{2})'
}

# Define the neural network model - should match the one used in training
class IntentClassifier(torch.nn.Module):
    def __init__(self, input_dim, hidden_dim, output_dim, dropout_rate=0.3):
        super(IntentClassifier, self).__init__()
        self.model = torch.nn.Sequential(
            torch.nn.Linear(input_dim, hidden_dim),
            torch.nn.ReLU(),
            torch.nn.Dropout(dropout_rate),
            
            torch.nn.Linear(hidden_dim, hidden_dim // 2),
            torch.nn.ReLU(),
            torch.nn.Dropout(dropout_rate),
            
            torch.nn.Linear(hidden_dim // 2, hidden_dim // 4),
            torch.nn.ReLU(),
            torch.nn.Dropout(dropout_rate),
            
            torch.nn.Linear(hidden_dim // 4, output_dim)
        )
    
    def forward(self, x):
        return self.model(x)

def preprocess_text(text, extract_entities=False):
    """Preprocess text for the model with optional entity extraction"""
    # Convert to lowercase
    text = text.lower()
    
    # Extract entities if requested
    entities = {}
    if extract_entities:
        for entity_type, pattern in ENTITY_PATTERNS.items():
            matches = re.finditer(pattern, text, re.IGNORECASE)
            for match in matches:
                if entity_type not in entities:
                    entities[entity_type] = []
                entities[entity_type].append(match.group(1))
    
    # Tokenize
    tokens = word_tokenize(text)
    
    # Remove stopwords and punctuation
    stop_words = set(stopwords.words('english'))
    # Keep some important words that might be stopwords but are relevant for our domain
    domain_relevant = {'what', 'when', 'where', 'how', 'which', 'why', 'who', 'show', 'list', 'find'}
    stop_words = stop_words - domain_relevant
    
    tokens = [t for t in tokens if (t.isalpha() and t not in stop_words) or t.isdigit()]
    
    # Lemmatize
    lemmatizer = WordNetLemmatizer()
    tokens = [lemmatizer.lemmatize(t) for t in tokens]
    
    # Join tokens back to text
    processed_text = ' '.join(tokens)
    
    if extract_entities:
        return processed_text, entities
    return processed_text

class IntentPredictor:
    def __init__(self, model_dir='models', confidence_threshold=0.5):
        self.model_dir = model_dir
        self.model = None
        self.vectorizer = None
        self.label_encoder = None
        self.metadata = None
        self.intent_labels = None
        self.confidence_threshold = confidence_threshold
        
        try:
            self.load_model()
        except Exception as e:
            print(f"Error loading intent classifier model: {e}")
            
    def load_model(self):
        # Load model metadata
        with open(os.path.join(self.model_dir, 'model_metadata.json'), 'r') as f:
            self.metadata = json.load(f)
        
        # Get model parameters
        input_dim = self.metadata.get('vocab_size')
        hidden_dim = self.metadata.get('hidden_dim')
        output_dim = self.metadata.get('output_dim')
        self.intent_labels = self.metadata.get('intent_labels')
        
        # Load vectorizer
        with open(os.path.join(self.model_dir, 'vectorizer.pkl'), 'rb') as f:
            self.vectorizer = pickle.load(f)
            
        # Load label encoder
        with open(os.path.join(self.model_dir, 'label_encoder.pkl'), 'rb') as f:
            self.label_encoder = pickle.load(f)
            
        # Initialize and load model
        self.model = IntentClassifier(input_dim, hidden_dim, output_dim)
        self.model.load_state_dict(torch.load(os.path.join(self.model_dir, 'intent_classifier.pth')))
        self.model.eval()
        
        print(f"Loaded intent classifier model with {output_dim} intents: {self.intent_labels}")
        
    def extract_entities(self, text):
        """Extract structured entities from the text"""
        _, entities = preprocess_text(text, extract_entities=True)
        return entities
    
    def get_keyword_matches(self, text):
        """Get keyword matches for fallback intent detection"""
        text = text.lower()
        keyword_scores = {
            'performance': 0,
            'defects': 0,
            'failures': 0,
            'orders': 0,
            'user_info': 0  
        }
        
        # Define keywords for each intent
        keywords = {
            'performance': ['production', 'output', 'efficiency', 'performance', 'produced', 'units', 'productivity', 'yield'],
            'defects': ['defect', 'quality', 'issue', 'problem', 'rejection', 'fault', 'error', 'defective'],
            'failures': ['machine', 'failure', 'breakdown', 'maintenance', 'repair', 'equipment', 'malfunction'],
            'orders': ['order', 'delivery', 'shipment', 'status', 'tracking', 'shipped', 'completed'],
            'user_info': ['supervisor', 'technician', 'manager', 'user', 'employee', 'staff', 'personnel', 'operator']
        }
        
        # Count matches for each intent
        for intent, words in keywords.items():
            for word in words:
                if re.search(r'\b' + re.escape(word) + r'\b', text):
                    keyword_scores[intent] += 1
        
        return keyword_scores
    
    def predict(self, text, extract_entities=True):
        """Predict intent from text with confidence score and optional entity extraction"""
        if not self.model or not self.vectorizer or not self.label_encoder:
            return {"intent": "unknown", "confidence": 0.0, "entities": {}}
        
        try:
            # Preprocess the text and optionally extract entities
            entities = {}
            if extract_entities:
                preprocessed_text, entities = preprocess_text(text, extract_entities=True)
            else:
                preprocessed_text = preprocess_text(text)
            
            # Vectorize the text
            text_vector = self.vectorizer.transform([preprocessed_text]).toarray()
            
            # Convert to tensor
            text_tensor = torch.FloatTensor(text_vector)
            
            # Predict
            with torch.no_grad():
                output = self.model(text_tensor)
                
                # Get probabilities
                probabilities = torch.nn.functional.softmax(output, dim=1)
                
                # Get all class probabilities
                all_probs = probabilities.cpu().numpy()[0]
                
                # Get the prediction and confidence
                confidence, predicted_idx = torch.max(probabilities, 1)
                
                # Convert to numpy for easier handling
                predicted_idx = predicted_idx.item()
                confidence = confidence.item()
                
                # Get the predicted label
                predicted_intent = self.label_encoder.inverse_transform([predicted_idx])[0]
                
                # If confidence is below threshold, use keyword matching as fallback
                if confidence < self.confidence_threshold:
                    print(f"Low confidence ({confidence:.4f}) for intent: {predicted_intent}")
                    
                    # Try keyword-based fallback
                    keyword_scores = self.get_keyword_matches(text)
                    max_score = max(keyword_scores.values())
                    
                    # Only use keyword fallback if we found some matches
                    if max_score > 0:
                        fallback_intent = max(keyword_scores.items(), key=lambda x: x[1])[0]
                        print(f"Fallback to keyword match: {fallback_intent}, score: {max_score}")
                        
                        # Use the higher of model confidence or a baseline for keywords
                        keyword_confidence = min(0.6, 0.3 + (max_score / 10))
                        
                        # If the keyword confidence is higher, use the keyword intent
                        if keyword_confidence > confidence:
                            predicted_intent = fallback_intent
                            confidence = keyword_confidence
                
                # Prepare the full prediction result
                result = {
                    "intent": predicted_intent,
                    "confidence": confidence,
                    "entities": entities,
                    "all_intents": {
                        self.intent_labels[i]: float(prob) 
                        for i, prob in enumerate(all_probs)
                    }
                }
                
                return result
                
        except Exception as e:
            print(f"Error during intent prediction: {e}")
            return {"intent": "unknown", "confidence": 0.0, "entities": {}}

# Example usage
if __name__ == "__main__":
    # Test the predictor with a few examples
    predictor = IntentPredictor()
    
    test_questions = [
        "What is the production for workshop 1?",
        "How many defects were found yesterday?",
        "Show me machine failures from last week",
        "What's the status of order #12345?",
        "Tell me about the weather today",  # This should be unknown
        "How many stain defects were found in workshop 2 last month?",  # Complex with entities
        "Show me loose thread issues in January"  # Specific defect type entity
    ]
    
    for question in test_questions:
        result = predictor.predict(question)
        print(f"Question: {question}")
        print(f"Predicted Intent: {result['intent']}")
        print(f"Confidence: {result['confidence']:.4f}")
        
        if result['entities']:
            print(f"Extracted Entities: {result['entities']}")
        
        # Show all intent probabilities
        print("All Intents:")
        for intent, prob in sorted(result['all_intents'].items(), key=lambda x: x[1], reverse=True):
            print(f"  {intent}: {prob:.4f}")
        
        print() 