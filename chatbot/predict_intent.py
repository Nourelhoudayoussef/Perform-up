import torch
import pickle
import os
import json
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

# Define the neural network model - should match the one used in training
class IntentClassifier(torch.nn.Module):
    def __init__(self, input_dim, hidden_dim, output_dim, dropout_rate=0.2):
        super(IntentClassifier, self).__init__()
        self.model = torch.nn.Sequential(
            torch.nn.Linear(input_dim, hidden_dim),
            torch.nn.ReLU(),
            torch.nn.Dropout(dropout_rate),
            torch.nn.Linear(hidden_dim, hidden_dim // 2),
            torch.nn.ReLU(),
            torch.nn.Dropout(dropout_rate),
            torch.nn.Linear(hidden_dim // 2, output_dim)
        )
    
    def forward(self, x):
        return self.model(x)

def preprocess_text(text):
    """Preprocess text for the model"""
    # Convert to lowercase
    text = text.lower()
    
    # Tokenize
    tokens = word_tokenize(text)
    
    # Remove stopwords and punctuation
    stop_words = set(stopwords.words('english'))
    tokens = [t for t in tokens if t.isalpha() and t not in stop_words]
    
    # Lemmatize
    lemmatizer = WordNetLemmatizer()
    tokens = [lemmatizer.lemmatize(t) for t in tokens]
    
    return ' '.join(tokens)

class IntentPredictor:
    def __init__(self, model_dir='models'):
        self.model_dir = model_dir
        self.model = None
        self.vectorizer = None
        self.label_encoder = None
        self.metadata = None
        self.intent_labels = None
        self.confidence_threshold = 0.5
        
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
    
    def predict(self, text):
        """Predict intent from text"""
        # Preprocess the text
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
            confidence, predicted_idx = torch.max(probabilities, 1)
            
            # Convert to numpy for easier handling
            predicted_idx = predicted_idx.item()
            confidence = confidence.item()
            
            # Get the predicted label
            predicted_intent = self.label_encoder.inverse_transform([predicted_idx])[0]
            
            # Check confidence threshold
            if confidence < self.confidence_threshold:
                return {"intent": "unknown", "confidence": confidence}
            
            return {"intent": predicted_intent, "confidence": confidence}

# Example usage
if __name__ == "__main__":
    # Test the predictor with a few examples
    predictor = IntentPredictor()
    
    test_questions = [
        "What is the production for workshop 1?",
        "How many defects were found yesterday?",
        "Show me machine failures from last week",
        "What's the status of order #12345?",
        "Tell me about the weather today"  # This should be unknown
    ]
    
    for question in test_questions:
        result = predictor.predict(question)
        print(f"Question: {question}")
        print(f"Predicted Intent: {result['intent']}")
        print(f"Confidence: {result['confidence']:.4f}")
        print() 