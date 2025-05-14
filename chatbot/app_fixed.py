from flask import Flask, request
from flask_cors import CORS
from pymongo import MongoClient
import re
from datetime import datetime, timedelta
import nltk
from nltk.tokenize import word_tokenize
from nltk.corpus import stopwords
from nltk.stem import WordNetLemmatizer
import numpy as np
import time  # Add this import for sleep functionality
from predict_intent import IntentPredictor  # Import our new intent predictor

# Download required NLTK data - only what we actually need
try:
    nltk.download('punkt')
    nltk.download('stopwords')
    nltk.download('wordnet')
except Exception as e:
    print(f"Warning: Could not download NLTK data: {e}")

app = Flask(__name__)
# Enable CORS for all routes and origins
CORS(app, resources={r"/*": {"origins": "*"}})

# MongoDB connection with retry logic
def connect_to_mongodb(max_retries=5, retry_delay=5):
    """Connect to MongoDB with improved retry logic and timeouts"""
    for attempt in range(1, max_retries + 1):
        try:
            print(f"MongoDB connection attempt {attempt}/{max_retries}...")
            client = MongoClient("mongodb+srv://nour:nour123@cluster0.vziu9.mongodb.net/clothing_factory?retryWrites=true&w=majority", 
                              serverSelectionTimeoutMS=15000,  # Increased timeout
                              connectTimeoutMS=15000,          # Increased timeout
                              socketTimeoutMS=30000)           # Increased socket timeout
            
            # Verify connection works with ping
            client.admin.command('ping')
            db = client["clothing_factory"]
            
            # Get collection names for verification
            collections = db.list_collection_names()
            print(f"MongoDB connection successful! Found {len(collections)} collections")
            print(f"Available collections: {collections}")
            
            return client, db, True, collections
            
        except Exception as e:
            print(f"MongoDB connection attempt {attempt} failed: {str(e)}")
            if attempt < max_retries:
                print(f"Retrying in {retry_delay} seconds...")
                time.sleep(retry_delay)
                # Increase delay for next attempt (exponential backoff)
                retry_delay *= 1.5
            else:
                print("Maximum retry attempts reached. Using fallback mode.")
                return None, None, False, []

# Try to connect with retries
client, db, mongodb_available, available_collections = connect_to_mongodb()

# Initialize the intent predictor
intent_predictor = IntentPredictor()

def preprocess_text(text):
    """Preprocess text with graceful fallback if POS tagging fails"""
    tokens = word_tokenize(text.lower())
    stop_words = set(stopwords.words('english'))
    lemmatizer = WordNetLemmatizer()
    tokens = [lemmatizer.lemmatize(w) for w in tokens if w.isalpha() and w not in stop_words]
    
    # Skip POS tagging entirely as it's not critical for our application
    # Return just the tokens with dummy POS tags
    return tokens, [(token, "UNKNOWN") for token in tokens]

def extract_date_info(text):
    """Extract and normalize date information from text"""
    today = datetime.now()
    
    print(f"Extracting date info from: '{text}'")
    
    # Extract explicit dates (YYYY-MM-DD)
    date_match = re.search(r'\b(\d{4}-\d{2}-\d{2})\b', text)
    if date_match:
        return {'type': 'exact_date', 'value': date_match.group(1)}
    
    # Detect 'this month' specifically 
    this_month_pattern = r'\bthis\s+month\b'
    if re.search(this_month_pattern, text, re.IGNORECASE):
        first_day = today.replace(day=1)
        last_day = today
        
        return {
            'type': 'relative_date',
            'value': {
                'start': first_day.strftime('%Y-%m-%d'),
                'end': last_day.strftime('%Y-%m-%d')
            },
            'description': 'this month'
        }
    
    # Handle relative dates
    relative_dates = {
        'today': today.strftime('%Y-%m-%d'),
        'yesterday': (today - timedelta(days=1)).strftime('%Y-%m-%d'),
        'this week': {
            'start': (today - timedelta(days=today.weekday())).strftime('%Y-%m-%d'),
            'end': today.strftime('%Y-%m-%d')
        }
    }
    
    for key_phrase, date_value in relative_dates.items():
        if key_phrase in text.lower():
            return {'type': 'relative_date', 'value': date_value, 'description': key_phrase}
    
    # Handle 'last month' specifically
    last_month_pattern = r'\blast\s+month\b|\bprevious\s+month\b|\ba\s+month\s+ago\b'
    if re.search(last_month_pattern, text, re.IGNORECASE):
        first_day = (today.replace(day=1) - timedelta(days=1)).replace(day=1)
        last_day = today.replace(day=1) - timedelta(days=1)
        
        return {
            'type': 'relative_date',
            'value': {
                'start': first_day.strftime('%Y-%m-%d'),
                'end': last_day.strftime('%Y-%m-%d')
            },
            'description': 'last month'
        }
    
    # Simple month name pattern with case-insensitivity (more permissive)
    month_names = ['january', 'february', 'march', 'april', 'may', 'june', 'july', 
                  'august', 'september', 'october', 'november', 'december']
    
    # First check for month with year (e.g., "May 2025")
    for i, month_name in enumerate(month_names, 1):
        # More permissive pattern: month name followed by optional spaces and a 4-digit year
        month_year_pattern = rf'\b{month_name}\s*(\d{{4}})\b'
        match = re.search(month_year_pattern, text.lower())
        
        if match:
            print(f"Found month with year: {month_name} {match.group(1)}")
            year = int(match.group(1))
            month_num = i
            
            # Create date range for the entire month
            first_day = datetime(year, month_num, 1)
            
            # Calculate the last day of the month
            if month_num == 12:
                last_day = datetime(year + 1, 1, 1) - timedelta(days=1)
            else:
                last_day = datetime(year, month_num + 1, 1) - timedelta(days=1)
            
            return {
                'type': 'relative_date',
                'value': {
                    'start': first_day.strftime('%Y-%m-%d'),
                    'end': last_day.strftime('%Y-%m-%d')
                },
                'description': f'{month_name} {year}'
            }
    
    # Then check for just month name without year
    for i, month_name in enumerate(month_names, 1):
        if f" {month_name} " in f" {text.lower()} ":
            print(f"Found month without year: {month_name}")
            month_num = i
            
            # Decide which year to use
            year = today.year
            if month_num > today.month:
                # If the specified month is in the future, assume previous year
                year = today.year - 1
            
            # Create date range for the entire month
            first_day = datetime(year, month_num, 1)
            
            # Calculate the last day of the month
            if month_num == 12:
                last_day = datetime(year + 1, 1, 1) - timedelta(days=1)
            else:
                last_day = datetime(year, month_num + 1, 1) - timedelta(days=1)
            
            return {
                'type': 'relative_date',
                'value': {
                    'start': first_day.strftime('%Y-%m-%d'),
                    'end': last_day.strftime('%Y-%m-%d')
                },
                'description': f'{month_name} {year}'
            }
    
    # No date info found
    print("No date information found in the text")
    return None

def extract_math_operation(text):
    """Extract mathematical operation from the question"""
    math_patterns = {
        'sum': r'sum|total|add(?:ition)?',
        'average': r'average|mean|avg',
        'percentage': r'percentage|percent|%',
        'difference': r'difference|change|gap',
        'trend': r'trend|movement|progression',
        'rate': r'rate|speed|pace|per|hour|day|productivity',
        'distribution': r'distribution|spread|range|statistics',
        'compare': r'compare|versus|vs|against',
        'efficiency': r'efficiency|productivity|performance'
    }
    
    # Check for specific time-based calculations
    time_patterns = {
        'hourly': r'per hour|hourly|each hour',
        'daily': r'per day|daily|each day',
        'monthly': r'per month|monthly|each month',
        'yearly': r'per year|yearly|annual'
    }
    
    operations = []
    
    # Check for math operations
    for op, pattern in math_patterns.items():
        if re.search(pattern, text, re.IGNORECASE):
            operations.append(op)
    
    # If no specific operation is found but there's a time pattern, assume it's a rate calculation
    if not operations:
        for time_unit, pattern in time_patterns.items():
            if re.search(pattern, text, re.IGNORECASE):
                operations.append('rate')
                break
    
    # If efficiency and rate are both detected, prioritize 'rate'
    if 'efficiency' in operations and 'rate' in operations:
        operations.remove('efficiency')
    
    # If asking for statistics or numbers without specific operation, default to 'sum'
    if not operations and re.search(r'show|display|get|find|what|how many|calculate', text, re.IGNORECASE):
        operations.append('sum')
    
    return operations[0] if operations else None

def predict_intent(text):
    """Predict the intent using the PyTorch model"""
    try:
        prediction = intent_predictor.predict(text)
        intent = prediction['intent']
        confidence = prediction['confidence']
        
        print(f"Intent prediction: {intent}, Confidence: {confidence:.4f}")
        
        # Map the predicted intent to our internal metrics
        intent_to_metrics = {
            'performance': ['production', 'efficiency'],
            'defects': ['defects'],
            'failures': ['failures'],
            'orders': ['order']
        }
        
        # Expand mappings for improved intent detection
        intent_context_clues = {
            'performance': ['production', 'efficiency', 'output', 'produced', 'productivity', 'performance', 'rate'],
            'defects': ['defect', 'quality', 'issue', 'problem', 'loose thread', 'mistake', 'error'],
            'failures': ['failure', 'machine', 'breakdown', 'maintenance', 'intervention', 'repair', 'malfunction'],
            'orders': ['order', 'delivery', 'shipment', 'customer', 'client']
        }
        
        # If confidence is too low or intent is unknown, try to detect intent from keywords
        if intent == 'unknown' or confidence < 0.4:
            print("Low confidence prediction, checking for context clues")
            text_lower = text.lower()
            
            best_match = None
            max_matches = 0
            
            for intent_type, clues in intent_context_clues.items():
                matches = sum(1 for clue in clues if clue in text_lower)
                if matches > max_matches:
                    max_matches = matches
                    best_match = intent_type
            
            if max_matches > 0 and best_match:
                print(f"Detected intent {best_match} from context clues with {max_matches} matches")
                return intent_to_metrics.get(best_match, None)
            
            return None
            
        return intent_to_metrics.get(intent, None)
    except Exception as e:
        print(f"Error predicting intent: {e}")
        # Fall back to keyword-based intent detection in case of model error
        try:
            text_lower = text.lower()
            
            # Map keywords to intent metrics
            keyword_metrics = {
                'defects': ['defect', 'quality', 'loose thread'],
                'production': ['production', 'output', 'produce', 'productivity'],
                'efficiency': ['efficiency', 'performance'],
                'failures': ['machine', 'failure', 'breakdown', 'maintenance'],
                'order': ['order', 'delivery', 'shipment']
            }
            
            detected_metrics = set()
            for metric, keywords in keyword_metrics.items():
                if any(keyword in text_lower for keyword in keywords):
                    detected_metrics.add(metric)
            
            if detected_metrics:
                print(f"Fallback detected metrics: {detected_metrics}")
                return list(detected_metrics)
                
            return None
        except Exception as fallback_error:
            print(f"Error in fallback intent detection: {fallback_error}")
            return None

def analyze_question(text):
    """Analyze the question using NLP to understand intent and extract relevant information"""
    try:
        tokens, _ = preprocess_text(text)
    except Exception as e:
        print(f"Warning: Text preprocessing failed: {e}")
        tokens = text.lower().split()
    
    analysis = {
        'intent': None,
        'date_info': extract_date_info(text),
        'metrics': set(),
        'filters': {},
        'aggregation': None,
        'comparison': None,
        'math_operation': None,
        'calculation_type': None,
        'original_text': text  # Store the original text for better question analysis
    }
    
    # Debug date extraction
    print(f"Date extraction results: {analysis['date_info']}")
    
    # First try to predict intent using the PyTorch model
    predicted_metrics = predict_intent(text)
    if predicted_metrics:
        analysis['metrics'].update(predicted_metrics)
        print(f"Setting metrics based on predicted intent: {predicted_metrics}")
    
    # Extract mathematical operation if we have a metrics-based question
    if analysis['metrics'] and not analysis['math_operation']:
        math_op = extract_math_operation(text)
        if math_op:
            analysis['math_operation'] = math_op
            print(f"Setting math operation: {math_op}")
    
    # If we're analyzing a known defect question, extract specialized information
    if 'defects' in analysis['metrics']:
        # Check for chain defect comparison patterns
        if re.search(r'which\s+chain|chain\s+with|chain\s+has', text, re.IGNORECASE) and re.search(r'most|highest|maximum|worst', text, re.IGNORECASE):
            analysis['calculation_type'] = 'chain_defects'
            analysis['comparison'] = 'highest'
            print("Detected chain defect comparison query")
        
        # For defect count queries
        if re.search(r'how\s+many|count|number\s+of|total', text, re.IGNORECASE) and not analysis['math_operation']:
            analysis['math_operation'] = 'sum'
            print("Setting math operation to sum for defect count")
        
        # For defect rate queries
        if re.search(r'rate|ratio|percentage|proportion', text, re.IGNORECASE):
            analysis['calculation_type'] = 'defect_rate'
            analysis['math_operation'] = 'rate'
            analysis['metrics'].add('production')  # Need production for rate calculation
            print("Set calculation type to defect_rate")
        
        # For workshop-specific defect queries
        workshop_match = re.search(r'workshop\s+(\d+|one|two|three|four|five)', text, re.IGNORECASE)
        if workshop_match:
            workshop_num = workshop_match.group(1).lower()
            # Convert word numbers to digits if necessary
            word_to_digit = {'one': '1', 'two': '2', 'three': '3', 'four': '4', 'five': '5'}
            if workshop_num in word_to_digit:
                workshop_num = word_to_digit[workshop_num]
            
            # Add workshop filter
            analysis['filters']['workshop'] = workshop_num
            print(f"Added workshop filter: {workshop_num} for workshop-specific query")
    
    # Similarly for failures questions
    if 'failures' in analysis['metrics']:
        # Distribution statistics 
        if re.search(r'distribution|spread|statistics', text, re.IGNORECASE):
            analysis['math_operation'] = 'distribution'
            print("Setting math operation to distribution for failure statistics")
    
    # Handle comparison questions
    compare_match = re.search(r'compare\s+(\w+)\s+between\s+(\w+)\s+(\d+)\s+and\s+(\d+)', text, re.IGNORECASE)
    if compare_match:
        metric_type = compare_match.group(1)
        entity_type = compare_match.group(2)
        id1 = compare_match.group(3)
        id2 = compare_match.group(4)
        
        # Set comparison type
        analysis['calculation_type'] = 'comparison'
        analysis['comparison'] = {
            'metric': metric_type,
            'entity_type': entity_type,
            'ids': [id1, id2]
        }
        
        # Add metrics based on what's being compared
        if 'performance' in metric_type.lower():
            analysis['metrics'].update(['production', 'defects', 'efficiency'])
        elif 'production' in metric_type.lower():
            analysis['metrics'].add('production')
        elif 'defect' in metric_type.lower():
            analysis['metrics'].add('defects')
        elif 'efficiency' in metric_type.lower():
            analysis['metrics'].add('efficiency')
        else:
            # Default to all production metrics if not specified
            analysis['metrics'].update(['production', 'defects'])
        
        print(f"Detected comparison: {analysis['comparison']}")
    
    return analysis

def perform_calculation(data, analysis):
    """Perform mathematical calculations based on the analysis"""
    if not data:
        return {'error': 'No data available for calculations'}
    
    results = {}
    
    try:
        # Special handling for chain defect comparison
        if analysis.get('calculation_type') == 'chain_defects':
            print("Calculating defects by chain")
            
            # Group defects by chain
            chain_defects = {}
            chain_production = {}
            
            # Try various possible field names for chain
            chain_fields = ['chain', 'chainId', 'chain_id', 'productChain', 'product_chain', 'chainName', 'chain_name']
            
            # Check if any of our records have chain fields
            has_chain_fields = False
            sample_record = data[0] if data else {}
            for field in chain_fields:
                if field in sample_record and sample_record[field]:
                    has_chain_fields = True
                    print(f"Found chain field: {field} with value: {sample_record[field]}")
                    break
            
            # If no chain fields found, try to use another field as proxy or group everything
            if not has_chain_fields:
                # Look for alternative grouping fields
                proxy_fields = ['line', 'product', 'productType', 'product_type', 'productLine', 'product_line']
                proxy_field = None
                
                for field in proxy_fields:
                    if any(field in record and record[field] for record in data[:10]):
                        proxy_field = field
                        print(f"Using {proxy_field} as proxy for chain grouping")
                        break
                
                if not proxy_field:
                    # If no proxy field found, check if we can use workshop as grouping
                    if any('workshop' in record and record['workshop'] for record in data[:10]):
                        proxy_field = 'workshop'
                        print("Using workshop as proxy for chain grouping")
            
            for record in data:
                # Find chain identifier
                chain_id = None
                
                # Try to get chain ID from direct chain fields
                for field in chain_fields:
                    if field in record and record[field]:
                        chain_id = str(record[field])
                        break
                
                # If no chain field found, use proxy field if available
                if not chain_id and not has_chain_fields:
                    if proxy_field and proxy_field in record and record[proxy_field]:
                        chain_id = f"{proxy_field.capitalize()}-{record[proxy_field]}"
                    elif 'workshop' in record and record['workshop']:
                        chain_id = f"Workshop-{record['workshop']}"
                    else:
                        chain_id = "Unknown Chain"
                
                # If still no chain ID, use Unknown
                if not chain_id:
                    chain_id = "Unknown Chain"
                
                # Get defects and production values
                defects = float(record.get('defects', 0))
                production = float(record.get('produced', 0))
                
                # Add to totals
                if chain_id not in chain_defects:
                    chain_defects[chain_id] = 0
                    chain_production[chain_id] = 0
                
                chain_defects[chain_id] += defects
                chain_production[chain_id] += production
            
            # Print debug info
            print(f"Found {len(chain_defects)} chains: {list(chain_defects.keys())}")
            
            # Calculate defect rates and create result list
            chain_stats = []
            for chain_id in chain_defects:
                defect_rate = 0
                if chain_production[chain_id] > 0:
                    defect_rate = (chain_defects[chain_id] / chain_production[chain_id]) * 100
                
                chain_stats.append({
                    'chain': chain_id,
                    'defects': chain_defects[chain_id],
                    'production': chain_production[chain_id],
                    'defect_rate': defect_rate
                })
            
            # Sort by defect count or rate based on comparison type
            if analysis.get('comparison') == 'highest':
                chain_stats.sort(key=lambda x: x['defects'], reverse=True)
            elif analysis.get('comparison') == 'lowest':
                chain_stats.sort(key=lambda x: x['defects'])
            
            results['chain_stats'] = chain_stats
            results['total_defects'] = sum(chain_defects.values())
            results['total_records'] = len(data)
            results['has_chain_fields'] = has_chain_fields
            return results
            
        # Special handling for defect rate calculation
        elif analysis.get('calculation_type') == 'defect_rate':
            print("Performing defect rate calculation")
            
            # Calculate defect rate for each record
            defect_rates = []
            total_production = 0
            total_defects = 0
            
            for record in data:
                produced = float(record.get('produced', 0))
                defects = float(record.get('defects', 0))
                
                if produced > 0:
                    defect_rate = (defects / produced) * 100
                    date = record.get('date', 'unknown')
                    defect_rates.append({
                        'date': date,
                        'defect_rate': defect_rate,
                        'produced': produced,
                        'defects': defects
                    })
                    
                    total_production += produced
                    total_defects += defects
            
            if not defect_rates:
                return {'error': 'Could not calculate defect rates with the available data'}
            
            # Calculate overall average defect rate
            overall_rate = (total_defects / total_production) * 100 if total_production > 0 else 0
            
            # Handle average calculation specifically
            if analysis.get('math_operation') == 'average':
                # Check if there's date info with type 'relative_date' and value containing 'month'
                date_info = analysis.get('date_info', {})
                time_period = "all time"
                
                if date_info:
                    if date_info.get('type') == 'relative_date':
                        if isinstance(date_info.get('value'), dict) and 'start' in date_info.get('value', {}):
                            # It's a month range
                            time_period = "this month"
                        elif 'month' in str(date_info).lower():
                            time_period = "this month"
                            
                # Set results
                results['overall_defect_rate'] = overall_rate
                results['total_production'] = total_production
                results['total_defects'] = total_defects
                results['sample_size'] = len(defect_rates)
                results['time_period'] = time_period
                return results
                
            # Sort by defect rate
            defect_rates.sort(key=lambda x: x['defect_rate'], reverse=(analysis.get('comparison') == 'highest'))
            
            # Return top 5 results
            results['defect_rates'] = defect_rates[:5]
            return results
            
        # Special handling for efficiency rate calculation
        elif analysis.get('calculation_type') == 'efficiency_rate':
            print("Performing efficiency rate calculation")
            
            # Define fields to look for with more comprehensive variations
            production_fields = ['produced', 'production', 'output', 'units', 'quantity', 'producedCount', 'totalProduced']
            time_fields = ['hours', 'duration', 'time', 'workingHours', 'working_hours', 'shiftHours', 'operatingHours']
            efficiency_fields = ['efficiency', 'efficiencyRate', 'efficiency_rate', 'performanceRate', 'performance']
            target_fields = ['target', 'productionTarget', 'production_target', 'targetOutput', 'plannedProduction']
            
            # Extract time period for calculation
            time_period = analysis.get('time_period', 'hour')
            
            # Calculate efficiency rate for each record
            efficiency_rates = []
            total_production = 0
            total_time = 0
            total_target = 0
            
            # Collect all field names for debugging
            found_fields = {'production': set(), 'time': set(), 'efficiency': set(), 'target': set()}
            
            for record in data:
                # First, identify which fields actually exist in the data
                for field in production_fields:
                    if field in record and record[field] is not None:
                        found_fields['production'].add(field)
                for field in time_fields:
                    if field in record and record[field] is not None:
                        found_fields['time'].add(field)
                for field in efficiency_fields:
                    if field in record and record[field] is not None:
                        found_fields['efficiency'].add(field)
                for field in target_fields:
                    if field in record and record[field] is not None:
                        found_fields['target'].add(field)
                
                # Extract production value
                production = 0
                for field in production_fields:
                    if field in record:
                        try:
                            value = record[field]
                            if value is not None:
                                production = float(value)
                                break
                        except (ValueError, TypeError):
                            pass
                
                # Extract working time (default to 1 unit if not found)
                time_value = 1.0  # Default of 1 hour
                for field in time_fields:
                    if field in record:
                        try:
                            value = record[field]
                            if value is not None:
                                time_value = float(value)
                                break
                        except (ValueError, TypeError):
                            pass
                
                # Extract efficiency if available
                efficiency = None
                for field in efficiency_fields:
                    if field in record:
                        try:
                            value = record[field]
                            if value is not None:
                                efficiency = float(value)
                                break
                        except (ValueError, TypeError):
                            pass
                
                # Extract target if available
                target = None
                for field in target_fields:
                    if field in record:
                        try:
                            value = record[field]
                            if value is not None:
                                target = float(value)
                                break
                        except (ValueError, TypeError):
                            pass
                
                if production > 0:
                    # Calculate units per time unit
                    production_rate = production / time_value
                    date = record.get('date', 'unknown')
                    
                    # Calculate performance percentage if target is available
                    performance_pct = None
                    if target is not None and target > 0:
                        performance_pct = (production / target) * 100
                    
                    record_data = {
                        'date': date,
                        'production_rate': production_rate,
                        'production': production,
                        'time': time_value,
                        'efficiency': efficiency,
                        'target': target,
                        'performance_pct': performance_pct
                    }
                    
                    # Add any other useful fields
                    if 'workshop' in record:
                        record_data['workshop'] = record['workshop']
                    elif 'workshopId' in record:
                        record_data['workshop'] = record['workshopId']
                    
                    efficiency_rates.append(record_data)
                    
                    total_production += production
                    total_time += time_value
                    if target is not None:
                        total_target += target
            
            if not efficiency_rates:
                return {'error': 'Could not calculate efficiency rates with the available data. Looking at the records, the following relevant fields were found: ' + 
                       ', '.join([f"{k}: {list(v)}" for k, v in found_fields.items() if v])}
            
            # Calculate overall metrics
            overall_rate = total_production / total_time if total_time > 0 else 0
            overall_performance = (total_production / total_target) * 100 if total_target > 0 else None
            
            # Sort by production rate (highest first)
            efficiency_rates.sort(key=lambda x: x.get('production_rate', 0), reverse=True)
            
            # Return results
            results['efficiency_rates'] = efficiency_rates
            results['overall_rate'] = overall_rate
            results['overall_performance'] = overall_performance
            results['time_period'] = time_period
            results['sample_size'] = len(efficiency_rates)
            results['found_fields'] = {k: list(v) for k, v in found_fields.items() if v}
            
            return results
            
        # Special handling for machine failure distribution
        elif 'failures' in analysis['metrics'] and analysis['math_operation'] == 'distribution':
            print("Calculating machine failure distribution")
            
            # Define likely field names for looking up values
            failure_fields = {
                'machine': ['machineReference', 'machine_id', 'machine', 'machineId', 'equipment_id'],
                'technician': ['technicianName', 'technician_name', 'technician', 'repairTechnician', 'engineer'],
                'issue': ['description', 'issue', 'problem', 'failure_description', 'breakdown_reason'],
                'time': ['timeSpent', 'time_spent', 'repair_time', 'maintenance_time', 'duration'],
                'date': ['date', 'breakdown_date', 'maintenance_date', 'failure_date', 'reportDate']
            }
            
            # Distribution by machine
            machine_counts = {}
            for record in data:
                # Find machine identifier
                machine_id = None
                for field in failure_fields['machine']:
                    if field in record and record[field]:
                        machine_id = str(record[field])
                        break
                
                if not machine_id:
                    machine_id = "Unknown"
                    
                machine_counts[machine_id] = machine_counts.get(machine_id, 0) + 1
            
            # Distribution by technician
            tech_counts = {}
            for record in data:
                # Find technician name
                tech = None
                for field in failure_fields['technician']:
                    if field in record and record[field]:
                        tech = str(record[field])
                        break
                
                if not tech:
                    tech = "Unknown"
                    
                tech_counts[tech] = tech_counts.get(tech, 0) + 1
            
            # Distribution by issue type (simplified)
            issue_counts = {}
            for record in data:
                # Find issue description
                issue = None
                for field in failure_fields['issue']:
                    if field in record and record[field]:
                        issue_text = str(record[field]).lower()
                        # Simple categorization based on keywords
                        if any(kw in issue_text for kw in ['electrical', 'circuit', 'power', 'voltage']):
                            issue = "Electrical"
                        elif any(kw in issue_text for kw in ['mechanical', 'bearing', 'motor', 'gear']):
                            issue = "Mechanical"
                        elif any(kw in issue_text for kw in ['software', 'program', 'error', 'code']):
                            issue = "Software"
                        elif any(kw in issue_text for kw in ['maintenance', 'service', 'routine']):
                            issue = "Maintenance"
                        else:
                            # Use first few words as category
                            words = issue_text.split()[:2]
                            issue = " ".join(words) + "..."
                        break
                
                if not issue:
                    issue = "Unknown"
                    
                issue_counts[issue] = issue_counts.get(issue, 0) + 1
            
            # Calculate repair time statistics if available
            repair_times = []
            for record in data:
                for field in failure_fields['time']:
                    if field in record and record[field]:
                        try:
                            time_value = float(record[field])
                            repair_times.append(time_value)
                            break
                        except (ValueError, TypeError):
                            pass
            
            # Put all distribution data together
            results['machine_distribution'] = sorted(machine_counts.items(), key=lambda x: x[1], reverse=True)
            results['technician_distribution'] = sorted(tech_counts.items(), key=lambda x: x[1], reverse=True)
            results['issue_distribution'] = sorted(issue_counts.items(), key=lambda x: x[1], reverse=True)
            
            if repair_times:
                results['repair_time_stats'] = {
                    'mean': np.mean(repair_times),
                    'median': np.median(repair_times),
                    'min': min(repair_times),
                    'max': max(repair_times)
                }
            
            return results
            
        # Extract relevant numeric data
        numeric_data = {
            'production': [float(d.get('produced', 0)) for d in data],
            'defects': [float(d.get('defects', 0)) for d in data],
            'target': [float(d.get('productionTarget', 0)) for d in data],
            'efficiency': [float(d.get('efficiency', 0)) for d in data],
            'failures': [float(d.get('timeSpent', 0)) for d in data if 'timeSpent' in d]
        }
        
        # Perform calculations based on math operation
        if analysis['math_operation'] == 'sum':
            for metric in analysis['metrics']:
                if metric in numeric_data and numeric_data[metric]:
                    results[metric] = sum(numeric_data[metric])
        
        elif analysis['math_operation'] == 'average':
            for metric in analysis['metrics']:
                if metric in numeric_data and numeric_data[metric]:
                    results[metric] = np.mean(numeric_data[metric])
        
        elif analysis['math_operation'] == 'percentage':
            for metric in analysis['metrics']:
                if metric in numeric_data and numeric_data[metric]:
                    total = sum(numeric_data[metric])
                    if 'target' in numeric_data and sum(numeric_data['target']) > 0:
                        results[f"{metric}_percent"] = (total / sum(numeric_data['target'])) * 100
        
        elif analysis['math_operation'] == 'rate':
            if 'production' in analysis['metrics'] and numeric_data['production']:
                total_time = len(data)  # assuming one record per time unit
                if total_time > 0:
                    results['production_rate'] = sum(numeric_data['production']) / total_time
            
            # Calculate defect rate if both metrics are present
            if 'defects' in analysis['metrics'] and 'production' in analysis['metrics']:
                total_production = sum(numeric_data['production'])
                total_defects = sum(numeric_data['defects'])
                if total_production > 0:
                    results['defect_rate'] = (total_defects / total_production) * 100
        
        elif analysis['math_operation'] == 'distribution':
            for metric in analysis['metrics']:
                if metric in numeric_data and numeric_data[metric]:
                    data_array = np.array(numeric_data[metric])
                    results[f"{metric}_stats"] = {
                        'mean': float(np.mean(data_array)),
                        'std': float(np.std(data_array)),
                        'min': float(np.min(data_array)),
                        'max': float(np.max(data_array)),
                        'median': float(np.median(data_array))
                    }
        
        elif analysis['math_operation'] == 'difference':
            for metric in analysis['metrics']:
                if metric in numeric_data and len(numeric_data[metric]) >= 2:
                    results[f"{metric}_difference"] = numeric_data[metric][-1] - numeric_data[metric][0]
        
        elif analysis['math_operation'] == 'trend':
            for metric in analysis['metrics']:
                if metric in numeric_data and len(numeric_data[metric]) >= 2:
                    values = numeric_data[metric]
                    change = ((values[-1] - values[0]) / values[0]) * 100 if values[0] != 0 else 0
                    results[f"{metric}_trend"] = change
        
        return results if results else {'error': 'No calculations could be performed with the available metrics'}
    
    except Exception as e:
        print(f"Calculation error: {str(e)}")
        return {'error': f'Error performing calculations: {str(e)}'}

def format_calculation_response(calc_results):
    """Format the calculation results into a readable response"""
    if not calc_results:
        return "No calculations could be performed."
    
    if 'error' in calc_results:
        return calc_results['error']
    
    response_parts = []
    
    # Special handling for chain defect comparison
    if 'chain_stats' in calc_results:
        chain_stats = calc_results['chain_stats']
        
        if not chain_stats:
            return "No data available to compare defects across chains."
        
        total_records = calc_results.get('total_records', 0)
        total_defects = calc_results.get('total_defects', 0)
        has_chain_fields = calc_results.get('has_chain_fields', False)
        
        # If no real chain fields in database, adjust messaging
        if not has_chain_fields:
            if all(stats.get('chain') == 'Unknown Chain' for stats in chain_stats):
                return f"Found {total_records} records | Total defects: {total_defects} | No chain information found in database."
            else:
                # We're grouping by a proxy field
                first_chain = chain_stats[0].get('chain', '') if chain_stats else ''
                proxy_type = first_chain.split('-')[0] if '-' in first_chain else 'Group'
                response_parts.append(f"Chain information not found. Showing {proxy_type} statistics instead:")
        else:
            response_parts.append(f"Chain Defect Analysis (from {total_records} records, total defects: {total_defects}):")
        
        for i, stats in enumerate(chain_stats[:5]):  # Show top 5 chains
            chain_id = stats.get('chain', 'Unknown')
            defects = stats.get('defects', 0)
            production = stats.get('production', 0)
            defect_rate = stats.get('defect_rate', 0)
            
            # Format appropriately based on whether we have real chain fields
            if has_chain_fields:
                chain_info = f"#{i+1}: Chain {chain_id} | Defects: {defects} | Production: {production} | Defect Rate: {defect_rate:.2f}%"
            else:
                # Remove "Chain" prefix if we're using a proxy field
                if '-' in chain_id:
                    chain_info = f"#{i+1}: {chain_id} | Defects: {defects} | Production: {production} | Defect Rate: {defect_rate:.2f}%"
                else:
                    chain_info = f"#{i+1}: {chain_id} | Defects: {defects} | Production: {production} | Defect Rate: {defect_rate:.2f}%"
            
            response_parts.append(chain_info)
        
        # Check if there was only one chain found
        if len(chain_stats) == 1:
            response_parts.append("Only one chain/group found in the data.")
            
        return " ■ ".join(response_parts)
    
    # Special handling for average defect rate
    elif 'overall_defect_rate' in calc_results:
        overall_rate = calc_results.get('overall_defect_rate', 0)
        total_production = calc_results.get('total_production', 0)
        total_defects = calc_results.get('total_defects', 0)
        sample_size = calc_results.get('sample_size', 0)
        time_period = calc_results.get('time_period', '')
        
        time_description = f"for {time_period}" if time_period else ""
        
        response_parts.append(f"Average Defect Rate Analysis {time_description} (based on {sample_size} records):")
        response_parts.append(f"Overall defect rate: {overall_rate:.2f}%")
        response_parts.append(f"Total production: {total_production:.0f} units")
        response_parts.append(f"Total defects: {total_defects:.0f}")
        
        return " | ".join(response_parts)
    
    # Special handling for efficiency rate results
    elif 'efficiency_rates' in calc_results:
        overall_rate = calc_results.get('overall_rate', 0)
        time_period = calc_results.get('time_period', 'hour')
        sample_size = calc_results.get('sample_size', 0)
        overall_performance = calc_results.get('overall_performance')
        
        response_parts.append(f"Efficiency Rate Analysis (based on {sample_size} records):")
        response_parts.append(f"Overall production rate: {overall_rate:.2f} units per {time_period}")
        
        # Add overall performance if available
        if overall_performance is not None:
            response_parts.append(f"Overall performance vs target: {overall_performance:.2f}%")
        
        # Add average efficiency if available
        efficiency_values = [r.get('efficiency') for r in calc_results['efficiency_rates'] if r.get('efficiency') is not None]
        if efficiency_values:
            avg_efficiency = sum(efficiency_values) / len(efficiency_values)
            response_parts.append(f"Average efficiency: {avg_efficiency:.2f}%")
        
        # Show highest rates
        rates = calc_results['efficiency_rates']
        
        if rates:
            response_parts.append("Top production rates:")
            for i, rate in enumerate(rates[:3]):  # Show top 3
                date = rate.get('date', 'unknown')
                prod_rate = rate.get('production_rate', 0)
                production = rate.get('production', 0)
                time_val = rate.get('time', 0)
                performance = rate.get('performance_pct')
                workshop = rate.get('workshop', '')
                
                rate_info = f"#{i+1}: Date: {date}"
                if workshop:
                    rate_info += f" | Workshop: {workshop}"
                rate_info += f" | Rate: {prod_rate:.2f} units/{time_period}"
                rate_info += f" | Production: {production} units"
                rate_info += f" | Time: {time_val} hours"
                if performance is not None:
                    rate_info += f" | Performance: {performance:.2f}%"
                
                response_parts.append(rate_info)
        
        # Add information about which fields were found in the data
        if 'found_fields' in calc_results:
            found_fields = calc_results['found_fields']
            field_info = []
            for category, fields in found_fields.items():
                if fields:
                    field_info.append(f"{category}: {', '.join(fields)}")
            
            if field_info:
                response_parts.append("Fields used in calculation: " + " | ".join(field_info))
        
        return " ■ ".join(response_parts)
    
    # Special handling for machine failure distribution
    elif 'machine_distribution' in calc_results:
        # Format machine distribution
        machine_dist = calc_results['machine_distribution']
        response_parts.append("Machine Failure Distribution:")
        
        # Top machines with most failures
        if machine_dist:
            machine_lines = []
            total_failures = sum(count for _, count in machine_dist)
            
            for machine, count in machine_dist[:5]:  # Show top 5
                percentage = (count / total_failures) * 100 if total_failures > 0 else 0
                machine_lines.append(f"{machine}: {count} failures ({percentage:.1f}%)")
            
            response_parts.append(" | ".join(machine_lines))
        
        # Technician distribution
        if 'technician_distribution' in calc_results:
            tech_dist = calc_results['technician_distribution']
            if tech_dist:
                response_parts.append("Technician Distribution:")
                tech_lines = []
                for tech, count in tech_dist[:3]:  # Show top 3
                    tech_lines.append(f"{tech}: {count} repairs")
                response_parts.append(" | ".join(tech_lines))
        
        # Issue type distribution
        if 'issue_distribution' in calc_results:
            issue_dist = calc_results['issue_distribution']
            if issue_dist:
                response_parts.append("Issue Type Distribution:")
                issue_lines = []
                for issue, count in issue_dist[:5]:  # Show top 5
                    issue_lines.append(f"{issue}: {count}")
                response_parts.append(" | ".join(issue_lines))
        
        # Repair time statistics
        if 'repair_time_stats' in calc_results:
            stats = calc_results['repair_time_stats']
            response_parts.append("Repair Time Statistics:")
            stats_lines = [
                f"Average: {stats['mean']:.1f} minutes",
                f"Median: {stats['median']:.1f} minutes",
                f"Min: {stats['min']:.1f} minutes",
                f"Max: {stats['max']:.1f} minutes"
            ]
            response_parts.append(" | ".join(stats_lines))
            
        return " ■ ".join(response_parts)
    
    # Special handling for defect rate results
    elif 'defect_rates' in calc_results:
        defect_rates = calc_results['defect_rates']
        if not defect_rates:
            return "No defect rate data available for the specified period."
            
        # Format the defect rate information
        response_parts.append(f"Highest defect rates found:")
        
        for i, rate_data in enumerate(defect_rates):
            date = rate_data.get('date', 'unknown date')
            defect_rate = rate_data.get('defect_rate', 0)
            produced = rate_data.get('produced', 0)
            defects = rate_data.get('defects', 0)
            
            rate_info = (
                f"#{i+1}: Date: {date} | "
                f"Defect Rate: {defect_rate:.2f}% | "
                f"Units Produced: {produced} | "
                f"Defects: {defects}"
            )
            response_parts.append(rate_info)
            
        return " ■ ".join(response_parts)
    
    # Regular formatting for other calculation types
    for metric, value in calc_results.items():
        if isinstance(value, dict):  # For distribution stats
            response_parts.append(f"{metric.replace('_', ' ').title()}:")
            for stat, stat_value in value.items():
                response_parts.append(f"- {stat}: {stat_value:.2f}")
        elif isinstance(value, (int, float)):
            if 'percent' in metric:
                response_parts.append(f"{metric.replace('_', ' ').title()}: {value:.2f}%")
            elif 'rate' in metric:
                if 'defect' in metric:
                    response_parts.append(f"Defect Rate: {value:.2f}%")
                else:
                    response_parts.append(f"{metric.replace('_', ' ').title()}: {value:.2f} units per period")
            elif 'trend' in metric:
                direction = "increase" if value > 0 else "decrease" if value < 0 else "change"
                response_parts.append(f"{metric.replace('_', ' ').title()}: {abs(value):.2f}% {direction}")
            elif 'difference' in metric:
                response_parts.append(f"{metric.replace('_', ' ').title()}: {value:.2f} units")
            else:
                response_parts.append(f"{metric.replace('_', ' ').title()}: {value:.2f}")
    
    return " | ".join(response_parts) if response_parts else "Could not format the calculation results."

def build_mongodb_query(analysis):
    """Build a MongoDB query based on the analysis without hardcoded field names"""
    query = {}
    
    # Add date filters
    if analysis['date_info']:
        date_info = analysis['date_info']
        if date_info['type'] == 'exact_date':
            # Handle both date formats (with and without time)
            date_value = date_info['value']
            query['$or'] = [
                {'date': date_value},  # Exact match for "2025-04-24" format
                {'date': {'$regex': f"^{date_value}"}}  # Prefix match for "2025-04-24T..." format
            ]
        elif date_info['type'] == 'relative_date':
            if isinstance(date_info['value'], dict):
                # For date range queries, we need to handle both formats
                start_date = date_info['value']['start']
                end_date = date_info['value']['end']
                query['$or'] = [
                    # For "2025-04-24" format
                    {'date': {'$gte': start_date, '$lte': end_date}},
                    # For "2025-04-24T..." format 
                    {'date': {'$regex': f"^({start_date}|{end_date})"}}
                ]
            else:
                query['date'] = date_info['value']
    
    # Add other filters with case-insensitive search
    for filter_type, value in analysis['filters'].items():
        if filter_type == 'technician':
            # Handle all possible field naming conventions for technician
            # Use both exact and partial matching to improve results
            print(f"Building technician query for: '{value}'")
            query['$or'] = [
                # Exact match (case-insensitive)
                {'technicianName': {'$regex': f"^{re.escape(value)}$", '$options': 'i'}},
                {'technician_name': {'$regex': f"^{re.escape(value)}$", '$options': 'i'}},
                {'technician': {'$regex': f"^{re.escape(value)}$", '$options': 'i'}},
                {'repairTechnician': {'$regex': f"^{re.escape(value)}$", '$options': 'i'}},
                {'engineer': {'$regex': f"^{re.escape(value)}$", '$options': 'i'}},
                # Partial match as fallback (case-insensitive)
                {'technicianName': {'$regex': f"{re.escape(value)}", '$options': 'i'}},
                {'technician_name': {'$regex': f"{re.escape(value)}", '$options': 'i'}},
                {'technician': {'$regex': f"{re.escape(value)}", '$options': 'i'}},
                {'repairTechnician': {'$regex': f"{re.escape(value)}", '$options': 'i'}},
                {'engineer': {'$regex': f"{re.escape(value)}", '$options': 'i'}}
            ]
        elif filter_type == 'workshop':
            query['$or'] = [
                {'workshop': value},
                {'workshopId': value},
                {'workshop_id': value}
            ]
        elif filter_type == 'machine':
            # Handle all possible field naming conventions for machine
            query['$or'] = [
                {'machineReference': {'$regex': value, '$options': 'i'}},
                {'machine_id': {'$regex': value, '$options': 'i'}},
                {'machine': {'$regex': value, '$options': 'i'}},
                {'machineId': {'$regex': value, '$options': 'i'}}
            ]
        elif filter_type == 'chain':
            # Handle all possible field naming conventions for chain
            query['$or'] = [
                {'chain': {'$regex': value, '$options': 'i'}},
                {'chainId': {'$regex': value, '$options': 'i'}},
                {'chain_id': {'$regex': value, '$options': 'i'}},
                {'productChain': {'$regex': value, '$options': 'i'}},
                {'product_chain': {'$regex': value, '$options': 'i'}},
                {'chainName': {'$regex': value, '$options': 'i'}},
                {'chain_name': {'$regex': value, '$options': 'i'}}
            ]
        elif filter_type == 'order':
            # Try both string and numeric format for order references
            query['$or'] = [
                {'orderRef': value},
                {'order_reference': value},
                {'orderReference': value},
                {'order_ref': value},
                {'order': value},
                {'orderId': value},
                {'order_id': value},
                # Numeric variants if the value is a digit
                {'orderRef': int(value)} if value.isdigit() else {},
                {'order_reference': int(value)} if value.isdigit() else {},
                {'orderReference': int(value)} if value.isdigit() else {},
                {'order_ref': int(value)} if value.isdigit() else {},
                {'order': int(value)} if value.isdigit() else {},
                {'orderId': int(value)} if value.isdigit() else {},
                {'order_id': int(value)} if value.isdigit() else {}
            ]
            # Remove any empty dictionaries which would be invalid in MongoDB
            query['$or'] = [q for q in query['$or'] if q]
    
    return query

def format_response(data, analysis):
    """Format the response based on the data and analysis"""
    if not data:
        if 'failures' in analysis['metrics']:
            date_info = ""
            if analysis['date_info']:
                if analysis['date_info']['type'] == 'exact_date':
                    date_info = f" on {analysis['date_info']['value']}"
                elif analysis['date_info']['type'] == 'relative_date' and analysis['date_info'].get('description') == 'today':
                    date_info = " today"
            
            return f"No machine failures or interventions found{date_info}."
            
        if 'defects' in analysis['metrics']:
            if analysis.get('calculation_type') == 'chain_defects':
                return "No defects found for any chains. The database may not have chain information or defect data."
                
            date_info = ""
            if analysis['date_info']:
                if analysis['date_info']['type'] == 'exact_date':
                    date_info = f" on {analysis['date_info']['value']}"
                elif analysis['date_info']['type'] == 'relative_date' and analysis['date_info'].get('description') == 'today':
                    date_info = " today"
            
            return f"No defects found{date_info}."
        
        # For order reference, give more specific message
        if 'order' in analysis['filters']:
            return f"No data found for order {analysis['filters']['order']}. Please check the order reference number and try again."
            
        if 'chain' in analysis['filters']:
            return f"No data found for chain {analysis['filters']['chain']}. The database may not have chain information or the specified chain doesn't exist."
            
        return "No data found matching your criteria."
    
    response_parts = []
    
    # Handle machine failures specifically
    if 'failures' in analysis['metrics']:
        total_records = len(data)
        response_parts.append(f"Found {total_records} machine failure records:")
        
        # Look for all possible field names from the data
        failure_fields = {
            'date': ['date', 'breakdown_date', 'maintenance_date', 'failure_date', 'reportDate'],
            'machine': ['machineReference', 'machine_id', 'machine', 'machineId', 'equipment_id'],
            'technician': ['technicianName', 'technician_name', 'technician', 'repairTechnician', 'engineer'],
            'issue': ['description', 'issue', 'problem', 'failure_description', 'breakdown_reason'],
            'time': ['timeSpent', 'time_spent', 'repair_time', 'maintenance_time', 'duration'],
            'solution': ['solution', 'resolution', 'action_taken', 'repair_action'],
            'status': ['status', 'repair_status', 'condition', 'state']
        }
        
        # Group failures by machine
        machine_groups = {}
        for failure in data:
            # Get machine ID (using different possible field names)
            machine_id = None
            for field in failure_fields['machine']:
                if field in failure:
                    machine_id = failure.get(field)
                    break
            
            if not machine_id:
                machine_id = 'Unknown Machine'
            
            if machine_id not in machine_groups:
                machine_groups[machine_id] = []
            machine_groups[machine_id].append(failure)
        
        # Format results in a readable table-like structure
        formatted_failures = []
        
        for failure in data:
            failure_info = []
            
            # Handle date field
            date_value = None
            for field in failure_fields['date']:
                if field in failure:
                    date_value = failure.get(field)
                    break
            if date_value:
                failure_info.append(f"Date: {date_value}")
            
            # Handle machine field
            machine_value = None
            for field in failure_fields['machine']:
                if field in failure:
                    machine_value = failure.get(field)
                    break
            if machine_value:
                failure_info.append(f"Machine: {machine_value}")
            
            # Handle technician field
            tech_value = None
            for field in failure_fields['technician']:
                if field in failure:
                    tech_value = failure.get(field)
                    break
            if tech_value:
                failure_info.append(f"Technician: {tech_value}")
            
            # Handle description/issue field
            issue_value = None
            for field in failure_fields['issue']:
                if field in failure:
                    issue_value = failure.get(field)
                    break
            if issue_value:
                failure_info.append(f"Issue: {issue_value}")
            
            # Handle time field
            time_value = None
            for field in failure_fields['time']:
                if field in failure:
                    time_value = failure.get(field)
                    break
            if time_value:
                failure_info.append(f"Time Spent: {time_value} minutes")
            
            # Handle solution field
            solution_value = None
            for field in failure_fields['solution']:
                if field in failure and failure.get(field):
                    solution_value = failure.get(field)
                    break
            if solution_value:
                failure_info.append(f"Solution: {solution_value}")
            
            # Handle status field
            status_value = None
            for field in failure_fields['status']:
                if field in failure and failure.get(field):
                    status_value = failure.get(field)
                    break
            if status_value:
                failure_info.append(f"Status: {status_value}")
            
            formatted_failures.append(" | ".join(failure_info))
        
        # Create summary by technician, machine, and issue type
        if len(data) > 5:
            summary = create_failure_summary(data, failure_fields)
            if summary:
                response_parts.append(summary)
        
        # Join all failure info with special separator for better readability
        response_parts.append(" ■ ".join(formatted_failures))
        
        # Join main parts with clear section headers
        return " <br><br> ".join(response_parts)
    
    # Handle other types of data
    if isinstance(data, list):
        if analysis['math_operation']:
            if analysis['math_operation'] == 'average':
                for metric in analysis['metrics']:
                    if metric == 'production':
                        avg = sum(d.get('produced', 0) for d in data) / len(data)
                        response_parts.append(f"Average production: {avg:.2f} units")
                    elif metric == 'defects':
                        avg = sum(d.get('defects', 0) for d in data) / len(data)
                        response_parts.append(f"Average defects: {avg:.2f}")
        else:
            # Summarize the data
            total_records = len(data)
            response_parts.append(f"Found {total_records} records")
            
            if 'production' in analysis['metrics']:
                total_production = sum(d.get('produced', 0) for d in data)
                response_parts.append(f"Total production: {total_production} units")
            
            if 'defects' in analysis['metrics']:
                total_defects = sum(d.get('defects', 0) for d in data)
                response_parts.append(f"Total defects: {total_defects}")
    
    return " | ".join(response_parts)

def create_failure_summary(failures, failure_fields=None):
    """Create a summary of failure data for better readability with flexible field names"""
    try:
        # Default field mappings if none provided
        if not failure_fields:
            failure_fields = {
                'date': ['date', 'breakdown_date', 'maintenance_date', 'failure_date'],
                'machine': ['machineReference', 'machine_id', 'machine', 'machineId'],
                'technician': ['technicianName', 'technician_name', 'technician'],
                'issue': ['description', 'issue', 'problem', 'failure_description']
            }
        
        # Count failures by technician
        techs = {}
        machines = {}
        issues = {}
        
        for failure in failures:
            # Count by technician
            tech = None
            for field in failure_fields['technician']:
                if field in failure and failure[field]:
                    tech = failure[field]
                    break
            if not tech:
                tech = 'Unknown'
            techs[tech] = techs.get(tech, 0) + 1
            
            # Count by machine
            machine = None
            for field in failure_fields['machine']:
                if field in failure and failure[field]:
                    machine = failure[field]
                    break
            if not machine:
                machine = 'Unknown'
            machines[machine] = machines.get(machine, 0) + 1
            
            # Count by issue
            issue = None
            for field in failure_fields['issue']:
                if field in failure and failure[field]:
                    issue = failure[field]
                    break
            if not issue:
                issue = 'Unknown issue'
                
            # Simplify issue text to group similar issues
            simple_issue = issue.lower().split()[:3]  # Use first 3 words
            simple_key = ' '.join(simple_issue)
            issues[simple_key] = issues.get(simple_key, 0) + 1
        
        # Create summary text
        summary_parts = ["Summary:"]
        
        # Add technician summary if we have multiple technicians
        if len(techs) > 1:
            tech_summary = ", ".join([f"{tech}: {count} records" for tech, count in 
                                     sorted(techs.items(), key=lambda x: x[1], reverse=True)[:3]])
            summary_parts.append(f"Technicians: {tech_summary}")
        
        # Add machine summary if we have multiple machines
        if len(machines) > 1:
            top_machines = sorted(machines.items(), key=lambda x: x[1], reverse=True)[:3]
            machine_summary = ", ".join([f"{machine}: {count} failures" for machine, count in top_machines])
            summary_parts.append(f"Top machines: {machine_summary}")
        
        # Add issue summary if we have multiple issues
        if len(issues) > 1:
            top_issues = sorted(issues.items(), key=lambda x: x[1], reverse=True)[:3]
            issue_summary = ", ".join([f"\"{issue}\": {count} occurrences" for issue, count in top_issues])
            summary_parts.append(f"Top issues: {issue_summary}")
            
        return " | ".join(summary_parts)
    except Exception as e:
        print(f"Error creating failure summary: {e}")
        return ""  # Return empty string if any error occurs during summary creation

def query_database(analysis):
    """Query the database based on the analysis"""
    # Check if database connection is available
    if not mongodb_available:
        # Try to reconnect once more before giving up
        global client, db
        retry_client, retry_db, success, collections = connect_to_mongodb(max_retries=1)
        if success:
            client = retry_client
            db = retry_db
            print("Successfully reconnected to MongoDB!")
        else:
            return "Database connection is currently unavailable. Please try again later. Check your network connection and MongoDB Atlas settings."
    
    # Handle special case for workshop comparison
    if analysis['calculation_type'] == 'comparison' and analysis['comparison'].get('entity_type') == 'workshop':
        return compare_workshops(analysis)
    
    # Handle different query types based on metrics and calculation types
    if 'defects' in analysis['metrics']:
        # Check if calculation type already set by analyze_question
        if analysis.get('calculation_type') == 'defect_rate':
            print("Processing defect rate query")
            # Ensure we have production info for the rate calculation
            analysis['metrics'].add('production')
            analysis['math_operation'] = 'rate'
        
        # Check for workshop-specific defect filter
        if 'workshop' in analysis['filters']:
            print(f"Processing defect query for workshop {analysis['filters']['workshop']}")
    
    # Special handling for chain defect comparison
    if analysis.get('calculation_type') == 'chain_defects':
        # For "which chain had the most defects" we don't want to filter by chain
        # We want to get all records to compare across chains
        if 'chain' in analysis['filters']:
            print("Removing chain filter for chain defect comparison query")
            del analysis['filters']['chain']
    
    # Special processing for machine failures/interventions
    if 'failures' in analysis['metrics'] and 'machine' in analysis['filters']:
        # Check if the machine filter value is actually "interventions" or similar
        machine_value = analysis['filters'].get('machine', '').lower()
        if 'intervention' in machine_value:
            print("Detected 'interventions' as machine filter value - this is likely incorrect")
            # Remove this as it's not a real machine ID but part of the query phrase
            del analysis['filters']['machine']
            print("Removed 'interventions' from machine filter")
    
    # Build and execute the query
    query = build_mongodb_query(analysis)
    print(f"Query: {query}")
    
    try:
        # Determine which collections to try based on the query metrics
        collections_to_try = []
        
        if 'failures' in analysis['metrics']:
            # Prioritize collections that likely contain machine failure data
            failure_collections = [coll for coll in available_collections 
                                if any(keyword in coll.lower() for keyword in ['failure', 'machine', 'repair', 'maintenance'])]
            if failure_collections:
                collections_to_try.extend(failure_collections)
            else:
                # Look for collections we know have failure data from logs
                if 'new_data.machinefailures' in available_collections:
                    collections_to_try.append('new_data.machinefailures')
                
            # Only use empty query if there are no filters specified
            if not analysis['filters'] and len(query) == 0:
                query = {}  # Clear the query to get all machine failures
                print("Using empty query to find all machine failures")
            else:
                print(f"Applying filters to machine failures query: {analysis['filters']}")
            
            # Add other collections as fallbacks
            other_collections = [coll for coll in available_collections 
                               if coll not in collections_to_try and coll != 'chatbot_conversations']
            collections_to_try.extend(other_collections)
        else:
            # Prioritize collections that likely contain performance data
            perf_collections = [coll for coll in available_collections 
                              if any(keyword in coll.lower() for keyword in ['performance', 'production'])]
            if perf_collections:
                collections_to_try.extend(perf_collections)
            else:
                # Look for collections we know have performance data from logs
                if 'performance3' in available_collections:
                    collections_to_try.append('performance3')
        
        # If no matches found, try all collections as a fallback
        if not collections_to_try:
            collections_to_try = available_collections
        
        # Try each collection
        data = []
        for collection_name in collections_to_try:
            try:
                print(f"Trying collection: {collection_name}")
                coll = db[collection_name]
                
                # Special handling for different query types
                if 'failures' in analysis['metrics'] and analysis['math_operation'] == 'distribution':
                    # Get all failures first, then group them for distribution calculation
                    result = list(coll.find().limit(100))  # Limit to reasonable number
                elif 'efficiency' in analysis['metrics'] and analysis.get('calculation_type') == 'efficiency_rate':
                    # Get a reasonable sample for efficiency calculations
                    result = list(coll.find(query).limit(100))  # More data for better analysis
                else:
                    result = list(coll.find(query).limit(50))
                    
                if result:
                    print(f"Found {len(result)} documents in {collection_name}")
                    data = result
                    break
            except Exception as collection_error:
                print(f"Error accessing collection {collection_name}: {collection_error}")
                continue
        
        # If no data found but we're looking for failures, try a more general approach
        if not data and 'failures' in analysis['metrics']:
            # Only try a more general approach if there are no filters
            if not analysis['filters']:
                print("No specific failures found. Trying to get all failure records...")
                # Try to get any failure records
                for collection_name in collections_to_try:
                    try:
                        # Simply get all documents in collection (typically failure collections are small)
                        result = list(db[collection_name].find().limit(50))
                        if result:
                            print(f"Found {len(result)} failure documents in {collection_name}")
                            data = result
                            break
                    except Exception:
                        continue
            else:
                print(f"No data found with filters: {analysis['filters']}. Not falling back to all records.")
        
        # If no data found with the specific query for non-failure queries, try a more flexible approach
        elif not data and analysis['filters']:
            print("No data found with specific query, trying a more general search...")
            
            # Try each filter individually
            for filter_type, value in analysis['filters'].items():
                flexible_query = {}
                
                # Build a flexible query based on filter type
                if filter_type == 'technician':
                    # First, get all field names from a sample document in each collection
                    for coll_name in collections_to_try:
                        try:
                            sample = db[coll_name].find_one()
                            if sample:
                                # Try to identify technician-related fields
                                tech_fields = [field for field in sample.keys() 
                                            if 'tech' in field.lower() or 'name' in field.lower()]
                                
                                # Build OR query for all potential technician fields
                                if tech_fields:
                                    or_conditions = []
                                    for field in tech_fields:
                                        or_conditions.append({field: {"$regex": value, "$options": "i"}})
                                    
                                    flexible_query = {"$or": or_conditions}
                                    
                                    # Try this query
                                    result = list(db[coll_name].find(flexible_query))
                                    if result:
                                        print(f"Found {len(result)} documents in {coll_name} with flexible technician query")
                                        data = result
                                        break
                        except Exception:
                            continue
                
                # Special handling for order queries
                elif filter_type == 'order':
                    print(f"Trying flexible search for order: {value}")
                    
                    # Try to find any field that might contain the order reference
                    for coll_name in collections_to_try:
                        try:
                            sample = db[coll_name].find_one()
                            if sample:
                                # Look for any field that might be order-related
                                order_fields = [field for field in sample.keys() 
                                            if any(kw in field.lower() for kw in ['order', 'ref', 'reference'])]
                                
                                if order_fields:
                                    or_conditions = []
                                    for field in order_fields:
                                        # Try both exact match and regex for string fields
                                        or_conditions.append({field: value})
                                        or_conditions.append({field: {"$regex": value, "$options": "i"}})
                                        # Also try numeric match if value is a number
                                        if value.isdigit():
                                            or_conditions.append({field: int(value)})
                                    
                                    flexible_query = {"$or": or_conditions}
                                    
                                    # Try this query
                                    print(f"Trying order search with fields: {order_fields}")
                                    result = list(db[coll_name].find(flexible_query).limit(10))
                                    if result:
                                        print(f"Found {len(result)} documents in {coll_name} with flexible order query")
                                        data = result
                                        break
                        except Exception as e:
                            print(f"Error in flexible order search: {e}")
                            continue
                
                # If we found data, stop trying other filters
                if data:
                    break
        
        # If there's a math operation and we have the right metrics, perform calculations
        if data:
            if analysis.get('calculation_type') in ['defect_rate', 'efficiency_rate']:
                calc_results = perform_calculation(data, analysis)
                return format_calculation_response(calc_results)
            elif analysis['math_operation'] and data:
                calc_results = perform_calculation(data, analysis)
                return format_calculation_response(calc_results)
        
        # Otherwise, format regular response
        return format_response(data, analysis)
    except Exception as e:
        print(f"Database query error: {e}")
        return f"Error querying database: {str(e)}. Please try a different query format."

def query_defect_types():
    """Query and return defect types information"""
    try:
        if mongodb_available and 'defect_types' in available_collections:
            # Query the defect_types collection
            defect_types = list(db.defect_types.find().limit(15))
            
            if not defect_types:
                return "No defect types found in the database."
            
            # Format the response
            response_parts = [f"Found {len(defect_types)} defect types:"]
            
            for defect in defect_types:
                # Check for different possible field names for defect name
                name = defect.get('defectName', defect.get('name', 'Unknown'))
                description = defect.get('description', defect.get('defectDescription', ''))
                severity = defect.get('severity', defect.get('defectSeverity', ''))
                count = defect.get('defectTypes', defect.get('count', 0))
                
                defect_info = f"• {name}"
                if description:
                    defect_info += f" - {description}"
                if severity:
                    defect_info += f" (Severity: {severity})"
                if count:
                    defect_info += f" ({count} occurrences)"
                
                response_parts.append(defect_info)
            
            return " \n".join(response_parts)
        else:
            # If defect_types collection is not available, check other collections for defect information
            defect_info = extract_defect_info_from_performance()
            if defect_info:
                return defect_info
            
            return "No dedicated defect types information found in the database."
    except Exception as e:
        print(f"Error querying defect types: {e}")
        return f"Error retrieving defect types: {str(e)}"

def extract_defect_info_from_performance():
    """Extract defect information from performance data if dedicated defect_types collection is not available"""
    try:
        if mongodb_available and 'performance3' in available_collections:
            # Try to get defect distribution info from performance data
            # Analyze defect fields across records to identify types
            results = list(db.performance3.find({}, {'defects': 1, 'defectTypes': 1}).limit(100))
            
            defect_counts = {}
            
            for record in results:
                # Check for any field that might contain defect type information
                if 'defectTypes' in record:
                    defect_types = record.get('defectTypes', {})
                    if isinstance(defect_types, dict):
                        for defect_type, count in defect_types.items():
                            if count > 0:
                                defect_counts[defect_type] = defect_counts.get(defect_type, 0) + count
            
            if defect_counts:
                # Sort by frequency
                sorted_defects = sorted(defect_counts.items(), key=lambda x: x[1], reverse=True)
                
                response_parts = ["Based on performance data, the following defect types were identified:"]
                for defect_type, count in sorted_defects:
                    response_parts.append(f"• {defect_type}: {count} occurrences")
                
                return " \n".join(response_parts)
            
            # If no defect types found in fields, return a generic message
            return "No specific defect type information was found, but general defect counts are available."
            
        return None
    except Exception as e:
        print(f"Error extracting defect info from performance: {e}")
        return None

def query_most_common_defects():
    """Query and return the most common defects"""
    try:
        if mongodb_available:
            # First try dedicated defect_types collection
            if 'defect_types' in available_collections:
                # Try to sort by defectTypes (count) field first
                defect_types = list(db.defect_types.find().sort('defectTypes', -1).limit(5))
                
                # If no results or no proper count field, try to get from performance data
                if not defect_types or ('defectTypes' not in defect_types[0] and 'frequency' not in defect_types[0]):
                    return extract_defect_info_from_performance() or "Could not determine most common defects as frequency data is not available."
                
                response_parts = ["The most common defect types are:"]
                for i, defect in enumerate(defect_types):
                    # Try different possible field names
                    name = defect.get('defectName', defect.get('name', 'Unknown'))
                    count = defect.get('defectTypes', defect.get('frequency', defect.get('count', 0)))
                    description = defect.get('description', defect.get('defectDescription', ''))
                    
                    defect_info = f"{i+1}. {name} ({count} occurrences)"
                    if description:
                        defect_info += f" - {description}"
                    
                    response_parts.append(defect_info)
                
                return " \n".join(response_parts)
            else:
                # If no dedicated collection, extract from performance data
                return extract_defect_info_from_performance() or "No defect type information found in the database."
        
        return "Database not available for querying defect information."
    except Exception as e:
        print(f"Error querying most common defects: {e}")
        return f"Error retrieving most common defects: {str(e)}"

def compare_workshops(analysis):
    """Compare data between two workshops"""
    if not mongodb_available:
        return "Database connection is unavailable for comparison."
    
    comparison_info = analysis['comparison']
    workshop_ids = comparison_info.get('ids', [])
    
    if len(workshop_ids) < 2:
        return "Need at least two workshop IDs to compare."
    
    # Get metrics to compare
    metrics = analysis['metrics']
    if not metrics:
        metrics = {'production', 'defects', 'efficiency'}  # Default metrics
    
    # Create results container
    workshop_data = {}
    
    # Prepare date filter if present
    date_query = {}
    if analysis['date_info']:
        date_info = analysis['date_info']
        if date_info['type'] == 'exact_date':
            date_query['$or'] = [
                {'date': date_info['value']},
                {'date': {'$regex': f"^{date_info['value']}"}}
            ]
        elif date_info['type'] == 'relative_date':
            if isinstance(date_info['value'], dict):
                start_date = date_info['value']['start']
                end_date = date_info['value']['end']
                date_query['$or'] = [
                    {'date': {'$gte': start_date, '$lte': end_date}},
                    {'date': {'$regex': f"^({start_date}|{end_date})"}}
                ]
            else:
                date_query['date'] = date_info['value']
    
    try:
        # Try different possible collection names for production data
        collections_to_try = [coll for coll in available_collections 
                          if any(keyword in coll.lower() for keyword in ['performance', 'production'])]
        
        # Add specific known collections
        if 'performance3' in available_collections:
            collections_to_try.insert(0, 'performance3')
        
        # Try each collection to find workshop data
        for workshop_id in workshop_ids:
            workshop_data[workshop_id] = {
                'production': 0,
                'defects': 0,
                'efficiency': 0,
                'records': 0
            }
            
            for collection_name in collections_to_try:
                try:
                    # Build query for this workshop
                    workshop_query = {
                        '$or': [
                            {'workshop': workshop_id},
                            {'workshopId': workshop_id},
                            {'workshop_id': workshop_id}
                        ]
                    }
                    
                    # Add date filter if present
                    if date_query:
                        for key, value in date_query.items():
                            workshop_query[key] = value
                    
                    print(f"Searching for workshop {workshop_id} in {collection_name} with query: {workshop_query}")
                    
                    # Query the database
                    results = list(db[collection_name].find(workshop_query))
                    if results:
                        print(f"Found {len(results)} records for workshop {workshop_id} in {collection_name}")
                        
                        # Calculate metrics
                        total_production = sum(float(r.get('produced', 0)) for r in results)
                        total_defects = sum(float(r.get('defects', 0)) for r in results)
                        avg_efficiency = sum(float(r.get('efficiency', 0)) for r in results) / len(results) if len(results) > 0 else 0
                        
                        # Store results
                        workshop_data[workshop_id]['production'] = total_production
                        workshop_data[workshop_id]['defects'] = total_defects
                        workshop_data[workshop_id]['efficiency'] = avg_efficiency
                        workshop_data[workshop_id]['records'] = len(results)
                        
                        # We found data, no need to check other collections
                        break
                except Exception as e:
                    print(f"Error querying workshop {workshop_id} in {collection_name}: {e}")
                    continue
        
        # If we found data for at least one workshop, format comparison
        if any(data['records'] > 0 for data in workshop_data.values()):
            return format_workshop_comparison(workshop_data, workshop_ids, metrics)
        else:
            return "No data found for the specified workshops."
            
    except Exception as e:
        print(f"Workshop comparison error: {e}")
        return f"Error during workshop comparison: {str(e)}"

def format_workshop_comparison(workshop_data, workshop_ids, metrics):
    """Format comparison between workshops"""
    response_parts = []
    response_parts.append(f"Workshop Comparison: Workshop {workshop_ids[0]} vs Workshop {workshop_ids[1]}")
    
    # Check if we have data for both workshops
    if workshop_data[workshop_ids[0]]['records'] == 0:
        return f"No data found for Workshop {workshop_ids[0]}."
    if workshop_data[workshop_ids[1]]['records'] == 0:
        return f"No data found for Workshop {workshop_ids[1]}."
    
    # Compare production if available
    if 'production' in metrics:
        prod1 = workshop_data[workshop_ids[0]]['production']
        prod2 = workshop_data[workshop_ids[1]]['production']
        
        prod_diff = prod1 - prod2
        prod_percent = (prod_diff / prod2) * 100 if prod2 > 0 else 0
        
        if prod_diff > 0:
            prod_text = f"Workshop {workshop_ids[0]} produced {prod_diff:.0f} more units ({abs(prod_percent):.1f}% more)"
        elif prod_diff < 0:
            prod_text = f"Workshop {workshop_ids[1]} produced {abs(prod_diff):.0f} more units ({abs(prod_percent):.1f}% more)"
        else:
            prod_text = f"Both workshops had equal production: {prod1:.0f} units"
            
        response_parts.append(f"Production: {prod_text}")
    
    # Compare defects if available
    if 'defects' in metrics:
        def1 = workshop_data[workshop_ids[0]]['defects']
        def2 = workshop_data[workshop_ids[1]]['defects']
        
        # Calculate defect rates
        prod1 = workshop_data[workshop_ids[0]]['production']
        prod2 = workshop_data[workshop_ids[1]]['production']
        
        defect_rate1 = (def1 / prod1) * 100 if prod1 > 0 else 0
        defect_rate2 = (def2 / prod2) * 100 if prod2 > 0 else 0
        
        if defect_rate1 < defect_rate2:
            def_text = f"Workshop {workshop_ids[0]} has better quality with {defect_rate1:.2f}% defect rate vs {defect_rate2:.2f}%"
        elif defect_rate1 > defect_rate2:
            def_text = f"Workshop {workshop_ids[1]} has better quality with {defect_rate2:.2f}% defect rate vs {defect_rate1:.2f}%"
        else:
            def_text = f"Both workshops have the same defect rate: {defect_rate1:.2f}%"
            
        response_parts.append(f"Quality: {def_text}")
    
    # Compare efficiency if available
    if 'efficiency' in metrics:
        eff1 = workshop_data[workshop_ids[0]]['efficiency']
        eff2 = workshop_data[workshop_ids[1]]['efficiency']
        
        eff_diff = eff1 - eff2
        
        if eff_diff > 0:
            eff_text = f"Workshop {workshop_ids[0]} is more efficient at {eff1:.1f}% vs {eff2:.1f}%"
        elif eff_diff < 0:
            eff_text = f"Workshop {workshop_ids[1]} is more efficient at {eff2:.1f}% vs {eff1:.1f}%"
        else:
            eff_text = f"Both workshops have equal efficiency: {eff1:.1f}%"
            
        response_parts.append(f"Efficiency: {eff_text}")
    
    # Add sample size information
    response_parts.append(f"Records analyzed: Workshop {workshop_ids[0]}: {workshop_data[workshop_ids[0]]['records']}, Workshop {workshop_ids[1]}: {workshop_data[workshop_ids[1]]['records']}")
    
    return " | ".join(response_parts)

# Helper for safely extracting numeric values from document fields
def safe_get_numeric(record, field_names, default=0):
    """Safely extract a numeric value from a record using multiple possible field names"""
    for field in field_names:
        if field in record:
            try:
                return float(record[field])
            except (ValueError, TypeError):
                continue
    return default

# Add a new function to extract specific defect type from a question
def extract_defect_type_from_question(text):
    """Extract specific defect type from a question"""
    # Common patterns for questions about specific defect types
    specific_defect_pattern = re.compile(r'how\s+many\s+([a-zA-Z\s]+?)\s+(defects?|issues?|problems?|reported|found)', re.IGNORECASE)
    match = specific_defect_pattern.search(text)
    
    if match:
        defect_type = match.group(1).strip().lower()
        print(f"Extracted specific defect type from question: '{defect_type}'")
        return defect_type
    
    return None

# Function to query for a specific defect type
def query_specific_defect_type(defect_type):
    """Query for a specific defect type and return its count and statistics"""
    try:
        if mongodb_available and 'performance3' in available_collections:
            # Get recent records with defect types
            results = list(db.performance3.find({}, {'defects': 1, 'defectTypes': 1, 'date': 1}).sort('date', -1).limit(100))
            
            if not results:
                return f"No data found for defect type: {defect_type}"
            
            total_records = len(results)
            total_of_specific_defect = 0
            total_defects = 0
            
            # Count the specific defect type
            for record in results:
                if 'defectTypes' in record and isinstance(record['defectTypes'], dict):
                    for d_type, count in record['defectTypes'].items():
                        # Case insensitive partial match for the defect type
                        if defect_type in d_type.lower():
                            try:
                                count_value = float(count)
                                total_of_specific_defect += count_value
                            except (ValueError, TypeError):
                                continue
                
                # Add to total defects
                total_defects += float(record.get('defects', 0))
            
            # Format response
            if total_of_specific_defect > 0:
                percentage = (total_of_specific_defect / total_defects * 100) if total_defects > 0 else 0
                return f"{defect_type.title()} defects reported: {total_of_specific_defect:.0f} ({percentage:.1f}% of all defects)"
            else:
                return f"No {defect_type} defects found in the last {total_records} records."
                
        return f"No data available to check for {defect_type} defects."
        
    except Exception as e:
        print(f"Error querying specific defect type: {e}")
        return f"Error retrieving information for {defect_type} defects: {str(e)}"

@app.route("/chatbot", methods=["POST"])
def chatbot():
    data = request.get_json()
    message = data.get("message", "").lower()
    user_id = data.get("user_id", "anonymous")  # Get user_id from request or use 'anonymous'
    
    print(f"Received message: '{message}'")
    
    # First, analyze the question using the neural intent model
    analysis = analyze_question(message)
    
    # Check if we have a defect question about a specific defect type
    if "defects" in analysis['metrics']:
        specific_defect_type = extract_defect_type_from_question(message)
        if specific_defect_type:
            print(f"Detected specific defect type query for: {specific_defect_type}")
            response = query_specific_defect_type(specific_defect_type)
            save_conversation(user_id, message, response, "defects")
            return {"response": response}
        
        # Check for special types of defect queries that need specialized handlers
        question_types = {
            'defect_types': re.compile(r'(what|which|list|show).*(types?|kinds?|categories?|common)\s+(?:of\s+)?defects', re.IGNORECASE),
            'defect_most_common': re.compile(r'(most\s+common|main|primary|principal)\s+defects?', re.IGNORECASE),
            'defect_stats': re.compile(r'(defect\s*stats|defect\s*statistics|statistics\s+(?:of|for|about)\s+defects)', re.IGNORECASE)
        }
        
        for q_type, pattern in question_types.items():
            if pattern.search(message):
                if q_type == 'defect_types':
                    response = query_defect_types()
                elif q_type == 'defect_most_common':
                    response = query_most_common_defects()
                elif q_type == 'defect_stats':
                    response = query_defect_statistics()
                
                save_conversation(user_id, message, response, "defects")
                return {"response": response}
    
    # If no metrics were identified, it's possible that the model didn't recognize the intent
    if not analysis['metrics']:
        return {"response": "I'm sorry, I didn't understand that question. Could you please rephrase it?"}
    
    # Query the database and get response
    response = query_database(analysis)
    
    # Determine intent from the metrics
    intent = "unknown"
    if "defects" in analysis['metrics']:
        intent = "defects"
    elif "failures" in analysis['metrics']:
        intent = "failures"
    elif "order" in analysis['metrics']:
        intent = "orders"
    elif "production" in analysis['metrics'] or "efficiency" in analysis['metrics']:
        intent = "performance"
    
    # Save conversation
    save_conversation(user_id, message, response, intent)
    
    return {"response": response}

def save_conversation(user_id, question, response, intent):
    """Save the conversation to MongoDB"""
    if mongodb_available and db is not None:
        try:
            # Create a document with the conversation data
            conversation_doc = {
                "user_id": user_id,
                "question": question,
                "response": response,
                "timestamp": datetime.utcnow(),
                "intent": intent
            }
            
            # Insert into the chatbot_conversations collection
            db.chatbot_conversations.insert_one(conversation_doc)
            print(f"Saved chatbot conversation for user {user_id}")
        except Exception as e:
            print(f"Error saving chatbot conversation: {str(e)}")
    
def query_defect_statistics():
    """Query and return detailed defect statistics"""
    try:
        if mongodb_available:
            # Try to get defect data from performance collection
            if 'performance3' in available_collections:
                # Get recent defect data 
                pipeline = [
                    {
                        "$project": {
                            "defects": 1,
                            "produced": 1,
                            "date": 1,
                            "workshop": 1,
                            "defectTypes": 1
                        }
                    },
                    {
                        "$sort": {"date": -1}
                    },
                    {
                        "$limit": 100
                    }
                ]
                
                results = list(db.performance3.aggregate(pipeline))
                
                if not results:
                    return "No defect statistics found in the database."
                
                # Calculate basic statistics
                total_records = len(results)
                total_defects = sum(float(r.get('defects', 0)) for r in results)
                total_production = sum(float(r.get('produced', 0)) for r in results)
                
                # Calculate defect rate
                defect_rate = (total_defects / total_production * 100) if total_production > 0 else 0
                
                # Get defect types breakdown if available
                defect_type_counts = {}
                for record in results:
                    if 'defectTypes' in record and isinstance(record['defectTypes'], dict):
                        for defect_type, count in record['defectTypes'].items():
                            try:
                                count_value = float(count)
                                if count_value > 0:
                                    defect_type_counts[defect_type] = defect_type_counts.get(defect_type, 0) + count_value
                            except (ValueError, TypeError):
                                continue
                
                # Format the response
                response_parts = [f"Defect Statistics (based on {total_records} recent records):"]
                response_parts.append(f"• Total defects: {total_defects:.0f}")
                response_parts.append(f"• Total production: {total_production:.0f} units")
                response_parts.append(f"• Overall defect rate: {defect_rate:.2f}%")
                
                # Add defect types breakdown if available
                if defect_type_counts:
                    response_parts.append("\nDefect types breakdown:")
                    sorted_defects = sorted(defect_type_counts.items(), key=lambda x: x[1], reverse=True)
                    for defect_type, count in sorted_defects[:5]:  # Show top 5
                        percentage = (count / total_defects * 100) if total_defects > 0 else 0
                        response_parts.append(f"• {defect_type}: {count:.0f} ({percentage:.1f}%)")
                
                # Add workshop breakdown if available
                workshop_defects = {}
                for record in results:
                    if 'workshop' in record:
                        workshop = record.get('workshop', 'Unknown')
                        defects = float(record.get('defects', 0))
                        if workshop not in workshop_defects:
                            workshop_defects[workshop] = 0
                        workshop_defects[workshop] += defects
                
                if len(workshop_defects) > 1:  # Only show if we have multiple workshops
                    response_parts.append("\nDefects by workshop:")
                    sorted_workshops = sorted(workshop_defects.items(), key=lambda x: x[1], reverse=True)
                    for workshop, count in sorted_workshops:
                        percentage = (count / total_defects * 100) if total_defects > 0 else 0
                        response_parts.append(f"• {workshop}: {count:.0f} ({percentage:.1f}%)")
                
                return "\n".join(response_parts)
            
            return "No defect data found in the system."
        
        return "Database not available for querying defect statistics."
    except Exception as e:
        print(f"Error querying defect statistics: {e}")
        return f"Error retrieving defect statistics: {str(e)}"

@app.route("/chatbot/diagnostics", methods=["GET"])
def diagnostics():
    """Diagnostic endpoint to help with database field mapping"""
    # Check connections
    global client, db, mongodb_available, available_collections
    
    if not mongodb_available:
        # Try to reconnect
        retry_client, retry_db, success, collections = connect_to_mongodb(max_retries=1)
        if success:
            client = retry_client
            db = retry_db
            mongodb_available = True
            available_collections = collections
    
    if not mongodb_available:
        return {"status": "error", "message": "Database connection unavailable"}
    
    # Run diagnostics
    try:
        results = {
            "status": "success",
            "connection": "available",
            "collections": available_collections,
            "field_analysis": {}
        }
        
        # Sample a few collections
        collections_to_check = available_collections[:3]  # First 3 collections
        
        for collection_name in collections_to_check:
            try:
                coll = db[collection_name]
                sample = coll.find_one()
                
                if not sample:
                    results["field_analysis"][collection_name] = "No documents found"
                    continue
                
                # List all fields
                fields = list(sample.keys())
                
                # Categorize fields by likely usage
                field_categories = {
                    "date_fields": [],
                    "workshop_fields": [],
                    "production_fields": [],
                    "order_fields": [],
                    "technician_fields": []
                }
                
                for field in fields:
                    field_lower = field.lower()
                    
                    # Categorize by name patterns
                    if any(keyword in field_lower for keyword in ["date", "time", "day"]):
                        field_categories["date_fields"].append(field)
                    elif any(keyword in field_lower for keyword in ["workshop", "shop", "line"]):
                        field_categories["workshop_fields"].append(field)
                    elif any(keyword in field_lower for keyword in ["prod", "output", "units", "defect"]):
                        field_categories["production_fields"].append(field)
                    elif any(keyword in field_lower for keyword in ["order", "ref"]):
                        field_categories["order_fields"].append(field)
                    elif any(keyword in field_lower for keyword in ["tech", "worker", "name"]):
                        field_categories["technician_fields"].append(field)
                
                # Get example values
                example_values = {}
                for category, category_fields in field_categories.items():
                    if category_fields:
                        example_values[category] = {}
                        for field in category_fields:
                            if field in sample:
                                example_values[category][field] = str(sample[field])
                
                results["field_analysis"][collection_name] = {
                    "fields": fields,
                    "categories": field_categories,
                    "examples": example_values
                }
                
            except Exception as e:
                results["field_analysis"][collection_name] = f"Error: {str(e)}"
        
        return results
    
    except Exception as e:
        return {"status": "error", "message": f"Diagnostics failed: {str(e)}"}

@app.route("/chatbot/history/<user_id>", methods=["GET"])
def get_conversation_history(user_id):
    """Get the conversation history for a specific user"""
    if not mongodb_available or db is None:
        return {"status": "error", "message": "Database connection unavailable"}
    
    try:
        # Query the chatbot_conversations collection for this user
        conversations = list(db.chatbot_conversations.find(
            {"user_id": user_id},
            {"_id": 0}  # Exclude MongoDB _id field from results
        ).sort("timestamp", -1).limit(50))  # Get latest 50 conversations
        
        # Convert datetime objects to string for JSON serialization
        for conv in conversations:
            if "timestamp" in conv and isinstance(conv["timestamp"], datetime):
                conv["timestamp"] = conv["timestamp"].isoformat()
        
        return {
            "status": "success", 
            "conversations": conversations,
            "count": len(conversations)
        }
    
    except Exception as e:
        print(f"Error fetching conversation history: {str(e)}")
        return {"status": "error", "message": f"Failed to fetch conversation history: {str(e)}"}

if __name__ == "__main__":
    print("Starting chatbot service on port 5001...")
    app.run(host='0.0.0.0', port=5001, debug=True)
