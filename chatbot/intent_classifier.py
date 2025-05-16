import os
import pandas as pd
import numpy as np
import torch
import torch.nn as nn
import torch.optim as optim
from torch.utils.data import Dataset, DataLoader
from sklearn.model_selection import train_test_split
from sklearn.feature_extraction.text import CountVectorizer, TfidfVectorizer
from sklearn.preprocessing import LabelEncoder
import pickle
import nltk
from nltk.tokenize import word_tokenize
from nltk.corpus import stopwords
from nltk.stem import WordNetLemmatizer
import json
import matplotlib.pyplot as plt
from sklearn.metrics import confusion_matrix, classification_report
import seaborn as sns
import re
import random

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

# Text preprocessing function
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

# Define an improved neural network model with batch normalization and more layers
class IntentClassifier(nn.Module):
    def __init__(self, input_dim, hidden_dim, output_dim, dropout_rate=0.3):
        super(IntentClassifier, self).__init__()
        self.model = nn.Sequential(
            nn.Linear(input_dim, hidden_dim),
            nn.ReLU(),
            nn.Dropout(dropout_rate),
            
            nn.Linear(hidden_dim, hidden_dim // 2),
            nn.ReLU(),
            nn.Dropout(dropout_rate),
            
            nn.Linear(hidden_dim // 2, hidden_dim // 4),
            nn.ReLU(),
            nn.Dropout(dropout_rate),
            
            nn.Linear(hidden_dim // 4, output_dim)
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

# Generate augmented training data from existing examples
def augment_training_data(df, augmentation_factor=1.5):
    """Augment the training data by creating variations of existing examples"""
    print(f"Augmenting training data with factor {augmentation_factor}...")
    
    augmented_data = []
    original_count = len(df)
    target_count = int(original_count * augmentation_factor)
    
    # Define operations for text augmentation
    def swap_words(text):
        words = text.split()
        if len(words) <= 3:  # Skip very short texts
            return text
        i, j = random.sample(range(len(words)), 2)
        words[i], words[j] = words[j], words[i]
        return ' '.join(words)
    
    def drop_word(text):
        words = text.split()
        if len(words) <= 3:  # Skip very short texts
            return text
        i = random.randint(0, len(words) - 1)
        words.pop(i)
        return ' '.join(words)
    
    def add_noise(text):
        noise_words = ['the', 'please', 'um', 'uh', 'well', 'so', 'like', 'actually']
        words = text.split()
        if len(words) == 0:
            return text
        i = random.randint(0, len(words))
        words.insert(i, random.choice(noise_words))
        return ' '.join(words)
    
    augmentation_ops = [swap_words, drop_word, add_noise]
    
    # Generate augmented examples
    while len(augmented_data) < (target_count - original_count):
        # Randomly select an example
        idx = random.randint(0, len(df) - 1)
        text = df.iloc[idx]['text']
        intent = df.iloc[idx]['intent']
        
        # Apply random augmentation
        op = random.choice(augmentation_ops)
        new_text = op(text)
        
        if new_text != text:
            augmented_data.append({'text': new_text, 'intent': intent})
    
    # Create DataFrame with augmented data
    if augmented_data:
        aug_df = pd.DataFrame(augmented_data)
        combined_df = pd.concat([df, aug_df], ignore_index=True)
        print(f"Added {len(aug_df)} augmented examples. New dataset size: {len(combined_df)}")
        return combined_df
    
    return df

# Function to plot training history
def plot_training_history(history, save_path='models/training_history.png'):
    plt.figure(figsize=(12, 4))
    
    plt.subplot(1, 2, 1)
    plt.plot(history['train_loss'], label='Train Loss')
    plt.plot(history['val_loss'], label='Validation Loss')
    plt.xlabel('Epoch')
    plt.ylabel('Loss')
    plt.legend()
    plt.title('Training and Validation Loss')
    
    plt.subplot(1, 2, 2)
    plt.plot(history['val_accuracy'], label='Validation Accuracy')
    plt.xlabel('Epoch')
    plt.ylabel('Accuracy (%)')
    plt.legend()
    plt.title('Validation Accuracy')
    
    plt.tight_layout()
    plt.savefig(save_path)
    print(f"Training history plot saved to {save_path}")

# Function to plot confusion matrix
def plot_confusion_matrix(y_true, y_pred, label_encoder, save_path='models/confusion_matrix.png'):
    # Get class names
    class_names = label_encoder.classes_
    
    # Compute confusion matrix
    cm = confusion_matrix(y_true, y_pred)
    
    plt.figure(figsize=(10, 8))
    sns.heatmap(cm, annot=True, fmt='d', cmap='Blues', xticklabels=class_names, yticklabels=class_names)
    plt.xlabel('Predicted')
    plt.ylabel('True')
    plt.title('Confusion Matrix')
    plt.tight_layout()
    plt.savefig(save_path)
    print(f"Confusion matrix saved to {save_path}")

# Function to train the model
def train_intent_classifier(data_path='data/intent_training_data.csv', augment=True, use_tfidf=True, max_features=2000):
    print("Loading and preprocessing data...")
    df = pd.read_csv(data_path)
    
    # Augment training data if requested
    if augment and len(df) > 0:
        df = augment_training_data(df)
    
    # Preprocess the text
    df['preprocessed_text'] = df['text'].apply(preprocess_text)
    
    # Create vocabulary and vectorize texts
    if use_tfidf:
        print(f"Using TF-IDF vectorization with max_features={max_features}")
        vectorizer = TfidfVectorizer(max_features=max_features, ngram_range=(1, 2))
    else:
        print(f"Using Count vectorization with max_features={max_features}")
        vectorizer = CountVectorizer(max_features=max_features, ngram_range=(1, 2))
        
    X = vectorizer.fit_transform(df['preprocessed_text']).toarray()
    
    # Print vocabulary size and some example features
    print(f"Vocabulary size: {len(vectorizer.get_feature_names_out())}")
    print("Sample features:", vectorizer.get_feature_names_out()[:10])
    
    # Encode labels
    label_encoder = LabelEncoder()
    y = label_encoder.fit_transform(df['intent'])
    
    # Print class distribution
    unique_intents, counts = np.unique(y, return_counts=True)
    print("\nClass distribution:")
    for i, intent in enumerate(label_encoder.classes_):
        print(f"{intent}: {counts[i]} samples")
    
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
    
    batch_size = 16  # Increased batch size for better stability
    train_loader = DataLoader(train_dataset, batch_size=batch_size, shuffle=True)
    val_loader = DataLoader(val_dataset, batch_size=batch_size)
    
    # Initialize model
    input_dim = X_train.shape[1]  # vocabulary size
    hidden_dim = 128  # Increased hidden dimension
    output_dim = len(label_encoder.classes_)
    
    model = IntentClassifier(input_dim, hidden_dim, output_dim)
    
    # Loss function and optimizer
    criterion = nn.CrossEntropyLoss()
    optimizer = optim.Adam(model.parameters(), lr=0.001, weight_decay=1e-5)  # Added weight decay
    scheduler = optim.lr_scheduler.ReduceLROnPlateau(optimizer, mode='min', factor=0.5, patience=5)
    
    # Training loop
    num_epochs = 100
    best_val_loss = float('inf')
    patience = 10  # Early stopping patience
    patience_counter = 0
    
    # For tracking training progress
    history = {
        'train_loss': [],
        'val_loss': [],
        'val_accuracy': []
    }
    
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
        
        y_true = []
        y_pred = []
        
        with torch.no_grad():
            for texts, labels in val_loader:
                outputs = model(texts)
                loss = criterion(outputs, labels)
                val_loss += loss.item()
                
                _, predicted = torch.max(outputs.data, 1)
                total += labels.size(0)
                correct += (predicted == labels).sum().item()
                
                # Store true and predicted labels for confusion matrix
                y_true.extend(labels.cpu().numpy())
                y_pred.extend(predicted.cpu().numpy())
        
        train_loss /= len(train_loader)
        val_loss /= len(val_loader)
        accuracy = 100 * correct / total
        
        # Update history
        history['train_loss'].append(train_loss)
        history['val_loss'].append(val_loss)
        history['val_accuracy'].append(accuracy)
        
        # Update learning rate scheduler
        old_lr = optimizer.param_groups[0]['lr']
        scheduler.step(val_loss)
        new_lr = optimizer.param_groups[0]['lr']
        if new_lr != old_lr:
            print(f'Learning rate reduced from {old_lr} to {new_lr}')
        
        # Print progress
        if (epoch + 1) % 5 == 0:
            print(f'Epoch {epoch+1}/{num_epochs}, Train Loss: {train_loss:.4f}, Val Loss: {val_loss:.4f}, Accuracy: {accuracy:.2f}%')
        
        # Save best model and check for early stopping
        if val_loss < best_val_loss:
            best_val_loss = val_loss
            patience_counter = 0
            
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
                'output_dim': output_dim,
                'vectorizer_type': 'tfidf' if use_tfidf else 'count',
                'max_features': max_features,
                'feature_names': vectorizer.get_feature_names_out().tolist()
            }
            with open('models/model_metadata.json', 'w') as f:
                json.dump(metadata, f, indent=2)
        else:
            patience_counter += 1
            if patience_counter >= patience:
                print(f'Early stopping after {epoch+1} epochs with no improvement')
                break
    
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
    
    # Plot and save training history
    plot_training_history(history)
    
    # Plot and save confusion matrix
    plot_confusion_matrix(y_true, y_pred, label_encoder)
    
    # Print classification report
    print("\nClassification Report:")
    print(classification_report(y_true, y_pred, target_names=label_encoder.classes_))
    
    return model, vectorizer, label_encoder

if __name__ == "__main__":
    import argparse
    
    parser = argparse.ArgumentParser(description='Train intent classifier model')
    parser.add_argument('--data', type=str, default='data/intent_training_data.csv', help='Path to training data CSV')
    parser.add_argument('--no-augment', action='store_false', dest='augment', help='Disable data augmentation')
    parser.add_argument('--use-count', action='store_false', dest='use_tfidf', help='Use CountVectorizer instead of TF-IDF')
    parser.add_argument('--max-features', type=int, default=2000, help='Maximum number of features for vectorization')
    
    args = parser.parse_args()
    
    # Train the model with specified parameters
    train_intent_classifier(
        data_path=args.data,
        augment=args.augment,
        use_tfidf=args.use_tfidf,
        max_features=args.max_features
    ) 