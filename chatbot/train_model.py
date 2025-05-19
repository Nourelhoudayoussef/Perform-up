#!/usr/bin/env python3
"""
Training script for the chatbot intent classifier.
This script runs the data extraction and model training in sequence.
"""

import os
import subprocess
import argparse
import time
import matplotlib
matplotlib.use('Agg')  # Use non-interactive backend for matplotlib

def run_command(command, description):
    """Run a shell command and print output"""
    print(f"\n{'='*80}")
    print(f"RUNNING: {description}")
    print(f"COMMAND: {command}")
    print(f"{'='*80}\n")
    
    start_time = time.time()
    result = subprocess.run(command, shell=True, text=True)
    elapsed_time = time.time() - start_time
    
    print(f"\n{'='*80}")
    print(f"FINISHED: {description}")
    print(f"TIME: {elapsed_time:.2f} seconds")
    print(f"EXIT CODE: {result.returncode}")
    print(f"{'='*80}\n")
    
    return result.returncode == 0

def main():
    parser = argparse.ArgumentParser(description="Train the chatbot intent classifier")
    parser.add_argument('--skip-data-extraction', action='store_true', 
                        help='Skip the data extraction step and use existing training data')
    parser.add_argument('--no-augment', action='store_true',
                        help='Disable data augmentation during training')
    parser.add_argument('--use-count', action='store_true',
                        help='Use CountVectorizer instead of TF-IDF')
    parser.add_argument('--max-features', type=int, default=2000,
                        help='Maximum number of features for vectorization')
    
    args = parser.parse_args()
    
    # Create necessary directories
    os.makedirs('data', exist_ok=True)
    os.makedirs('models', exist_ok=True)
    
    # Step 1: Extract training data from MongoDB
    if not args.skip_data_extraction:
        if not run_command('python data_extractor.py', 'Extracting training data from MongoDB'):
            print("Data extraction failed. Exiting.")
            return False
    else:
        print("Skipping data extraction step as requested.")
    
    # Step 2: Train the intent classifier model
    train_cmd = 'python intent_classifier.py'
    
    if args.no_augment:
        train_cmd += ' --no-augment'
    if args.use_count:
        train_cmd += ' --use-count'
    
    train_cmd += f' --max-features {args.max_features}'
    
    if not run_command(train_cmd, 'Training intent classifier model'):
        print("Model training failed. Exiting.")
        return False
    
    # Step 3: Test the model with some example queries
    if not run_command('python predict_intent.py', 'Testing intent prediction with examples'):
        print("Model testing failed, but continuing anyway.")
    
    print("\nTraining completed successfully!")
    print("The intent classifier model is now ready to use in the chatbot.")
    print("You can run the Flask app with: python app.py")
    
    return True

if __name__ == "__main__":
    main() 