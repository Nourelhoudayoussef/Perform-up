import os
import pandas as pd
import numpy as np
import torch
import torch.nn as nn
import torch.optim as optim
from torch.utils.data import Dataset, DataLoader
from sklearn.model_selection import train_test_split
from sklearn.feature_extraction.text import CountVectorizer
from sklearn.preprocessing import LabelEncoder
import pickle
import nltk
from nltk.tokenize import word_tokenize
from nltk.corpus import stopwords
from nltk.stem import WordNetLemmatizer
import json

# Download NLTK data if not already downloaded
try:
    nltk.download('punkt', quiet=True)
    nltk.download('stopwords', quiet=True)
    nltk.download('wordnet', quiet=True)
except Exception as e:
    print(f"Warning: Could not download NLTK data: {e}")

# Text preprocessing function
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

# Define the neural network model
class IntentClassifier(nn.Module):
    def __init__(self, input_dim, hidden_dim, output_dim, dropout_rate=0.2):
        super(IntentClassifier, self).__init__()
        self.model = nn.Sequential(
            nn.Linear(input_dim, hidden_dim),
            nn.ReLU(),
            nn.Dropout(dropout_rate),
            nn.Linear(hidden_dim, hidden_dim // 2),
            nn.ReLU(),
            nn.Dropout(dropout_rate),
            nn.Linear(hidden_dim // 2, output_dim)
        )
    
    def forward(self, x):
        return self.model(x)

# Custom dataset class
class IntentDataset(Dataset):
    def __init__(self, texts, labels):
        self.texts = texts
        self.labels = labels
    
    def __len__(self):
        return len(self.texts)
    
    def __getitem__(self, idx):
        return self.texts[idx], self.labels[idx]

# Function to train the model
def train_intent_classifier(data_path='data/intent_training_data.csv'):
    print("Loading and preprocessing data...")
    df = pd.read_csv(data_path)
    
    # Preprocess the text
    df['preprocessed_text'] = df['text'].apply(preprocess_text)
    
    # Create vocabulary and vectorize texts
    vectorizer = CountVectorizer(max_features=1000)
    X = vectorizer.fit_transform(df['preprocessed_text']).toarray()
    
    # Encode labels
    label_encoder = LabelEncoder()
    y = label_encoder.fit_transform(df['intent'])
    
    # Split data into train and validation sets
    X_train, X_val, y_train, y_val = train_test_split(X, y, test_size=0.2, random_state=42, stratify=y)
    
    # Convert to PyTorch tensors
    X_train_tensor = torch.FloatTensor(X_train)
    y_train_tensor = torch.LongTensor(y_train)
    X_val_tensor = torch.FloatTensor(X_val)
    y_val_tensor = torch.LongTensor(y_val)
    
    # Create datasets and dataloaders
    train_dataset = IntentDataset(X_train_tensor, y_train_tensor)
    val_dataset = IntentDataset(X_val_tensor, y_val_tensor)
    
    train_loader = DataLoader(train_dataset, batch_size=8, shuffle=True)
    val_loader = DataLoader(val_dataset, batch_size=8)
    
    # Initialize model
    input_dim = X_train.shape[1]  # vocabulary size
    hidden_dim = 64
    output_dim = len(label_encoder.classes_)
    
    model = IntentClassifier(input_dim, hidden_dim, output_dim)
    
    # Loss function and optimizer
    criterion = nn.CrossEntropyLoss()
    optimizer = optim.Adam(model.parameters(), lr=0.001)
    
    # Training loop
    num_epochs = 50
    best_val_loss = float('inf')
    
    print(f"Training model with {len(X_train)} examples...")
    print(f"Vocabulary size: {input_dim}")
    print(f"Number of intents: {output_dim}")
    
    for epoch in range(num_epochs):
        model.train()
        train_loss = 0.0
        
        for texts, labels in train_loader:
            # Forward pass
            outputs = model(texts)
            loss = criterion(outputs, labels)
            
            # Backward and optimize
            optimizer.zero_grad()
            loss.backward()
            optimizer.step()
            
            train_loss += loss.item()
        
        # Validation
        model.eval()
        val_loss = 0.0
        correct = 0
        total = 0
        
        with torch.no_grad():
            for texts, labels in val_loader:
                outputs = model(texts)
                loss = criterion(outputs, labels)
                val_loss += loss.item()
                
                _, predicted = torch.max(outputs.data, 1)
                total += labels.size(0)
                correct += (predicted == labels).sum().item()
        
        train_loss /= len(train_loader)
        val_loss /= len(val_loader)
        accuracy = 100 * correct / total
        
        # Print progress
        if (epoch + 1) % 10 == 0:
            print(f'Epoch {epoch+1}/{num_epochs}, Train Loss: {train_loss:.4f}, Val Loss: {val_loss:.4f}, Accuracy: {accuracy:.2f}%')
        
        # Save best model
        if val_loss < best_val_loss:
            best_val_loss = val_loss
            
            # Create models directory if it doesn't exist
            os.makedirs('models', exist_ok=True)
            
            # Save the model
            torch.save(model.state_dict(), 'models/intent_classifier.pth')
            
            # Save the vectorizer and label encoder for later use
            with open('models/vectorizer.pkl', 'wb') as f:
                pickle.dump(vectorizer, f)
            
            with open('models/label_encoder.pkl', 'wb') as f:
                pickle.dump(label_encoder, f)
            
            # Save vocabulary and labels for reference
            metadata = {
                'intent_labels': label_encoder.classes_.tolist(),
                'vocab_size': input_dim,
                'hidden_dim': hidden_dim,
                'output_dim': output_dim
            }
            with open('models/model_metadata.json', 'w') as f:
                json.dump(metadata, f, indent=2)
    
    # Final evaluation
    model.eval()
    correct = 0
    total = 0
    
    with torch.no_grad():
        for texts, labels in val_loader:
            outputs = model(texts)
            _, predicted = torch.max(outputs.data, 1)
            total += labels.size(0)
            correct += (predicted == labels).sum().item()
    
    final_accuracy = 100 * correct / total
    print(f'Final validation accuracy: {final_accuracy:.2f}%')
    print(f'Model saved to models/intent_classifier.pth')
    
    return model, vectorizer, label_encoder

if __name__ == "__main__":
    # Train the model
    train_intent_classifier() 