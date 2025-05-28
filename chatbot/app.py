from flask import Flask, request
from flask_cors import CORS
from pymongo import MongoClient
import re
from datetime import datetime, timedelta, UTC
import nltk
from nltk.tokenize import word_tokenize
from nltk.corpus import stopwords
from nltk.stem import WordNetLemmatizer
import numpy as np
import time  # Add this import for sleep functionality
import os # Import os module
from predict_intent import IntentPredictor
from bson import ObjectId

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

# Instantiate the intent predictor (adjust model_dir if needed)
intent_predictor = IntentPredictor(model_dir='models')

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
    
    # Extract explicit dates (YYYY-MM-DD)
    date_match = re.search(r'\b(\d{4}-\d{2}-\d{2})\b', text)
    if date_match:
        return {'type': 'exact_date', 'value': date_match.group(1)}
    
    # NEW: Extract dates like 'May 9th, 2025' or 'May 9, 2025'
    month_names = ['january', 'february', 'march', 'april', 'may', 'june', 'july', 'august', 'september', 'october', 'november', 'december']
    month_regex = r'(' + '|'.join(month_names) + r')\s+(\d{1,2})(?:st|nd|rd|th)?[ ,]*?(\d{4})'
    match = re.search(month_regex, text.lower())
    if match:
        month_name = match.group(1)
        day = int(match.group(2))
        year = int(match.group(3))
        month_num = month_names.index(month_name) + 1
        return {'type': 'exact_date', 'value': f'{year:04d}-{month_num:02d}-{day:02d}'}
    
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
    
    # Handle month names (January, February, etc.)
    month_pattern = r'(january|february|march|april|may|june|july|august|september|october|november|december)'
    month_match = re.search(month_pattern, text.lower())
    if month_match:
        month_name = month_match.group(1)
        month_num = {
            'january': 1, 'february': 2, 'march': 3, 'april': 4,
            'may': 5, 'june': 6, 'july': 7, 'august': 8,
            'september': 9, 'october': 10, 'november': 11, 'december': 12
        }[month_name]
        
        # Check if year is specified
        year_match = re.search(r'\b(20\d{2})\b', text)
        year = int(year_match.group(1)) if year_match else today.year
        
        # If the month is in the future and no year specified, assume last year
        if month_num > today.month and not year_match:
            year = today.year - 1
            
        # Create date range for the entire month
        first_day = datetime(year, month_num, 1)
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
            'description': month_name
        }
    
    # Handle 'last week' specifically
    last_week_pattern = r'\blast\s+week\b'
    if re.search(last_week_pattern, text, re.IGNORECASE):
        today = datetime.now()
        # Calculate the start and end of last week (Monday to Sunday)
        start_of_this_week = today - timedelta(days=today.weekday())
        start_of_last_week = start_of_this_week - timedelta(days=7)
        end_of_last_week = start_of_this_week - timedelta(days=1)
        return {
            'type': 'relative_date',
            'value': {
                'start': start_of_last_week.strftime('%Y-%m-%d'),
                'end': end_of_last_week.strftime('%Y-%m-%d')
            },
            'description': 'last week'
        }
    
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
        'defect_query_type': None  # New field to track defect query types
    }
    
    # Detect defect query types first - this is important for specialized handling
    defect_patterns = {
        'defect_types': [
            r'what\s+(are|is)\s+the\s+(type|kind)s?\s+of\s+defects',
            r'defect\s+(types?|categories|classification)',
            r'(list|show|get|find)\s+(all|me|the)?\s+defect\s+(types?|categories)',
            r'what\s+(defect|quality issue)\s+(types?|categories|kinds?)',
            r'(types?|categories|kinds?)\s+of\s+defects',
        ],
        'defect_names': [
            r'(list|show|get|find)\s+(all|me|the)?\s+defect\s+names',
            r'what\s+(are|is)\s+the\s+names?\s+of\s+defects',
            r'defect\s+names',
            r'names\s+of\s+defects',
        ],
        'defect_statistics': [
            r'(statistics|stats|metrics|analytics|numbers|figures)\s+of\s+defects',
            r'defect\s+(statistics|stats|metrics|analytics|numbers|figures)',
            r'(summarize|analyze)\s+defects',
            r'defect\s+(count|summary|analysis|overview)',
            r'(how\s+many|number\s+of)\s+defects',
        ],
        'defect_distribution': [
            r'(distribution|spread|breakdown)\s+of\s+defects',
            r'defect\s+(distribution|spread|breakdown|by\s+type)',
            r'(most\s+common|frequent)\s+defects?',
            r'(group|categorize)\s+defects',
            r'defects?\s+by\s+(type|category|workshop|date)'
        ],
        'defect_trend': [
            r'defect\s+(trend|pattern|evolution|progress|development)',
            r'(trend|pattern|evolution|progress|development)\s+of\s+defects',
            r'(change|increase|decrease|improvement)\s+in\s+defects',
            r'defects?\s+(over\s+time|compared)',
            r'how\s+are\s+defects\s+(changing|evolving|developing)'
        ],
        'specific_defect': [
            r'(show|find|get|how\s+many|number\s+of)\s+(\w+)\s+defects',
            r'defects?\s+of\s+type\s+(\w+)',
            r'(\w+)\s+(defects?|quality\s+issues?)',
            r'information\s+(about|on)\s+(\w+)\s+defects?'
    ]
    }
    
    # Check for defect query patterns
    for query_type, patterns in defect_patterns.items():
        for pattern in patterns:
            match = re.search(pattern, text, re.IGNORECASE)
            if match:
                analysis['metrics'].add('defects')
                analysis['defect_query_type'] = query_type
                # For specific defect type queries, extract the defect type
                if query_type == 'specific_defect' and len(match.groups()) > 1:
                    defect_type = match.group(2)
                    if defect_type and defect_type.lower() not in ['all', 'any', 'these', 'those', 'the']:
                        analysis['filters']['defect_type'] = defect_type
                # Set appropriate math operation based on query type
                if query_type == 'defect_statistics':
                    analysis['math_operation'] = 'sum'
                elif query_type == 'defect_distribution':
                    analysis['math_operation'] = 'distribution'
                elif query_type == 'defect_trend':
                    analysis['math_operation'] = 'trend'
                print(f"Detected defect query type: {query_type}")
                if 'defect_type' in analysis['filters']:
                    print(f"Specific defect type: {analysis['filters']['defect_type']}")
            break
        # If we found a match, no need to check other patterns
        if analysis['defect_query_type']:
            break
    # If we detect "defects" but no specific query type, set a default
    if 'defects' in analysis['metrics'] and not analysis['defect_query_type']:
        analysis['defect_query_type'] = 'defect_statistics'
        analysis['math_operation'] = 'sum'
        print("Setting default defect query type to statistics")
            
    # Detect intent for machine failures or interventions specifically
    failure_patterns = [
        r'(machine|equipment)[^\w]*(failures?|breakdowns?|issues?|problems?|failed)',
        r'(failures?|breakdowns?)\s+of\s+(machines?|equipment)',
        r'(show|display|get|list|find)[^\w]*.*(machine|equipment)[^\w]*(failures?|breakdowns?)',
        r'(distribution|spread|statistics)[^\w]*of[^\w]*(machine|equipment)[^\w]*(failures?|breakdowns?)',
        r'how many[^\w]*(machines?|equipment)[^\w]*(failed|failures?|breakdowns?)',
        r'intervention(s)?',
    ]
    for pattern in failure_patterns:
        if re.search(pattern, text, re.IGNORECASE):
            analysis['metrics'].add('failures')
            print("Detected machine failure/intervention query intent")
            # Check if this is a distribution/statistics query
            if re.search(r'distribution|spread|statistics', text, re.IGNORECASE):
                analysis['math_operation'] = 'distribution'
                print("Setting math operation to distribution for failure statistics")
            break
    
    # Detect compare/comparison operations
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
    else:
        # Check for simpler comparison pattern
        simple_compare = re.search(r'compare\s+(\w+)\s+(\d+)\s+and\s+(\d+)', text, re.IGNORECASE)
        if simple_compare:
            entity_type = simple_compare.group(1)
            id1 = simple_compare.group(2)
            id2 = simple_compare.group(3)
            
            # Set comparison type
            analysis['calculation_type'] = 'comparison'
            analysis['comparison'] = {
                'entity_type': entity_type,
                'ids': [id1, id2]
            }
            
            # Add default metrics
            analysis['metrics'].update(['production', 'defects', 'efficiency'])
            
            print(f"Detected simple comparison: {analysis['comparison']}")
    
    # If no specific comparison pattern found, check for generic comparison words
    if analysis['comparison'] is None and not analysis['calculation_type']:
        workshop_compare = re.search(r'(compare|comparison)\s+.*?(workshop|work shop|shops?)\s+(\d+)\s+and\s+(\d+)', text, re.IGNORECASE)
        if workshop_compare:
            id1 = workshop_compare.group(3)
            id2 = workshop_compare.group(4)
            
            analysis['calculation_type'] = 'comparison'
            analysis['comparison'] = {
                'entity_type': 'workshop',
                'ids': [id1, id2]
            }
            
            # Add default metrics for workshop comparison
            analysis['metrics'].update(['production', 'defects', 'efficiency'])
            
            print(f"Detected workshop comparison: {analysis['comparison']}")
    
    # Detect special metrics like defect rate with averages
    defect_rate_patterns = [
        r'(average|mean|avg).*?defect\s+rate',
        r'defect\s+rate.*?(average|mean|avg)',
        r'(calculate|compute|what\s+is)\s+(?:the\s+)?(average|mean|avg).*?defect\s+rate'
    ]
    
    for pattern in defect_rate_patterns:
        if re.search(pattern, text, re.IGNORECASE):
            analysis['metrics'].add('defects')
            analysis['metrics'].add('production')
            analysis['calculation_type'] = 'defect_rate'
            analysis['math_operation'] = 'average'
            print("Detected average defect rate calculation")
            break
            
    # Fix for the defect rate check - properly handling the calculation_type field
    calc_type = analysis.get('calculation_type')
    has_defect_rate_calculation_type = (calc_type is not None and 'defect_rate' in calc_type)
    
    # Regular defect rate without average
    if not has_defect_rate_calculation_type and re.search(r'defect\s+rate', text, re.IGNORECASE):
        analysis['metrics'].add('defects')
        analysis['metrics'].add('production')
        analysis['calculation_type'] = 'defect_rate'
        
        # Check for highest/lowest
        if re.search(r'highest|max|maximum|worst', text, re.IGNORECASE):
            # Initialize comparison field if it's still None
            if analysis['comparison'] is None:
                analysis['comparison'] = 'highest'
            # Otherwise it could be a dictionary from previous processing
            elif isinstance(analysis['comparison'], str):
                analysis['comparison'] = 'highest'
        elif re.search(r'lowest|min|minimum|best', text, re.IGNORECASE):
            # Initialize comparison field if it's still None
            if analysis['comparison'] is None:
                analysis['comparison'] = 'lowest'
            # Otherwise it could be a dictionary from previous processing
            elif isinstance(analysis['comparison'], str):
                analysis['comparison'] = 'lowest'
            
        print(f"Detected defect rate calculation with comparison: {analysis['comparison']}")
    
    # Handle "past week" or time-based filters
    if re.search(r'past\s+week', text, re.IGNORECASE):
        # Calculate date range for past week
        today = datetime.now()
        one_week_ago = today - timedelta(days=7)
        analysis['date_info'] = {
            'type': 'relative_date',
            'value': {
                'start': one_week_ago.strftime('%Y-%m-%d'),
                'end': today.strftime('%Y-%m-%d')
            }
        }
        print(f"Set date range for past week: {analysis['date_info']}")
    
    # Better detection of efficiency rate calculations
    efficiency_rate_patterns = [
        r'(?:efficiency|performance)\s+rate\s+per\s+(hour|day|week|month)',
        r'(?:calculate|compute|what\s+is)\s+(?:the\s+)?(?:efficiency|performance)\s+(?:rate\s+)?per\s+(hour|day|week|month)',
        r'(?:hourly|daily|weekly|monthly)\s+(?:efficiency|performance)\s+rate',
        r'(?:production|output)\s+rate\s+per\s+(hour|day|week|month)'
    ]
    
    for pattern in efficiency_rate_patterns:
        match = re.search(pattern, text, re.IGNORECASE)
        if match:
            # Extract the time period if available in the pattern
            time_group = match.groups()
            if time_group and time_group[0]:
                period = time_group[0].lower()
            # Otherwise detect from other patterns
            elif 'hourly' in text.lower() or 'per hour' in text.lower():
                period = 'hour'
            elif 'daily' in text.lower() or 'per day' in text.lower():
                period = 'day'
            elif 'weekly' in text.lower() or 'per week' in text.lower():
                period = 'week'
            elif 'monthly' in text.lower() or 'per month' in text.lower():
                period = 'month'
            else:
                period = 'hour'  # Default to hour
                
            analysis['metrics'].add('efficiency')
            analysis['calculation_type'] = 'efficiency_rate'
            analysis['time_period'] = period
            analysis['math_operation'] = 'rate'
            print(f"Detected efficiency rate calculation per {period}")
            break
    
    # Determine if this is a calculation query
    calculation_keywords = ['calculate', 'compute', 'sum', 'average', 'mean', 'percentage', 
                           'percent', 'trend', 'rate', 'distribution', 'statistics', 
                           'efficiency', 'performance']
    
    if any(keyword in text.lower() for keyword in calculation_keywords) and not analysis['calculation_type']:
        analysis['math_operation'] = extract_math_operation(text)
        
        # If we detect a rate calculation for efficiency
        if analysis['math_operation'] == 'rate' and 'efficiency' in text.lower():
            # Add efficiency to metrics
            analysis['metrics'].add('efficiency')
            
            # Extract time period
            time_period = 'hour'  # default
            if re.search(r'per day|daily', text, re.IGNORECASE):
                time_period = 'day'
            elif re.search(r'per week|weekly', text, re.IGNORECASE):
                time_period = 'week'
            elif re.search(r'per month|monthly', text, re.IGNORECASE):
                time_period = 'month'
                
            analysis['time_period'] = time_period
            analysis['calculation_type'] = 'efficiency_rate'
            print(f"Detected efficiency rate calculation per {time_period}")
    
    # Extract metrics using generic patterns
    metric_patterns = {
        'production': r'production|output|produced|units|quantity|manufactured',
        'performance': r'performance|efficiency|productivity|yield|production',
        'defects': r'defects?|errors?|quality issues?|reject|faulty',
        'efficiency': r'efficiency|performance|productivity|yield',
        'failures': r'failures?|breakdowns?|maintenance|repairs?|malfunction',
        'target': r'target|goal|objective|plan',
        'variance': r'variance|deviation|difference|gap'
    }
    
    # Check for general keywords related to each metric
    for metric, pattern in metric_patterns.items():
        if re.search(pattern, text, re.IGNORECASE):
            analysis['metrics'].add(metric)
    
    # Extract filters using generic patterns
    filter_patterns = {
        'workshop': r'workshop\s*(\d+)|(\d+)\s*(?:st|nd|rd|th)?\s*workshop|work\s*shop\s*(\d+)',
        'machine': r'machine\s+(?:id|reference|ref|number)?\s*([a-zA-Z0-9\-]+)|([a-zA-Z0-9\-]+)\s*machine',
        'technician': r'(?:technician|handled by|fixed by|repaired by|engineer)\s+([^\s,.?!][^,.?!]*)',
        'order': r'order\s*(?:reference|ref)?\s*#?\s*(\d+)|order\s*(?:number|num|no)\s*#?\s*(\d+)',
        'chain': r'chain\s*(\d+)|chain\s*([a-zA-Z0-9\-]+)|(\d+)\s*(?:st|nd|rd|th)?\s*chain',
        'hour': r'(?:at|during|hour)\s*(\d{1,2})(?:\s*(?:am|pm|h|hour|:00))?|(\d{1,2})\s*(?:am|pm|h|hour|o\'clock)'
    }
    
    # Check for workshop mentions in comparison contexts
    if isinstance(analysis['comparison'], dict) and analysis['comparison'].get('entity_type') == 'workshop':
        workshop_ids = analysis['comparison'].get('ids', [])
        if workshop_ids:
            # Don't add as a filter, as we need both workshops for comparison
            print(f"Found workshop IDs for comparison: {workshop_ids}")
            
    # Extract all filters except machine if it's a general machine failures query
    for filter_type, pattern in filter_patterns.items():
        # Skip machine filter for general machine failures query
        if filter_type == 'machine' and 'failures' in analysis['metrics'] and not re.search(r'for machine|by machine|specific machine', text, re.IGNORECASE):
            print("Query is about general machine failures, not filtering by specific machine")
            continue
        match = re.search(pattern, text, re.IGNORECASE)
        if match and match.lastindex is not None and match.group(1) is not None:
            # Clean up the matched value
            value = match.group(1).strip()
            # Remove common words and keep only the relevant part
            value = re.sub(r'\b(handled|by|fixed|repaired)\b', '', value, flags=re.IGNORECASE).strip()
            # Special handling for technician
            if filter_type == 'technician':
                # Just extract the name without the word "technician"
                if "technician" in value.lower():
                    value = re.sub(r'technician\s*', '', value, flags=re.IGNORECASE).strip()
                print(f"Extracted technician filter: '{value}'")
                # Add to filters
                analysis['filters'][filter_type] = value
                print(f"Added technician filter to analysis: {analysis['filters']}")
            # Special handling for order
            elif filter_type == 'order':
                print(f"Extracted order reference: '{value}'")
                analysis['filters'][filter_type] = value
            # Special handling for machine: skip if value is 'maintenance', 'failures', 'failure', 'breakdown', or does not look like a real machine reference
            elif filter_type == 'machine':
                generic_words = ['maintenance', 'failures', 'failure', 'breakdown', 'breakdowns', 'issue', 'problem']
                # Only add if it looks like a real machine reference (e.g., contains a dash and starts with 'W')
                if value.lower() in generic_words or '-' not in value or not value.upper().startswith('W'):
                    continue  # Skip adding this as a machine filter
                analysis['filters'][filter_type] = value
            else:
                analysis['filters'][filter_type] = value
    
    # Special handling for last month
    if re.search(r'\blast\s+month\b', text, re.IGNORECASE) and not analysis['date_info']:
        today = datetime.now()
        # Calculate first and last day of previous month
        first_day = (today.replace(day=1) - timedelta(days=1)).replace(day=1)
        last_day = today.replace(day=1) - timedelta(days=1)
        
        analysis['date_info'] = {
            'type': 'relative_date',
            'value': {
                'start': first_day.strftime('%Y-%m-%d'),
                'end': last_day.strftime('%Y-%m-%d')
            }
        }
        print(f"Set date range for last month: {analysis['date_info']}")
    
    # Fallback: If the question contains 'by <technician name>' or 'recorded by <name>' or 'interventions by <name>' and technician filter is not set, extract it
    if 'technician' not in analysis['filters']:
        # Match 'interventions' followed anywhere by 'by' or 'recorded by' and a name
        by_match = re.search(r'interventions.*?(?:recorded by|by)\s+([a-zA-Z0-9_\- ]+)', text, re.IGNORECASE)
        if not by_match:
            # Also match 'recorded by <name>' or 'by <name>' anywhere
            by_match = re.search(r'(?:recorded by|by)\s+([a-zA-Z0-9_\- ]+)', text, re.IGNORECASE)
        if by_match:
            tech_name = by_match.group(1).strip()
            if tech_name:
                analysis['filters']['technician'] = tech_name

    # Fallback: If the question contains 'machine' followed by a reference and machine filter is not set, extract it
    if 'machine' not in analysis['filters']:
        machine_match = re.search(r'machine\s*([a-zA-Z0-9_\-]+)', text, re.IGNORECASE)
        if machine_match:
            machine_ref = machine_match.group(1).strip()
            # Only add if it looks like a real machine reference (contains a dash and starts with 'W')
            if (machine_ref and machine_ref.lower() != 'maintenance'
                and '-' in machine_ref and machine_ref.upper().startswith('W')):
                analysis['filters']['machine'] = machine_ref
    
    # Fallback for defect types/names if not detected by regex
    if not analysis['defect_query_type']:
        if 'defect types' in text.lower():
            analysis['metrics'].add('defects')
            analysis['defect_query_type'] = 'defect_types'
        elif 'defect names' in text.lower():
            analysis['metrics'].add('defects')
            analysis['defect_query_type'] = 'defect_names'
    
    # Patch: Force 'failures' metric for repeated/recurrent issue queries
    repeated_issue_phrases = [
        'most failures', 'most failed', 'highest failures', 'most breakdowns', 'most issues', 'most problems',
        'repeated issues', 'recurring issues', 'repeat failures', 'repeat breakdowns', 'repeat problems', 'repeat issues',
        'machines with repeated issues', 'machines with recurring issues', 'machines with issues more than once', 'machines with multiple failures'
    ]
    if any(phrase in text.lower() for phrase in repeated_issue_phrases):
        analysis['metrics'].discard('defects')
        analysis['metrics'].add('failures')
    
    return analysis

def perform_calculation(data, analysis):
    """Perform mathematical calculations based on the analysis"""
    if not data:
        return {'error': 'No data available for calculations'}
    
    results = {}
    
    try:
        # Special handling for defect rate calculation
        if analysis.get('calculation_type') == 'defect_rate':
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
            production_fields = ['produced', 'production', 'output', 'units', 'quantity', 'producedCount', 'totalProduced']
            time_fields = ['hours', 'duration', 'time', 'workingHours', 'working_hours', 'shiftHours', 'operatingHours']
            efficiency_fields = ['efficiency', 'efficiencyRate', 'efficiency_rate', 'performanceRate', 'performance']
            target_fields = ['target', 'productionTarget', 'production_target', 'targetOutput', 'plannedProduction']
            time_period = analysis.get('time_period', 'hour')
            
            # --- NEW: Hourly breakdown logic ---
            # If the user asked for per hour ("per hour" in question or time_period == 'hour'), group by hour
            original_question = analysis.get('original_question', '')
            wants_hourly = (
                time_period == 'hour' or
                'per hour' in original_question or
                'hourly' in original_question or
                'each hour' in original_question or
                'by hour' in original_question
            )
            # If user specified a date, use it; else, default to today for hourly breakdown
            import datetime
            date_info = analysis.get('date_info')
            if wants_hourly:
                # Build a mapping: hour -> {produced, target}
                hourly = {}
                for record in data:
                    # Extract date and hour
                    date_str = record.get('date', '')
                    hour = None
                    # Try to extract hour from 'hour' field or from date string
                    if 'hour' in record and record['hour'] is not None:
                        hour = str(record['hour']).zfill(2)
                    elif 'timeHour' in record and record['timeHour'] is not None:
                        hour = str(record['timeHour']).zfill(2)
                    elif date_str and 'T' in date_str:
                        # ISO format: 2025-05-09T13:00:00Z
                        try:
                            hour = date_str.split('T')[1][:2]
                        except Exception:
                            pass
                    # If no hour, skip
                    if not hour:
                        continue
                    # Filter by date if specified
                    if date_info:
                        # If exact date
                        if date_info.get('type') == 'exact_date':
                            if not date_str.startswith(date_info['value']):
                                continue
                        # If relative_date with start/end
                        elif date_info.get('type') == 'relative_date' and isinstance(date_info.get('value'), dict):
                            start = date_info['value'].get('start')
                            end = date_info['value'].get('end')
                            if start and end and (date_str < start or date_str > end):
                                continue
                        # If relative_date with a single value (e.g., today)
                        elif date_info.get('type') == 'relative_date' and isinstance(date_info.get('value'), str):
                            if not date_str.startswith(date_info['value']):
                                continue
                    else:
                        # No date specified: default to today
                        today = datetime.datetime.now().strftime('%Y-%m-%d')
                        if not date_str.startswith(today):
                            continue
                    # Extract produced and target
                    produced = 0
                    target = 0
                    for field in production_fields:
                        if field in record and record[field] is not None:
                            try:
                                produced = float(record[field])
                                break
                            except Exception:
                                pass
                    for field in target_fields:
                        if field in record and record[field] is not None:
                            try:
                                target = float(record[field])
                                break
                            except Exception:
                                pass
                    if hour not in hourly:
                        hourly[hour] = {'produced': 0, 'target': 0}
                    hourly[hour]['produced'] += produced
                    hourly[hour]['target'] += target
                # Calculate efficiency per hour
                hourly_efficiency = {}
                for hour, vals in sorted(hourly.items()):
                    if vals['target'] > 0:
                        eff = (vals['produced'] / vals['target']) * 100
                    else:
                        eff = 0
                    hourly_efficiency[hour] = eff
                results['hourly_efficiency'] = hourly_efficiency
                results['hourly_sample_size'] = sum(1 for v in hourly.values() if v['target'] > 0)
                # Also return overall as before
                total_production = sum(v['produced'] for v in hourly.values())
                total_target = sum(v['target'] for v in hourly.values())
                overall_rate = (total_production / total_target) * 100 if total_target > 0 else 0
                results['overall_rate'] = overall_rate
                results['overall_performance'] = overall_rate
                results['time_period'] = 'hour'
                results['sample_size'] = results['hourly_sample_size']
                return results
            # --- END HOURLY LOGIC ---

            # (Otherwise, default/total efficiency logic as before)
            efficiency_rates = []
            total_production = 0
            total_time = 0
            total_target = 0
            found_fields = {'production': set(), 'time': set(), 'efficiency': set(), 'target': set()}
            for record in data:
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
                time_value = 1.0
                for field in time_fields:
                    if field in record:
                        try:
                            value = record[field]
                            if value is not None:
                                time_value = float(value)
                                break
                        except (ValueError, TypeError):
                            pass
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
                    production_rate = production / time_value
                    date = record.get('date', 'unknown')
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
            overall_rate = total_production / total_time if total_time > 0 else 0
            overall_performance = (total_production / total_target) * 100 if total_target > 0 else None
            efficiency_rates.sort(key=lambda x: x.get('production_rate', 0), reverse=True)
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
    
    # Special handling for average defect rate
    if 'overall_defect_rate' in calc_results:
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
    
    # Special handling for hourly efficiency breakdown
    if 'hourly_efficiency' in calc_results:
        overall_rate = calc_results.get('overall_rate', 0)
        sample_size = calc_results.get('sample_size', 0)
        response_parts.append(f"Hourly Efficiency Rate (based on {sample_size} hours):")
        hourly = calc_results['hourly_efficiency']
        for hour, eff in sorted(hourly.items()):
            response_parts.append(f"Hour {hour}: {eff:.2f}%")
        response_parts.append(f"Overall efficiency: {overall_rate:.2f}%")
        return " | ".join(response_parts)
    
    return " | ".join(response_parts) if response_parts else "Could not format the calculation results."

def build_mongodb_query(analysis):
    """Build a MongoDB query based on the analysis without hardcoded field names"""
    query = {}
    # Add date filters
    if analysis['date_info']:
        date_info = analysis['date_info']
        if date_info['type'] == 'exact_date':
            date_value = date_info['value']
            query['$or'] = [
                {'date': date_value},
                {'date': {'$regex': f"^{date_value}"}}
            ]
        elif date_info['type'] == 'relative_date':
            if isinstance(date_info['value'], dict):
                start_date = date_info['value']['start']
                end_date = date_info['value']['end']
                query['$or'] = [
                    {'date': {'$gte': start_date, '$lte': end_date}},
                    {'date': {'$regex': f"^({start_date}|{end_date})"}}
                ]
            else:
                query['date'] = date_info['value']
    # Add other filters with case-insensitive search
    for filter_type, value in analysis['filters'].items():
        if filter_type == 'technician':
            print(f"Building technician query for: '{value}'")
            query['$or'] = [
                {'technicianName': {'$regex': f"^{re.escape(value)}$", '$options': 'i'}},
                {'technician_name': {'$regex': f"^{re.escape(value)}$", '$options': 'i'}},
                {'technician': {'$regex': f"^{re.escape(value)}$", '$options': 'i'}},
                {'repairTechnician': {'$regex': f"^{re.escape(value)}$", '$options': 'i'}},
                {'engineer': {'$regex': f"^{re.escape(value)}$", '$options': 'i'}},
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
                {'machineId': {'$regex': value, '$options': 'i'}},
                {'equipment_id': {'$regex': value, '$options': 'i'}}
            ]
        elif filter_type == 'order':
            query['$or'] = [
                {'orderRef': value},
                {'order_reference': value},
                {'orderReference': value},
                {'order_ref': value},
                {'order': value},
                {'orderId': value},
                {'order_id': value},
                {'orderRef': int(value)} if value.isdigit() else {},
                {'order_reference': int(value)} if value.isdigit() else {},
                {'orderReference': int(value)} if value.isdigit() else {},
                {'order_ref': int(value)} if value.isdigit() else {},
                {'order': int(value)} if value.isdigit() else {},
                {'orderId': int(value)} if value.isdigit() else {},
                {'order_id': int(value)} if value.isdigit() else {}
            ]
            query['$or'] = [q for q in query['$or'] if q]
        elif filter_type == 'chain':
            query['chain'] = {'$regex': value, '$options': 'i'}
    return query

def format_response(data, analysis):
    print(f"[DEBUG] format_response called with metrics: {analysis['metrics']}, filters: {analysis['filters']}, date_info: {analysis.get('date_info')}")
    """Format the response based on the data and analysis"""
    if not data:
        print("[DEBUG] Returning from format_response: no data")
        if 'failures' in analysis['metrics']:
            if 'machine' in analysis['filters']:
                return "there's no failures"
            if analysis.get('date_info'):
                return "there's no record"
            return "No machine failures found matching your criteria."
        if 'defects' in analysis['metrics']:
            if 'defect_type' in analysis['filters']:
                return f"No defect data found for type '{analysis['filters']['defect_type']}'. Please check the defect type or try a different query."
            return "No defect data found matching your criteria."
        if 'order' in analysis['filters']:
            return f"No data found for order {analysis['filters']['order']}. Please check the order reference number and try again."
        return "No data found matching your criteria."
    response_parts = []
    
    # Handle defects specifically
    if 'defects' in analysis['metrics'] and analysis.get('defect_query_type'):
        defect_query_type = analysis.get('defect_query_type')
        
        # Handle defect query types in different ways
        if defect_query_type == 'defect_statistics':
            total_records = len(data)
            total_defects = sum(safe_get_numeric(d, ['defects', 'qualityIssues', 'defect_count', 'defectCount']) for d in data)
            response_parts.append(f"Total defects: {total_defects:.0f}")
            
            # Check for workshop filter
            if 'workshop' in analysis['filters']:
                workshop = analysis['filters']['workshop']
                response_parts.append(f"Workshop: {workshop}")
            
            # Check for date info
            if analysis['date_info']:
                date_info = analysis['date_info']
                if date_info['type'] == 'exact_date':
                    response_parts.append(f"Date: {date_info['value']}")
                elif date_info['type'] == 'relative_date':
                    if isinstance(date_info['value'], dict):
                        response_parts.append(f"Date range: {date_info['value']['start']} to {date_info['value']['end']}")
                    else:
                        response_parts.append(f"Date: {date_info['value']}")
            
            # Add defect density/rate if we can calculate it
            total_production = sum(safe_get_numeric(d, ['produced', 'production', 'producedCount', 'totalProduction']) for d in data)
            if total_production > 0:
                defect_rate = (total_defects / total_production) * 100
                response_parts.append(f"Defect rate: {defect_rate:.2f}%")
                response_parts.append(f"Total production: {total_production:.0f} units")
        
        # For other defect query types, just use the default handling
        
        return " | ".join(response_parts)
    
    # Handle machine failures/interventions specifically
    if 'failures' in analysis['metrics']:
        import datetime
        original_question = analysis.get('original_question', '')
        # Special handling for 'most failures' queries
        repeated_issue_phrases = [
            'most failures', 'most failed', 'highest failures', 'most breakdowns', 'most issues', 'most problems',
            'repeated issues', 'recurring issues', 'repeat failures', 'repeat breakdowns', 'repeat problems', 'repeat issues',
            'machines with repeated issues', 'machines with recurring issues', 'machines with issues more than once', 'machines with multiple failures'
        ]
        if any(phrase in original_question.lower() for phrase in repeated_issue_phrases):
            # Group by machineReference and count
            failure_fields = {
                'machine': ['machineReference', 'machine_id', 'machine', 'machineId', 'equipment_id'],
            }
            machine_counts = {}
            missing_count = 0
            for failure in data:
                machine_id = None
                for field in failure_fields['machine']:
                    if field in failure and failure[field]:
                        machine_id = str(failure[field])
                        break
                if not machine_id:
                    missing_count += 1
                    continue  # Still skip, but count how many are missing
                machine_counts[machine_id] = machine_counts.get(machine_id, 0) + 1
            if not machine_counts and missing_count > 0:
                return "No machine reference information available for these failures."
            elif not machine_counts:
                return "No machine failures found for this period."
            # Find the max count
            max_count = max(machine_counts.values())
            top_machines = [m for m, c in machine_counts.items() if c == max_count]
            response = f"Machine with the most failures this period: {', '.join(top_machines)} ({max_count} failures each)"
            return response
        # If the question is about total time spent, sum the time fields
        if any(kw in original_question.lower() for kw in ['total time spent', 'sum time spent', 'total maintenance time']):
            total_time = 0
            for doc in data:
                for field in ['timeSpent', 'time_spent', 'repair_time', 'maintenance_time', 'duration']:
                    if field in doc:
                        try:
                            total_time += float(doc[field])
                        except Exception:
                            pass
            return f"Total time spent on machine maintenance: {total_time:.0f} minutes"
        # If technician filter is present, list interventions for that technician
        if 'technician' in analysis['filters']:
            technician = analysis['filters']['technician'].replace(' ', '').lower()
            # Only include records where any technician field matches
            def matches_technician(doc):
                for field in ['technicianName', 'technician_name', 'technician', 'technicianId', 'technician_id']:
                    if field in doc and isinstance(doc[field], str):
                        if doc[field].replace(' ', '').lower() == technician:
                            return True
                return False
            filtered_data = [doc for doc in data if matches_technician(doc)]
            # Sort data by date descending if possible
            def get_date(doc):
                for field in ['date', 'breakdown_date', 'maintenance_date', 'failure_date', 'reportDate']:
                    if field in doc:
                        return str(doc[field])
                return ''
            sorted_data = sorted(filtered_data, key=get_date, reverse=True)
            original_question = analysis.get('original_question', '')
            if 'recent' in original_question.lower():
                # Filter to current week (Monday to today)
                today = datetime.datetime.now().date()
                monday = today - datetime.timedelta(days=today.weekday())
                def is_this_week(doc):
                    date_str = get_date(doc)
                    try:
                        date_obj = datetime.datetime.fromisoformat(date_str[:10]).date()
                        return monday <= date_obj <= today
                    except Exception:
                        return False
                sorted_data = [doc for doc in sorted_data if is_this_week(doc)]
                response_parts.append(f"Recent interventions by {analysis['filters']['technician']}:")
            else:
                response_parts.append(f"Interventions by {analysis['filters']['technician']}:")
            for doc in sorted_data:
                date = ''
                for field in ['date', 'breakdown_date', 'maintenance_date', 'failure_date', 'reportDate']:
                    if field in doc:
                        date = str(doc[field])
                        break
                issue = ''
                for field in ['description', 'issue', 'problem', 'failure_description', 'breakdown_reason']:
                    if field in doc:
                        issue = str(doc[field])
                        break
                time_spent = ''
                for field in ['timeSpent', 'time_spent', 'repair_time', 'maintenance_time', 'duration']:
                    if field in doc:
                        time_spent = str(doc[field])
                        break
                response_parts.append(f"- Date: {date} | Issue: {issue} | Time Spent: {time_spent} minutes")
            return "\n".join(response_parts)
        # If technician filter is present, list interventions for that technician
        if 'technician' in analysis['filters']:
            technician = analysis['filters']['technician'].replace(' ', '').lower()
            # Only include records where any technician field matches
            def matches_technician(doc):
                for field in ['technicianName', 'technician_name', 'technician', 'technicianId', 'technician_id']:
                    if field in doc and isinstance(doc[field], str):
                        if doc[field].replace(' ', '').lower() == technician:
                            return True
                return False
            filtered_data = [doc for doc in data if matches_technician(doc)]
            # Sort data by date descending if possible
            def get_date(doc):
                for field in ['date', 'breakdown_date', 'maintenance_date', 'failure_date', 'reportDate']:
                    if field in doc:
                        return str(doc[field])
                return ''
            sorted_data = sorted(filtered_data, key=get_date, reverse=True)
            original_question = analysis.get('original_question', '')
            if 'recent' in original_question.lower():
                # Filter to current week (Monday to today)
                today = datetime.datetime.now().date()
                monday = today - datetime.timedelta(days=today.weekday())
                def is_this_week(doc):
                    date_str = get_date(doc)
                    try:
                        date_obj = datetime.datetime.fromisoformat(date_str[:10]).date()
                        return monday <= date_obj <= today
                    except Exception:
                        return False
                sorted_data = [doc for doc in sorted_data if is_this_week(doc)]
                response_parts.append(f"Recent interventions by {analysis['filters']['technician']}:")
            else:
                response_parts.append(f"Interventions by {analysis['filters']['technician']}:")
            for doc in sorted_data:
                date = ''
                for field in ['date', 'breakdown_date', 'maintenance_date', 'failure_date', 'reportDate']:
                    if field in doc:
                        date = str(doc[field])
                        break
                issue = ''
                for field in ['description', 'issue', 'problem', 'failure_description', 'breakdown_reason']:
                    if field in doc:
                        issue = str(doc[field])
                        break
                time_spent = ''
                for field in ['timeSpent', 'time_spent', 'repair_time', 'maintenance_time', 'duration']:
                    if field in doc:
                        time_spent = str(doc[field])
                        break
                response_parts.append(f"- Date: {date} | Issue: {issue} | Time Spent: {time_spent} minutes")
            return "\n".join(response_parts)
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
        # --- DEFECTS-ONLY LOGIC: MUST BE FIRST ---
        if 'defects' in analysis['metrics'] and 'production' not in analysis['metrics'] and analysis.get('date_info'):
            total_defects = sum(d.get('defects', 0) for d in data)
            date_str = analysis['date_info'].get('value')
            print("[DEBUG] Returning from defects-only block")
            return f"Total defects on {date_str}: {total_defects:.0f}"
        # --- ORDER-SPECIFIC LOGIC (bulletproof) ---
        if 'order' in analysis['filters'] and analysis.get('date_info'):
            order_ref = str(analysis['filters']['order'])
            date_str = analysis['date_info'].get('value')
            filtered = []
            for d in data:
                doc_order = d.get('orderRef') or d.get('order_reference') or d.get('order')
                if doc_order is not None and str(doc_order) == order_ref:
                    doc_date = d.get('date', '') or d.get('productionDate', '')
                    if doc_date.startswith(date_str):
                        filtered.append(d)
            print(f"[DEBUG] Filtered for order {order_ref} on {date_str}: {len(filtered)} records: {filtered}")
            if filtered:
                produced = sum(d.get('produced', 0) for d in filtered)
                target = sum(d.get('productionTarget', d.get('target', 0)) for d in filtered)
                completion = (produced / target * 100) if target else 0
                print("[DEBUG] Returning from order-specific block")
                return f"Order {order_ref} on {date_str}: produced {produced:.0f} units, target {target:.0f} units, completion {completion:.2f}%"
            else:
                print("[DEBUG] Returning from order-specific block: no data found")
                return f"No data found for order {order_ref} on {date_str}."
        # --- HOURLY BREAKDOWN LOGIC ---
        if 'workshop' in analysis['filters'] and analysis.get('date_info') and (
            'hour' in analysis['metrics'] or 'every hour' in analysis.get('original_question', '') or 'hour' in analysis.get('original_question', '')
        ):
            by_hour = {}
            for d in data:
                hour = d.get('hour')
                if hour is None:
                    date_str = d.get('date', '')
                    if 'T' in date_str:
                        hour = date_str.split('T')[1][:5]
                if hour is None:
                    continue
                if hour not in by_hour:
                    by_hour[hour] = {'produced': 0, 'defects': 0}
                by_hour[hour]['produced'] += d.get('produced', 0)
                by_hour[hour]['defects'] += d.get('defects', 0)
            hour_lines = []
            for h in sorted(by_hour.keys()):
                hour_lines.append(f"Hour {h}: {by_hour[h]['produced']} units, {by_hour[h]['defects']} defects")
            return "Production by hour:\n" + " | ".join(hour_lines)
        # --- MONTHLY/RANGE SUMMARY LOGIC ---
        if analysis.get('date_info') and analysis['date_info'].get('type') == 'relative_date' and isinstance(analysis['date_info'].get('value'), dict):
            date_range = analysis['date_info']['value']
            start_date = date_range.get('start')
            end_date = date_range.get('end')
            header = f"Performance Data from {start_date} to {end_date}"
            total_produced = sum(d.get('produced', 0) for d in data)
            total_defects = sum(d.get('defects', 0) for d in data)
            total_target = sum(d.get('productionTarget', 0) for d in data)
            defect_rate = (total_defects / total_produced * 100) if total_produced else 0
            completion = (total_produced / total_target * 100) if total_target else 0
            response_parts = [header]
            response_parts.append(f"Total production: {total_produced:.0f} units")
            response_parts.append(f"Total defects: {total_defects:.0f}")
            response_parts.append(f"Defect rate: {defect_rate:.2f}%")
            response_parts.append(f"Production target: {total_target:.0f} units")
            response_parts.append(f"Target completion: {completion:.2f}%")
            # Production by date
            by_date = {}
            for d in data:
                date = d.get('date')
                if date:
                    if date not in by_date:
                        by_date[date] = {'produced': 0, 'defects': 0}
                    by_date[date]['produced'] += d.get('produced', 0)
                    by_date[date]['defects'] += d.get('defects', 0)
            if by_date:
                date_lines = []
                for date, vals in sorted(by_date.items()):
                    date_lines.append(f"{date}: {vals['produced']:.0f} units, {vals['defects']:.0f} defects")
                response_parts.append("\nProduction by date:")
                response_parts.append(" | ".join(date_lines))
            # Production by order
            by_order = {}
            for d in data:
                order = d.get('orderRef') or d.get('order_reference') or d.get('order')
                if order is not None:
                    if order not in by_order:
                        by_order[order] = {'produced': 0, 'target': 0}
                    by_order[order]['produced'] += d.get('produced', 0)
                    by_order[order]['target'] += d.get('productionTarget', 0)
            if by_order:
                order_lines = []
                for order, vals in sorted(by_order.items(), key=lambda x: -x[1]['produced']):
                    target = vals['target']
                    produced = vals['produced']
                    percent = (produced / target * 100) if target else 0
                    order_lines.append(f"Order {order}: {produced:.0f} units ({percent:.1f}% of target)")
                response_parts.append("\nProduction by order:")
                response_parts.append(" | ".join(order_lines))
            return "\n".join(response_parts)
        # If the user asked for the sum of production only, return just that
        if analysis.get('math_operation') == 'sum' and 'production' in analysis['metrics']:
            total_production = sum(d.get('produced', 0) for d in data)
            return f"Total production: {total_production:.0f} units"
        if analysis['math_operation']:
            if analysis['math_operation'] == 'average':
                for metric in analysis['metrics']:
                    if metric == 'production':
                        avg = sum(d.get('produced', 0) for d in data) / len(data)
                        response_parts.append(f"Average production: {avg:.2f} units")
                    elif metric == 'defects':
                        avg = sum(d.get('defects', 0) for d in data) / len(data)
                        response_parts.append(f"Average defects: {avg:.2f}")
            elif analysis['math_operation'] == 'rate':
                if 'performance' in analysis['metrics'] or 'efficiency' in analysis['metrics']:
                    total_production = sum(d.get('produced', 0) for d in data)
                    total_target = sum(d.get('productionTarget', 0) for d in data)
                    if total_target > 0:
                        efficiency = (total_production / total_target) * 100
                        response_parts.append(f"Efficiency: {efficiency:.2f}%")
                        response_parts.append(f"Total production: {total_production} units")
                        response_parts.append(f"Production target: {total_target} units")
                    else:
                        response_parts.append(f"Total production: {total_production} units")
        else:
            # Summarize the data
            total_records = len(data)
            # REMOVED: response_parts.append(f"Found {total_records} records")
            if 'production' in analysis['metrics']:
                total_production = sum(d.get('produced', 0) for d in data)
                response_parts.append(f"Total production: {total_production} units")
            if 'defects' in analysis['metrics']:
                total_defects = sum(d.get('defects', 0) for d in data)
                response_parts.append(f"Total defects: {total_defects}")
    
        # --- MONTHLY PERFORMANCE FOR ORDER LOGIC ---
        if 'order' in analysis['filters'] and (
            'monthly' in analysis.get('original_question', '').lower() or 'month' in analysis.get('original_question', '').lower()
        ):
            order_ref = analysis['filters']['order']
            # Group by date for this order
            by_date = {}
            for d in data:
                doc_order = d.get('orderRef') or d.get('order_reference') or d.get('order')
                if doc_order is not None and str(doc_order) == str(order_ref):
                    date = d.get('date')
                    if date:
                        if date not in by_date:
                            by_date[date] = {'produced': 0, 'defects': 0}
                        by_date[date]['produced'] += d.get('produced', 0)
                        by_date[date]['defects'] += d.get('defects', 0)
            if by_date:
                date_lines = []
                for date, vals in sorted(by_date.items()):
                    date_lines.append(f"{date}: {vals['produced']:.0f} units, {vals['defects']:.0f} defects")
                response = "Production by date:\n" + " | ".join(date_lines)
                # Add order summary
                total_produced = sum(vals['produced'] for vals in by_date.values())
                total_target = sum(d.get('productionTarget', 0) for d in data if str(d.get('orderRef', d.get('order_reference', d.get('order', '')))) == str(order_ref))
                percent = (total_produced / total_target * 100) if total_target else 0
                response += f"\n\nProduction by order:\nOrder {order_ref}: {total_produced:.0f} units ({percent:.1f}% of target)"
                return response
            else:
                return f"No data found for order {order_ref}."
    
        # --- MONTHLY PERFORMANCE FOR ORDER LOGIC (safe) ---
        if (
            'order' in analysis['filters']
            and ('monthly' in analysis.get('original_question', '').lower() or 'month' in analysis.get('original_question', '').lower())
            and 'hour' not in analysis['filters']
            and 'workshop' not in analysis['filters']
        ):
            order_ref = analysis['filters']['order']
            # Group by date for this order
            by_date = {}
            for d in data:
                doc_order = d.get('orderRef') or d.get('order_reference') or d.get('order')
                if doc_order is not None and str(doc_order) == str(order_ref):
                    date = d.get('date')
                    if date:
                        if date not in by_date:
                            by_date[date] = {'produced': 0, 'defects': 0}
                        by_date[date]['produced'] += d.get('produced', 0)
                        by_date[date]['defects'] += d.get('defects', 0)
            if by_date:
                date_lines = []
                for date, vals in sorted(by_date.items()):
                    date_lines.append(f"{date}: {vals['produced']:.0f} units, {vals['defects']:.0f} defects")
                response = "Production by date:\n" + " | ".join(date_lines)
                # Add order summary
                total_produced = sum(vals['produced'] for vals in by_date.values())
                total_target = sum(d.get('productionTarget', 0) for d in data if str(d.get('orderRef', d.get('order_reference', d.get('order', '')))) == str(order_ref))
                percent = (total_produced / total_target * 100) if total_target else 0
                response += f"\n\nProduction by order:\nOrder {order_ref}: {total_produced:.0f} units ({percent:.1f}% of target)"
                return response
            else:
                return f"No data found for order {order_ref}."
    
    print("[DEBUG] Returning from format_response: default return")
    return " | ".join(response_parts) if response_parts else "Could not format the calculation results."

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
    
    # Handle special cases for defect-related queries
    if 'defects' in analysis['metrics'] and analysis['defect_query_type']:
        defect_query_type = analysis['defect_query_type']
        
        # Handle defect type listing specifically
        if defect_query_type == 'defect_types':
            return get_defect_types()
            
        # Handle defect names listing specifically
        elif defect_query_type == 'defect_names':
            return get_defect_names()
            
        # Handle defect distribution 
        elif defect_query_type == 'defect_distribution':
            return get_defect_distribution(analysis)
            
        # Handle specific defect type queries
        elif defect_query_type == 'specific_defect' and 'defect_type' in analysis['filters']:
            return get_specific_defect_info(analysis)
    
    # Handle performance/production related queries
    if 'performance' in analysis['metrics'] or 'production' in analysis['metrics'] or ('defects' in analysis['metrics'] and not analysis['defect_query_type']):
        return get_performance_data(analysis)
    
    # Handle special case for workshop comparison
    if analysis['calculation_type'] == 'comparison' and analysis['comparison'].get('entity_type') == 'workshop':
        return compare_workshops(analysis)
    
    query = build_mongodb_query(analysis)
    print(f"Query: {query}")  # For debugging
    
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
            if not analysis['filters'] and not analysis.get('date_info') and len(query) == 0:
                query = {}  # Clear the query to get all machine failures
                print("Using empty query to find all machine failures")
            else:
                print(f"Applying filters to machine failures query: {analysis['filters']}")
                if analysis.get('date_info'):
                    print(f"Applying date filter: {analysis['date_info']}")
        elif 'efficiency' in analysis['metrics'] and analysis.get('calculation_type') == 'efficiency_rate':
            # For efficiency rate, prioritize collections with performance data
            perf_collections = [coll for coll in available_collections 
                              if any(keyword in coll.lower() for keyword in ['performance', 'production', 'efficiency'])]
            if perf_collections:
                collections_to_try.extend(perf_collections)
            else:
                # Look for collections we know have performance data from logs
                if 'performance3' in available_collections:
                    collections_to_try.append('performance3')
                if 'monthly_performance' in available_collections:
                    collections_to_try.append('monthly_performance')
                    
            # For efficiency rates, we may need to adjust the query
            if not analysis['filters'] and len(query) == 0:
                # Get a reasonable sample of data for efficiency calculations
                query = {}  # Clear the query to get all records
                print("Using empty query to get sample for efficiency rate calculation")
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
                    result = list(coll.find())  # Removed limit
                elif 'efficiency' in analysis['metrics'] and analysis.get('calculation_type') == 'efficiency_rate':
                    # Get a reasonable sample for efficiency calculations
                    result = list(coll.find(query))  # Removed limit
                else:
                    result = list(coll.find(query))  # Removed limit
                    
                if result:
                    print(f"Found {len(result)} documents in {collection_name}")
                    data = result
                    break
            except Exception as collection_error:
                print(f"Error accessing collection {collection_name}: {collection_error}")
                continue
        
        # If no data found but we're looking for failures, try a more general approach
        if not data and 'failures' in analysis['metrics']:
            # If a date filter is present, return a specific message
            if analysis.get('date_info'):
                return "there's no recording for this date"
            # Only try a more general approach if there are no filters and no date filter
            if not analysis['filters'] and not analysis.get('date_info'):
                print("No specific failures found. Trying to get all failure records...")
                # Try to get any failure records
                for collection_name in collections_to_try:
                    try:
                        # Simply get all documents in collection (typically failure collections are small)
                        result = list(db[collection_name].find())  # Removed limit
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
                                    result = list(db[coll_name].find(flexible_query))  # Removed limit
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
                                    result = list(db[coll_name].find(flexible_query))  # Removed limit
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
                value = record[field]
                if value is not None:
                    return float(value)
            except (ValueError, TypeError):
                continue
    return default

# Path to the guidance file
GUIDANCE_FILE_PATH = "c:/Users/noure/Downloads/app_guidance.txt"

def get_guidance(query):
    """Get guidance response from app_guidance.txt"""
    try:
        with open('c:/Users/noure/Downloads/app_guidance.txt', 'r', encoding='utf-8') as f:
            guidance_text = f.read()
        
        # Split into sections by double newlines
        sections = guidance_text.split('\n\n')
        
        # Convert query to lowercase for matching
        query_lower = query.lower()
        
        # Find the most relevant section
        best_match = None
        best_score = 0
        
        for section in sections:
            # Skip empty sections
            if not section.strip():
                continue
            
            # Get the first line as the topic
            lines = section.strip().split('\n')
            if not lines:
                continue
            
            topic = lines[0].lower()
            
            # Calculate relevance score based on word overlap
            query_words = set(query_lower.split())
            topic_words = set(topic.split())
            overlap = len(query_words.intersection(topic_words))
            
            if overlap > best_score:
                best_score = overlap
                best_match = section
        
        if best_match:
            return best_match.strip()
        return "I'm sorry, I couldn't find specific guidance for that question. Please try rephrasing or ask about a different topic."
    except Exception as e:
        print(f"Error getting guidance: {e}")
        return "I'm sorry, I encountered an error while looking up guidance information."

@app.route("/chatbot", methods=["POST"])
def chatbot():
    import sys
    response = ""
    print("[DEBUG] chatbot route hit")
    data = request.get_json()
    message = data.get("message", "").lower()
    user_id = data.get("user_id", "anonymous")
    print(f"[DEBUG] message: {message}")
    sys.stdout.flush()
    print("[DEBUG] before analyze_question")
    sys.stdout.flush()
    try:
        analysis = analyze_question(message)
    except Exception as e:
        print(f"[DEBUG] Exception in analyze_question: {e}")
        sys.stdout.flush()
        raise
    print("[DEBUG] after analyze_question")
    sys.stdout.flush()
    analysis['original_question'] = message
    # Compute is_db_query as a boolean before any return
    is_db_query = bool(
        analysis['metrics']
        or analysis['filters']
        or analysis.get('date_info')
        or analysis.get('math_operation')
        or analysis.get('calculation_type')
        or analysis.get('comparison')
    )
    # Force database query if technician filter is present
    if 'technician' in analysis['filters']:
        is_db_query = True
    print(f"[DEBUG] analysis.filters: {analysis['filters']}, is_db_query: {is_db_query}, message: {message}")
    sys.stdout.flush()

    # Role-based greeting feature
    greeting_words = {"hi", "hello", "hey"}
    if message.strip() in greeting_words:
        print("[DEBUG] returning: greeting branch")
        sys.stdout.flush()
        # Try to get the user's role from the database if user_id is provided
        role = None
        if user_id and user_id != "anonymous" and mongodb_available and db is not None:
            try:
                # Convert user_id to ObjectId if it's a string
                if isinstance(user_id, str):
                    user_id = ObjectId(user_id)
                user_doc = db["new_data.users"].find_one({"_id": user_id})
                if user_doc and "role" in user_doc:
                    role = user_doc["role"]
            except Exception as e:
                print(f"Error fetching user role for greeting: {e}")
        if role:
            response = f"Hello {role.upper()}!"
        else:
            response = "Hello!"
        # Save greeting response to database
        if mongodb_available and db is not None:
            try:
                current_time = datetime.now(UTC)
                print(f"Saving greeting conversation for user {user_id} at {current_time.isoformat()}")
                conversation_doc = {
                    "user_id": user_id,
                    "question": message,
                    "response": response,
                    "timestamp": current_time
                }
                result = db.chatbot_conversations.insert_one(conversation_doc)
                print(f"Saved greeting conversation for user {user_id}, id: {result.inserted_id}")
            except Exception as e:
                print(f"Error saving greeting conversation: {str(e)}")
        print("[DEBUG] return: greeting response")
        sys.stdout.flush()
        return {"response": response}

    # Existing logic follows...
    # Get intent prediction
    prediction = intent_predictor.predict(message)
    intent = prediction['intent']
    confidence = prediction['confidence']
    entities = prediction.get('entities', {})
    
    print(f"Intent: {intent}, Confidence: {confidence:.4f}")

    # Backend fallback for user/role queries if intent is not guidance
    user_keywords = ['supervisor', 'technician', 'manager']
    user_actions = ['how many', 'number', 'count', 'list', 'show', 'names', 'who']
    if (any(role in message for role in user_keywords) and
        any(action in message for action in user_actions) and
        intent != 'guidance'):
        role = next((r for r in user_keywords if r in message), None)
        if role:
            if any(word in message for word in ['how many', 'number', 'count', 'total']):
                attribute = 'count'
            elif any(word in message for word in ['name', 'list', 'show']):
                attribute = 'names'
            else:
                attribute = 'count'
            if attribute == 'count':
                count = db["new_data.users"].count_documents({"role": {"$regex": f"^{role}$", "$options": "i"}})
                response = f"There are {count} {role}{'s' if count != 1 else ''}."
            elif attribute == 'names':
                users = db["new_data.users"].find({"role": {"$regex": f"^{role}$", "$options": "i"}})
                names = []
                for u in users:
                    name = u.get("full_name") or u.get("username") or "Unknown"
                    names.append(name)
                response = f"{role.title()}s: {', '.join(names)}"
            else:
                count = db["new_data.users"].count_documents({"role": {"$regex": f"^{role}$", "$options": "i"}})
                response = f"There are {count} {role}{'s' if count != 1 else ''}."
            # Save to DB
    if mongodb_available and db is not None:
        try:
            current_time = datetime.now(UTC)
            conversation_doc = {
                "user_id": user_id,
                "question": message,
                "response": response,
                "timestamp": current_time
                 }
            db.chatbot_conversations.insert_one(conversation_doc)
        except Exception as e:
            print(f"Error saving chatbot conversation: {str(e)}")
            print("[DEBUG] return: user/role branch")
            sys.stdout.flush()
            return {"response": response}

    # User email query support
    if any(word in message for word in ['email', 'mail', 'address']):
        import re
        name_query = None
        # Try to extract name after 'of'
        name_match = re.search(r'(?:email|mail|address)\s*(?:of)?\s*([a-zA-Z0-9_ .\'-]+)', message)
        if name_match:
            name_query = name_match.group(1).strip()
        else:
            # Try to extract from "'s email" pattern (improved)
            name_match = re.search(r"([a-zA-Z0-9_.'-]+)'s\s*(?:email|mail|address)", message)
            if name_match:
                name_query = name_match.group(1).strip()
            else:
                # Try to extract the last word before 'email/mail/address'
                name_match = re.search(r'([a-zA-Z0-9_ .\'-]+)\s+(?:email|mail|address)', message)
                if name_match:
                    name_query = name_match.group(1).strip()
        if name_query:
            user = db["new_data.users"].find_one({
                "$or": [
                    {"full_name": {"$regex": name_query, "$options": "i"}},
                    {"username": {"$regex": name_query, "$options": "i"}}
                ]
            })
            if user and "email" in user:
                response = f"{name_query.title()}'s email is: {user['email']}"
            else:
                response = f"Sorry, I couldn't find an email for {name_query.title()}."
        else:
            response = "Sorry, I couldn't extract the name from your question."
        # Save to DB
        if mongodb_available and db is not None:
            try:
                current_time = datetime.now(UTC)
                conversation_doc = {
                    "user_id": user_id,
                    "question": message,
                    "response": response,
                    "timestamp": current_time
                }
                result = db.chatbot_conversations.insert_one(conversation_doc)
                print(f"Saved email conversation for user {user_id}, id: {result.inserted_id}")
            except Exception as e:
                print(f"Error saving email conversation: {str(e)}")
        print("[DEBUG] return: email branch")
        sys.stdout.flush()
        return {"response": response}

    # Fallback: If message starts with 'how to', 'how do i', or confidence is low, check guidance
    howto_starts = (
        message.strip().startswith('how to') or
        message.strip().startswith('how do i') or
        message.strip().startswith('how can i') or
        message.strip().startswith('how should i')
    )
    if howto_starts or confidence < 0.6:
        response = get_guidance(message)
        # Only return if guidance is found (not the default sorry message)
        if response and not response.lower().startswith("i'm sorry"):
            # Save guidance response to database
            if mongodb_available and db is not None:
                try:
                    current_time = datetime.now(UTC)
                    print(f"Saving guidance conversation for user {user_id} at {current_time.isoformat()}")
                    conversation_doc = {
                        "user_id": user_id,
                        "question": message,
                        "response": response,
                        "timestamp": current_time
                    }
                    result = db.chatbot_conversations.insert_one(conversation_doc)
                    print(f"Saved guidance conversation for user {user_id}, id: {result.inserted_id}")
                except Exception as e:
                    print(f"Error saving guidance conversation: {str(e)}")
            return {"response": response}

    # Handle guidance questions first (existing logic)
    if intent == 'guidance' and confidence >= 0.4:
        response = get_guidance(message)
        # Save guidance response to database
        if mongodb_available and db is not None:
            try:
                current_time = datetime.now(UTC)
                print(f"Saving guidance conversation for user {user_id} at {current_time.isoformat()}")
                conversation_doc = {
                    "user_id": user_id,
                    "question": message,
                    "response": response,
                    "timestamp": current_time
                }
                result = db.chatbot_conversations.insert_one(conversation_doc)
                print(f"Saved guidance conversation for user {user_id}, id: {result.inserted_id}")
            except Exception as e:
                print(f"Error saving guidance conversation: {str(e)}")
        return {"response": response}

    # Continue with existing logic for database queries
    analysis = analyze_question(message)
    analysis['original_question'] = message
    print(f"[DEBUG] analysis.filters: {analysis['filters']}, is_db_query: {is_db_query}, message: {message}")
    sys.stdout.flush()

    # Check if the query is likely NOT a database query (minimal metrics/filters)
    is_db_query = (
        analysis['metrics']
        or analysis['filters']
        or analysis.get('date_info')
        or analysis.get('math_operation')
        or analysis.get('calculation_type')
        or analysis.get('comparison')
    )
    # Ensure that if intent is 'failures' and a technician filter is present, always query the database
    if intent == 'failures' and 'technician' in analysis['filters']:
        is_db_query = True

    # Guidance and non-guidance phrase detection
    guidance_starts = (
        message.strip().startswith('how to') or
        message.strip().startswith('how do i') or
        message.strip().startswith('how can i') or
        message.strip().startswith('how should i')
    )
    non_guidance_starts = (
        message.strip().startswith('what') or
        message.strip().startswith('show') or
        message.strip().startswith('list') or
        message.strip().startswith('give me')
    )
    print(f"[DEBUG] intent: {intent}, confidence: {confidence}, guidance_starts: {guidance_starts}, non_guidance_starts: {non_guidance_starts}, is_db_query: {is_db_query}")

    response = ""
    # Refined fallback: If message starts with a guidance phrase and is_db_query is False, always fetch from guidance
    if guidance_starts and not is_db_query:
        response = get_guidance(message)
        # Only return if guidance is found (not the default sorry message)
        if response and not response.lower().startswith("i'm sorry"):
            if mongodb_available and db is not None:
                try:
                    current_time = datetime.now(UTC)
                    print(f"Saving guidance conversation for user {user_id} at {current_time.isoformat()}")
                    conversation_doc = {
                        "user_id": user_id,
                        "question": message,
                        "response": response,
                        "timestamp": current_time
                    }
                    result = db.chatbot_conversations.insert_one(conversation_doc)
                    print(f"Saved guidance conversation for user {user_id}, id: {result.inserted_id}")
                except Exception as e:
                    print(f"Error saving guidance conversation: {str(e)}")
            return {"response": response}

    # Only trigger guidance fallback if (intent == 'guidance') OR (confidence is very low AND guidance_starts and not non_guidance_starts)
    guidance_trigger = (
        intent == 'guidance' or
        (confidence < 0.4 and guidance_starts and not non_guidance_starts)
    )
    if not is_db_query and guidance_trigger:
        response = get_guidance(message)
        # Only return if guidance is found (not the default sorry message)
        if response and not response.lower().startswith("i'm sorry"):
            if mongodb_available and db is not None:
                try:
                    current_time = datetime.now(UTC)
                    print(f"Saving guidance conversation for user {user_id} at {current_time.isoformat()}")
                    conversation_doc = {
                        "user_id": user_id,
                        "question": message,
                        "response": response,
                        "timestamp": current_time
                    }
                    result = db.chatbot_conversations.insert_one(conversation_doc)
                    print(f"Saved guidance conversation for user {user_id}, id: {result.inserted_id}")
                except Exception as e:
                    print(f"Error saving guidance conversation: {str(e)}")
            return {"response": response}

    # Refined fallback: Only trigger guidance if message starts with a guidance phrase, does NOT start with a non-guidance phrase, and is_db_query is False
    if guidance_starts and not non_guidance_starts and not is_db_query:
        print("[DEBUG] about to call get_guidance")
        sys.stdout.flush()
        response = get_guidance(message)
        # Only return if guidance is found (not the default sorry message)
        if response and not response.lower().startswith("i'm sorry"):
            if mongodb_available and db is not None:
                try:
                    current_time = datetime.now(UTC)
                    print(f"Saving guidance conversation for user {user_id} at {current_time.isoformat()}")
                    conversation_doc = {
                        "user_id": user_id,
                        "question": message,
                        "response": response,
                        "timestamp": current_time
                    }
                    result = db.chatbot_conversations.insert_one(conversation_doc)
                    print(f"Saved guidance conversation for user {user_id}, id: {result.inserted_id}")
                except Exception as e:
                    print(f"Error saving guidance conversation: {str(e)}")
            return {"response": response}

    # Otherwise, always try DB if is_db_query or not response
    if is_db_query or not response or "Error: Guidance file not found" in response:
        print("[DEBUG] about to call query_database")
        sys.stdout.flush()
        response = query_database(analysis)
        # Remove <br> and <br><br> from the response if present
        if isinstance(response, str):
            response = response.replace('<br><br>', ' ').replace('<br>', ' ')
        # Save the conversation to MongoDB
        if mongodb_available and db is not None:
            try:
                current_time = datetime.now(UTC)
                print(f"Saving conversation for user {user_id} at {current_time.isoformat()}")
                conversation_doc = {
                    "user_id": user_id,
                    "question": message,
                    "response": response,
                    "timestamp": current_time
                }
                result = db.chatbot_conversations.insert_one(conversation_doc)
                print(f"Saved chatbot conversation for user {user_id}, id: {result.inserted_id}")
            except Exception as e:
                print(f"Error saving chatbot conversation: {str(e)}")
    return {"response": response}

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
        print(f"Fetching chat history for user: {user_id}")
        
        # Use a simpler query without date filtering to ensure all records are returned
        conversations = list(db.chatbot_conversations.find(
            {"user_id": user_id},
            {"_id": 0}  # Exclude MongoDB _id field from results
        ).sort("timestamp", -1).limit(50))  # Get latest 50 conversations
        
        print(f"Found {len(conversations)} conversations")
        if conversations:
            print(f"Most recent conversation timestamp: {conversations[0].get('timestamp', 'unknown')}")
            print(f"First question: {conversations[0].get('question', 'unknown')}")
        
        # Convert datetime objects to string for JSON serialization
        current_time = datetime.now(UTC)
        print(f"Current UTC time: {current_time.isoformat()}")
        
        for conv in conversations:
            if "timestamp" in conv and isinstance(conv["timestamp"], datetime):
                # Ensure timestamp is in ISO format with timezone info
                conv["timestamp"] = conv["timestamp"].replace(microsecond=0).isoformat() + 'Z'
                
        # Log some sample data for debugging
        if conversations:
            print(f"Formatted timestamp of latest: {conversations[0].get('timestamp', 'unknown')}")
        
        return {
            "status": "success", 
            "conversations": conversations,
            "count": len(conversations),
            "server_time": current_time.replace(microsecond=0).isoformat() + 'Z'
        }
    
    except Exception as e:
        print(f"Error fetching conversation history: {str(e)}")
        return {"status": "error", "message": f"Failed to fetch conversation history: {str(e)}"}

def get_defect_types():
    """Query the database to get all defect types"""
    if not mongodb_available:
        return "Database connection is unavailable. Cannot retrieve defect types."
    
    try:
        # First try to get defect types from a dedicated collection if it exists
        defect_types = []
        
        if 'defect_types' in available_collections:
            # Try to get types from dedicated collection
            types_docs = list(db.defect_types.find())
            if types_docs:
                for doc in types_docs:
                    # Look for fields that might contain the type name
                    for field in ['name', 'type', 'defectType', 'category']:
                        if field in doc and doc[field]:
                            defect_types.append(str(doc[field]))
                            break
        
        # If no dedicated collection or no types found, try to extract from defect records
        if not defect_types:
            # Try to identify collections that might contain defect data
            defect_collections = [coll for coll in available_collections 
                                if any(kw in coll.lower() for kw in ['defect', 'quality', 'production'])]
            
            if not defect_collections:
                defect_collections = ['performance3', 'monthly_performance']  # fallback to known collections
            
            # Search for defect type fields in each collection
            extracted_types = set()
            for coll_name in defect_collections:
                try:
                    # Find a sample document to identify field structure
                    sample = db[coll_name].find_one()
                    if not sample:
                        continue
                        
                    # Look for fields that might contain defect type information
                    type_fields = []
                    for field in sample.keys():
                        if any(kw in field.lower() for kw in ['defect_type', 'defecttype', 'type', 'category']):
                            type_fields.append(field)
                    
                    # If we found potential fields, query for distinct values
                    if type_fields:
                        for field in type_fields:
                            distinct_values = db[coll_name].distinct(field)
                            for value in distinct_values:
                                if value and isinstance(value, (str, int)):
                                    extracted_types.add(str(value))
                except Exception as e:
                    print(f"Error extracting defect types from {coll_name}: {e}")
                    continue
            
            # If we found types via extraction, use them
            if extracted_types:
                defect_types = list(extracted_types)
        
        # If still no defect types found, fall back to extracting from text fields
        if not defect_types:
            # Look in text description fields 
            text_field_patterns = [
                ('description', r'type:\s*(\w+)'), 
                ('notes', r'defect:\s*(\w+)'),
                ('comment', r'issue:\s*(\w+)')
            ]
            
            # Search in likely collections
            extracted_types = set()
            for coll_name in defect_collections:
                try:
                    # Find documents with text fields
                    for field_name, pattern in text_field_patterns:
                        docs = list(db[coll_name].find({field_name: {"$exists": True}}).limit(50))
                        for doc in docs:
                            if field_name in doc and isinstance(doc[field_name], str):
                                matches = re.findall(pattern, doc[field_name], re.IGNORECASE)
                                for match in matches:
                                    extracted_types.add(match)
                except Exception:
                    continue
            
            # Add any types from extraction
            if extracted_types:
                defect_types.extend(list(extracted_types))
        
        # We won't look for hardcoded patterns anymore
        # Just rely on what we find in the database
        
        # If we still have no types found in the database
        if not defect_types:
            return "No defect types found in the database. Please check if defect type data is properly stored."
        
        # If we only have numeric IDs, leave them as is without adding descriptive names
        # This ensures we're only using what's in the database without any hardcoded assumptions
        
        # Format and return the response
        if defect_types:
            # Remove duplicates and sort
            unique_types = sorted(list(set(defect_types)))
            
            # Check if we only have numeric values
            all_numeric = all(isinstance(t, (int, float)) or (isinstance(t, str) and t.isdigit()) for t in unique_types)
            
            # We won't add hardcoded descriptions, but we will try to find name fields in the database
            if all_numeric and 'defect_types' in available_collections:
                print("Found only numeric defect type IDs, looking for name fields in database")
                
                # Try to find descriptive fields that might contain names
                name_to_id_map = {}
                try:
                    # Look for documents that have both a numeric ID and a text field
                    for doc_id in unique_types:
                        # Look for a document with this ID
                        potential_docs = list(db.defect_types.find({"$or": [
                            {"_id": doc_id}, 
                            {"id": doc_id}, 
                            {"defectId": doc_id}, 
                            {"defect_id": doc_id}
                        ]}))
                        
                        if potential_docs:
                            # Found a matching document, look for text fields
                            doc = potential_docs[0]
                            for field, value in doc.items():
                                if field not in ["_id", "id", "defectId", "defect_id"] and isinstance(value, str) and not value.isdigit():
                                    name_to_id_map[doc_id] = value
                                    print(f"Found mapping: ID {doc_id} -> Name '{value}' in field '{field}'")
                                    break
                            
                    # If we found mappings, use them to enhance the response
                    if name_to_id_map:
                        # Replace IDs with ID+Name format
                        enhanced_types = []
                        for type_id in unique_types:
                            if type_id in name_to_id_map:
                                enhanced_types.append(f"{type_id} ({name_to_id_map[type_id]})")
                            else:
                                enhanced_types.append(str(type_id))
                        unique_types = enhanced_types
                        print(f"Enhanced type IDs with names: {unique_types}")
                except Exception as e:
                    print(f"Error trying to find defect type names: {e}")
                    # Continue with just the IDs
            
            # Format the response with the types
            response = f"Found {len(unique_types)} defect types: "
            response += ", ".join(str(t) for t in unique_types)
            return response
        else:
            return "No defect types found in the database."
    
    except Exception as e:
        print(f"Error retrieving defect types: {e}")
        return f"Error retrieving defect types: {str(e)}"

def get_defect_names():
    """Query the database to get all defect names"""
    if not mongodb_available:
        return "Database connection is unavailable. Cannot retrieve defect names."
    
    try:
        # First try to get defect names from a dedicated collection if it exists
        defect_names = []
        
        if 'defect_types' in available_collections:
            # Try to get names from dedicated collection
            types_docs = list(db.defect_types.find())
            if types_docs:
                for doc in types_docs:
                    # Look for fields that might contain the name (prioritize name fields)
                    for field in ['name', 'defectName', 'description', 'label']:
                        if field in doc and doc[field]:
                            defect_names.append(str(doc[field]))
                            break
        
        # If no names found yet, look for mappings of IDs to names
        if not defect_names and 'defect_types' in available_collections:
            types_docs = list(db.defect_types.find())
            id_name_pairs = []
            
            for doc in types_docs:
                defect_id = None
                defect_name = None
                
                # First, get the ID
                for id_field in ['_id', 'id', 'defectId', 'defect_id']:
                    if id_field in doc and doc[id_field] is not None:
                        defect_id = str(doc[id_field])
                        break
                
                # Then, get the name
                for name_field in ['name', 'defectName', 'description', 'label']:
                    if name_field in doc and doc[name_field] is not None:
                        defect_name = str(doc[name_field])
                        break
                
                # If we have both an ID and a name, add to our list
                if defect_id and defect_name and defect_id != defect_name:
                    id_name_pairs.append(f"{defect_name}")
            
            if id_name_pairs:
                defect_names.extend(id_name_pairs)
        
        # If still no defect names found, try other collections
        if not defect_names:
            # Try to identify collections that might contain defect data
            defect_collections = [coll for coll in available_collections 
                                if any(kw in coll.lower() for kw in ['defect', 'quality', 'defect_names'])]
            
            if not defect_collections:
                defect_collections = ['performance3', 'monthly_performance']  # fallback to known collections
            
            # Look for fields that might contain defect name information
            for coll_name in defect_collections:
                try:
                    sample = db[coll_name].find_one()
                    if not sample:
                        continue
                    
                    name_fields = []
                    for field in sample.keys():
                        if any(kw in field.lower() for kw in ['defect_name', 'defectname', 'name', 'description']):
                            name_fields.append(field)
                    
                    if name_fields:
                        for field in name_fields:
                            distinct_values = db[coll_name].distinct(field)
                            for value in distinct_values:
                                if value and isinstance(value, str) and value.strip():
                                    defect_names.append(value)
                except Exception as e:
                    print(f"Error extracting defect names from {coll_name}: {e}")
                    continue
        
        # If we still have no names found in the database, try to get the defect types and convert
        if not defect_names:
            # Get defect types
            defect_types = []
            
            if 'defect_types' in available_collections:
                # Try to extract name-id mappings from defect_types collection
                name_mappings = {}
                all_docs = list(db.defect_types.find())
                
                for doc in all_docs:
                    type_id = None
                    for id_field in ['_id', 'id', 'defectId', 'type', 'defectType']:
                        if id_field in doc and doc[id_field] is not None:
                            type_id = str(doc[id_field])
                            break
                    
                    if type_id:
                        name = None
                        for name_field in ['name', 'defectName', 'description', 'label']:
                            if name_field in doc and doc[name_field] is not None and isinstance(doc[name_field], str):
                                name = doc[name_field]
                                break
                        
                        if name:
                            name_mappings[type_id] = name
                            defect_names.append(name)
        
        # Format and return the response
        if defect_names:
            # Remove duplicates and sort
            unique_names = sorted(list(set(defect_names)))
            
            # Format the response with the names
            response = f"Found {len(unique_names)} defect names: "
            response += ", ".join(str(name) for name in unique_names)
            return response
        else:
            return "No defect names found in the database. The system may only have defect type IDs without descriptive names."
    
    except Exception as e:
        print(f"Error retrieving defect names: {e}")
        return f"Error retrieving defect names: {str(e)}"

def get_defect_distribution(analysis):
    """Get the distribution of defects by type, workshop, etc."""
    if not mongodb_available:
        return "Database connection is unavailable. Cannot retrieve defect distribution."
    
    try:
        # Determine which collections to query
        defect_collections = [coll for coll in available_collections 
                            if any(kw in coll.lower() for kw in ['defect', 'quality', 'production'])]
        
        if not defect_collections:
            defect_collections = ['performance3', 'monthly_performance']  # fallback
        
        # Build the query based on date and other filters
        query = build_mongodb_query(analysis)
        
        # Initialize counters
        defect_counts = {}  # Defects by type
        workshop_defects = {}  # Defects by workshop
        date_defects = {}  # Defects by date
        
        # Track field names that contain defect information
        defect_fields = {
            'count': [],  # Fields that contain defect counts
            'type': []    # Fields that contain defect types
        }
        
        # For each collection, try to extract defect distribution
        data_found = False
        for coll_name in defect_collections:
            try:
                # Get a sample to identify fields
                sample = db[coll_name].find_one()
                if not sample:
                    continue
                
                # Identify defect-related fields
                for field in sample.keys():
                    field_lower = field.lower()
                    if 'defect' in field_lower or 'quality' in field_lower:
                        if any(kw in field_lower for kw in ['count', 'number', 'total']):
                            defect_fields['count'].append(field)
                        elif any(kw in field_lower for kw in ['type', 'category', 'kind']):
                            defect_fields['type'].append(field)
                
                # If we don't have specific defect count fields, look for general fields
                if not defect_fields['count']:
                    for field in sample.keys():
                        if field == 'defects' or field == 'qualityIssues':
                            defect_fields['count'].append(field)
                
                # Query the database
                documents = list(db[coll_name].find(query))  # Removed limit
                
                if documents:
                    data_found = True
                    
                    # Process each document
                    for doc in documents:
                        # Get the workshop id (try various field names)
                        workshop = None
                        for w_field in ['workshop', 'workshopId', 'workshop_id']:
                            if w_field in doc:
                                workshop = str(doc[w_field])
                                break
                        
                        # Get the date
                        date = doc.get('date', 'unknown')
                        if isinstance(date, str):
                            # Use just the date part if it includes time
                            date_parts = date.split('T')[0] if 'T' in date else date
                        else:
                            date_parts = str(date)
                        
                        # If we have a type field, use it to distribute defects by type
                        defect_type_found = False
                        for type_field in defect_fields['type']:
                            if type_field in doc and doc[type_field]:
                                defect_type = str(doc[type_field])
                                defect_count = 1  # Default count if no count field
                                
                                # Look for a corresponding count field
                                for count_field in defect_fields['count']:
                                    if count_field in doc and doc[count_field] is not None:
                                        try:
                                            defect_count = float(doc[count_field])
                                            break
                                        except (ValueError, TypeError):
                                            pass
                                
                                # Update the counters
                                defect_counts[defect_type] = defect_counts.get(defect_type, 0) + defect_count
                                defect_type_found = True
                                
                                # Update workshop distribution if workshop exists
                                if workshop:
                                    if workshop not in workshop_defects:
                                        workshop_defects[workshop] = {}
                                    workshop_defects[workshop][defect_type] = workshop_defects[workshop].get(defect_type, 0) + defect_count
                                
                                # Update date distribution
                                if date_parts not in date_defects:
                                    date_defects[date_parts] = {}
                                date_defects[date_parts][defect_type] = date_defects[date_parts].get(defect_type, 0) + defect_count
                        
                        # If no specific defect type found, just count total defects
                        if not defect_type_found:
                            total_defects = 0
                            for count_field in defect_fields['count']:
                                if count_field in doc and doc[count_field] is not None:
                                    try:
                                        total_defects = float(doc[count_field])
                                        break
                                    except (ValueError, TypeError):
                                        pass
                            
                            if total_defects > 0:
                                defect_type = "Unspecified"
                                defect_counts[defect_type] = defect_counts.get(defect_type, 0) + total_defects
                                
                                # Update workshop distribution if workshop exists
                                if workshop:
                                    if workshop not in workshop_defects:
                                        workshop_defects[workshop] = {}
                                    workshop_defects[workshop][defect_type] = workshop_defects[workshop].get(defect_type, 0) + total_defects
                                
                                # Update date distribution
                                if date_parts not in date_defects:
                                    date_defects[date_parts] = {}
                                date_defects[date_parts][defect_type] = date_defects[date_parts].get(defect_type, 0) + total_defects
            except Exception as e:
                print(f"Error processing defect distribution in {coll_name}: {e}")
                continue
        
        if not data_found:
            return "No defect data found that matches your query criteria."
        
        # Format the response
        response_parts = []
        
        # Overall distribution by type
        if defect_counts:
            total_defects = sum(defect_counts.values())
            response_parts.append(f"Total defects: {total_defects:.0f}")
            
            response_parts.append("Defect distribution by type:")
            type_lines = []
            for defect_type, count in sorted(defect_counts.items(), key=lambda x: x[1], reverse=True):
                percentage = (count / total_defects) * 100 if total_defects > 0 else 0
                type_lines.append(f"{defect_type}: {count:.0f} ({percentage:.1f}%)")
            response_parts.append(" | ".join(type_lines[:5]))  # Show top 5
        
        # Distribution by workshop
        if workshop_defects:
            response_parts.append("Defect distribution by workshop:")
            workshop_lines = []
            for workshop, defects in workshop_defects.items():
                workshop_total = sum(defects.values())
                workshop_lines.append(f"Workshop {workshop}: {workshop_total:.0f} defects")
            response_parts.append(" | ".join(workshop_lines[:5]))  # Show top 5
        
        # Date trend (optional, only if requested)
        if date_defects and len(date_defects) > 1 and analysis.get('math_operation') == 'trend':
            response_parts.append("Defect trend:")
            date_totals = {date: sum(defects.values()) for date, defects in date_defects.items()}
            # Sort by date
            date_trend = sorted(date_totals.items())
            trend_lines = []
            for date, total in date_trend[:5]:  # Show most recent 5
                trend_lines.append(f"{date}: {total:.0f}")
            response_parts.append(" | ".join(trend_lines))
        
        return " ▪ ".join(response_parts)
    
    except Exception as e:
        print(f"Error analyzing defect distribution: {e}")
        return f"Error analyzing defect distribution: {str(e)}"

def get_specific_defect_info(analysis):
    """Get information about a specific defect type"""
    if not mongodb_available:
        return "Database connection is unavailable. Cannot retrieve defect information."
    
    try:
        # Get the specific defect type from filters
        defect_type = analysis['filters'].get('defect_type')
        if not defect_type:
            return "No specific defect type specified."
            
        # Check if user is asking about "defect" in general rather than a specific type
        if defect_type.lower() == "defect" or defect_type.lower() == "defects":
            print("User is asking about defects in general")
            
            # Check if the original query was about types or names
            if 'defect_names' in str(analysis).lower():
                return get_defect_names()
            else:
                return get_defect_types()
        
        # Make the defect type case-insensitive
        defect_pattern = re.compile(defect_type, re.IGNORECASE)
        
        # Determine which collections to query
        defect_collections = [coll for coll in available_collections 
                             if any(kw in coll.lower() for kw in ['defect', 'quality', 'production'])]
        
        if not defect_collections:
            defect_collections = ['performance3', 'monthly_performance']  # fallback
        
        # Build the base query for date and other filters
        query = build_mongodb_query(analysis)
        
        # Add defect type filter with case-insensitive matching
        # We'll need to check various possible field names
        defect_type_query = {"$or": []}
        
        # Track found data and field information
        total_count = 0
        workshop_counts = {}
        date_counts = {}
        
        # For each collection, try to find data for this defect type
        data_found = False
        defect_fields = set()  # Track which fields contained defect data
        
        for coll_name in defect_collections:
            try:
                # Get a sample document to identify field structure
                sample = db[coll_name].find_one()
                if not sample:
                    continue
                
                # Look for fields that might contain defect type information
                type_fields = []
                for field in sample.keys():
                    field_lower = field.lower()
                    if any(kw in field_lower for kw in ['defect_type', 'defecttype', 'type', 'category']):
                        type_fields.append(field)
                
                # If no specific type fields found, look for count fields that might have the defect type in name
                count_fields = []
                type_in_count_field = False
                
                for field in sample.keys():
                    field_lower = field.lower()
                    if any(kw in field_lower for kw in ['defect', 'quality']):
                        # Check if the field name contains the defect type
                        if defect_pattern.search(field_lower):
                            count_fields.append(field)
                            type_in_count_field = True
                
                if type_fields:
                    # Build a query using the type fields
                    for field in type_fields:
                        defect_type_query["$or"].append({field: {"$regex": defect_type, "$options": "i"}})
                
                if type_in_count_field:
                    # Use the count fields directly
                    count_query = {"$or": []}
                    for field in count_fields:
                        count_query["$or"].append({field: {"$exists": True}})
                    
                    # Either use a combined query or just the count query
                    if defect_type_query["$or"]:
                        # If we have both type fields and count fields, use them in an OR
                        final_query = {"$or": [defect_type_query, count_query]}
                    else:
                        final_query = count_query
                else:
                    # Just use the type query if no count fields match the defect type
                    final_query = defect_type_query if defect_type_query["$or"] else {}
                
                # Combine with the base query
                if query and final_query:
                    combined_query = {"$and": [query, final_query]}
                else:
                    combined_query = query or final_query or {}
                
                # Query the database
                print(f"Querying {coll_name} for {defect_type} with query: {combined_query}")
                documents = list(db[coll_name].find(combined_query))  # Removed limit
                
                if documents:
                    data_found = True
                    print(f"Found {len(documents)} documents with {defect_type} in {coll_name}")
                    
                    # Process each document
                    for doc in documents:
                        # Track which fields contained defect information
                        defect_count = 0
                        
                        # Check type fields first
                        for field in type_fields:
                            if field in doc and defect_pattern.search(str(doc[field])):
                                # Found the defect type, now look for a corresponding count field
                                for count_field in sample.keys():
                                    if 'defect' in count_field.lower() and 'count' in count_field.lower():
                                        if count_field in doc and doc[count_field] is not None:
                                            try:
                                                defect_count = float(doc[count_field])
                                                defect_fields.add(f"{field} + {count_field}")
                                                break
                                            except (ValueError, TypeError):
                                                pass
                        
                        # If no count found yet, check for fields that have the defect type in the name
                        if defect_count == 0:
                            for field in count_fields:
                                if field in doc and doc[field] is not None:
                                    try:
                                        defect_count = float(doc[field])
                                        defect_fields.add(field)
                                        break
                                    except (ValueError, TypeError):
                                        pass
                        
                        # If still no count, check if there's a field just called 'defects'
                        if defect_count == 0 and 'defects' in doc and doc['defects'] is not None:
                            try:
                                defect_count = float(doc['defects'])
                                defect_fields.add('defects')
                            except (ValueError, TypeError):
                                pass
                        
                        # If we found a count, update our totals
                        if defect_count > 0:
                            total_count += defect_count
                            
                            # Get the workshop (if available)
                            workshop = None
                            for w_field in ['workshop', 'workshopId', 'workshop_id']:
                                if w_field in doc:
                                    workshop = str(doc[w_field])
                                    break
                            
                            if workshop:
                                workshop_counts[workshop] = workshop_counts.get(workshop, 0) + defect_count
                            
                            # Get the date
                            date = doc.get('date', 'unknown')
                            if isinstance(date, str):
                                # Use just the date part if it includes time
                                date_parts = date.split('T')[0] if 'T' in date else date
                            else:
                                date_parts = str(date)
                            
                            date_counts[date_parts] = date_counts.get(date_parts, 0) + defect_count
            except Exception as e:
                print(f"Error processing {defect_type} in {coll_name}: {e}")
                continue
        
        if not data_found:
            return f"No data found for defect type '{defect_type}'. Try a different type or check spelling."
        
        # Format the response
        response_parts = []
        response_parts.append(f"Defect Information: {defect_type.title()}")
        response_parts.append(f"Total count: {total_count:.0f}")
        
        # Workshop distribution
        if workshop_counts:
            response_parts.append("Distribution by workshop:")
            workshop_lines = []
            for workshop, count in sorted(workshop_counts.items(), key=lambda x: x[1], reverse=True):
                percentage = (count / total_count) * 100 if total_count > 0 else 0
                workshop_lines.append(f"Workshop {workshop}: {count:.0f} ({percentage:.1f}%)")
            response_parts.append(" | ".join(workshop_lines[:5]))  # Show top 5
        
        # Date trend
        if date_counts and len(date_counts) > 1:
            response_parts.append("Recent trend:")
            # Sort by date
            dates = sorted(date_counts.keys())[-5:]  # Most recent 5 dates
            trend_lines = []
            for date in dates:
                count = date_counts[date]
                trend_lines.append(f"{date}: {count:.0f}")
            response_parts.append(" | ".join(trend_lines))
        
        # Fields that were used
        if defect_fields:
            field_str = ", ".join(defect_fields)
            response_parts.append(f"Data source fields: {field_str}")
        
        return " ▪ ".join(response_parts)
    
    except Exception as e:
        print(f"Error retrieving information for defect type {defect_type}: {e}")
        return f"Error retrieving defect information: {str(e)}"

def get_performance_data(analysis):
    """Get production performance data based on the query analysis"""
    if not mongodb_available:
        return "Database connection is unavailable. Cannot retrieve performance data."
    
    try:
        print("Starting get_performance_data with analysis:", str(analysis).replace('\n', ' ')[:200] + "...")
        
        # Ensure required fields exist
        if 'filters' not in analysis:
            analysis['filters'] = {}
        if 'metrics' not in analysis:
            analysis['metrics'] = []
            
        # IMPORTANT: Try to diagnose what collections and document formats exist
        print("Available collections:", available_collections)
        
        # Sample some documents from performance collections to understand format
        for collection_name in ['performance3', 'monthly_performance']:
            if collection_name in available_collections:
                try:
                    sample_doc = db[collection_name].find_one()
                    if sample_doc:
                        print(f"Sample document from {collection_name}: {str(sample_doc)[:500]}...")
                        print(f"Fields in {collection_name}: {list(sample_doc.keys())}")
                except Exception as e:
                    print(f"Error sampling {collection_name}: {e}")
        
        # Build the query based on date, time, workshop, chain, etc.
        query = build_mongodb_query(analysis)
        print(f"Initial performance query: {query}")
        
        # Create a more comprehensive query with all filters
        comprehensive_query = {}
        query_conditions = []
        
        # Workshop filter - try multiple field names and formats
        if 'workshop' in analysis['filters']:
            workshop_id = analysis['filters']['workshop']
            print(f"Processing workshop filter with ID: {workshop_id}")
            # Try additional formats for workshops
            workshop_values = [
                workshop_id,                 # Plain ID: "3"
                int(workshop_id) if workshop_id.isdigit() else workshop_id,  # Numeric ID: 3
                f"Workshop {workshop_id}",    # With prefix: "Workshop 3"
                f"workshop {workshop_id}",    # Lowercase: "workshop 3"
                f"W{workshop_id}",           # Short form: "W3"
                f"w{workshop_id}",           # Lowercase short: "w3"
                f"Workshop{workshop_id}"     # No space: "Workshop3"
            ]
            workshop_condition = {"$or": []}
            for val in workshop_values:
                # Add all possible field names for workshop
                for field in ["workshop", "workshopId", "workshop_id", "workshopID", "Workshop", "shop", "location"]:
                    workshop_condition["$or"].append({field: val})
            query_conditions.append(workshop_condition)
        
        # Hour filter - try multiple field names and formats
        if 'hour' in analysis['filters']:
            hour_id = analysis['filters']['hour']
            print(f"Processing hour filter with ID: {hour_id}")
            # Try additional formats for hours
            hour_values = [
                hour_id,              # Plain: "13"
                f"{hour_id}:00",      # With minutes: "13:00"
                f"{hour_id}h",        # With h: "13h"
                f"{hour_id}:00:00",   # Full time: "13:00:00"
                int(hour_id) if hour_id.isdigit() else hour_id  # Numeric: 13
            ]
            hour_condition = {"$or": []}
            for val in hour_values:
                # Add all possible field names for hour
                for field in ["hour", "timeHour", "time_hour", "Hour", "time", "productionHour"]:
                    hour_condition["$or"].append({field: val})
            
            # Also try to match against ISO date strings with the hour
            hour_regex_patterns = [
                {"date": {"$regex": f"T{hour_id.zfill(2)}:", "$options": "i"}},
                {"date": {"$regex": f" {hour_id}:", "$options": "i"}},
                {"dateTime": {"$regex": f"T{hour_id.zfill(2)}:", "$options": "i"}},
                {"timestamp": {"$regex": f"T{hour_id.zfill(2)}:", "$options": "i"}}
            ]
            hour_condition["$or"].extend(hour_regex_patterns)
            
            query_conditions.append(hour_condition)
        
        # Chain filter - try multiple field names
        if 'chain' in analysis['filters']:
            chain_id = analysis['filters']['chain']
            chain_condition = {"$or": [
                {"chain": chain_id},
                {"chain": int(chain_id) if chain_id.isdigit() else chain_id},
                {"chainId": chain_id},
                {"chainId": int(chain_id) if chain_id.isdigit() else chain_id},
                {"chain_id": chain_id},
                {"chain_id": int(chain_id) if chain_id.isdigit() else chain_id}
            ]}
            query_conditions.append(chain_condition)
        
        # Date filter - try multiple field names and formats
        if analysis.get('date_info'):
            date_info = analysis.get('date_info')
            if date_info['type'] == 'exact_date':
                date_value = date_info['value']
                date_condition = {"$or": [
                    {"date": date_value},
                    {"date": {"$regex": f"^{date_value}"}},
                    {"productionDate": date_value},
                    {"productionDate": {"$regex": f"^{date_value}"}}
                ]}
                query_conditions.append(date_condition)
            elif date_info['type'] == 'relative_date' and isinstance(date_info.get('value'), dict):
                start_date = date_info['value']['start']
                end_date = date_info['value']['end']
                date_range_condition = {"$or": [
                    {"date": {"$gte": start_date, "$lte": end_date}},
                    {"productionDate": {"$gte": start_date, "$lte": end_date}}
                ]}
                query_conditions.append(date_range_condition)
        
        # Combine all conditions with AND
        if query_conditions:
            comprehensive_query = {"$and": query_conditions}
            print(f"Comprehensive query: {comprehensive_query}")
        else:
            comprehensive_query = query
            
        # Add an option to search all collections for production data
        all_collections = [coll for coll in available_collections if 'test' not in coll.lower()]
        print(f"Will search across all {len(all_collections)} collections if needed")
        
        # Select performance collections to try, prioritizing based on analysis
        performance_collections = []
        
        # First try collections that match common performance naming patterns
        for coll in available_collections:
            if any(pattern in coll.lower() for pattern in ['performance', 'production', 'output', 'workshop']):
                performance_collections.append(coll)
        
        # Add specific known collection names if they exist
        if 'performance3' in available_collections and 'performance3' not in performance_collections:
            performance_collections.append('performance3')
        if 'monthly_performance' in available_collections and 'monthly_performance' not in performance_collections:
            performance_collections.append('monthly_performance')
            
        # If still no collections found, use defaults
        if not performance_collections:
            performance_collections = ['performance3', 'monthly_performance']
        
        print(f"Performance collections to try first: {performance_collections}")
        
        # Track hour filter separately to apply after database query if needed
        has_hour_filter = 'hour' in analysis['filters']
        hour_value = analysis['filters'].get('hour')
        
        # Try each collection with the comprehensive query
        documents = []
        collection_used = None
        
        for collection_name in performance_collections:
            if collection_name in available_collections:
                try:
                    print(f"Querying collection: {collection_name} with comprehensive query")
                    current_docs = list(db[collection_name].find(comprehensive_query))  # Removed limit
                    if current_docs:
                        print(f"Found {len(current_docs)} documents in {collection_name}")
                        documents = current_docs
                        collection_used = collection_name
                        break
                except Exception as e:
                    print(f"Error querying {collection_name}: {e}")
        
        # If no results with comprehensive query, try with original query
        if not documents and query and query != comprehensive_query:
            print("No results with comprehensive query, trying original query...")
            
            for collection_name in performance_collections:
                if collection_name in available_collections:
                    try:
                        print(f"Querying collection: {collection_name} with original query")
                        current_docs = list(db[collection_name].find(query))  # Removed limit
                        if current_docs:
                            print(f"Found {len(current_docs)} documents in {collection_name}")
                            documents = current_docs
                            collection_used = collection_name
                            break
                    except Exception as e:
                        print(f"Error querying {collection_name}: {e}")
        
        # If still no results, try a special query just looking for workshop
        if not documents and 'workshop' in analysis['filters']:
            print("Trying a more flexible workshop-only search...")
            workshop_id = analysis['filters']['workshop']
            
            # Create a more flexible workshop query
            flexible_workshop_query = {"$or": [
                {"workshop": {"$regex": workshop_id, "$options": "i"}},
                {"workshopId": {"$regex": workshop_id, "$options": "i"}},
                {"workshop_id": {"$regex": workshop_id, "$options": "i"}},
                {"Workshop": {"$regex": workshop_id, "$options": "i"}}
            ]}
            
            # Try in performance collections first
            for collection_name in performance_collections:
                if collection_name in available_collections:
                    try:
                        print(f"Trying flexible workshop query in {collection_name}")
                        workshop_docs = list(db[collection_name].find(flexible_workshop_query))  # Removed limit
                        if workshop_docs:
                            print(f"Found {len(workshop_docs)} documents with flexible workshop query")
                            
                            # If we have an hour filter, try to apply it in memory
                            if hour_value:
                                print(f"Filtering for hour: {hour_value}")
                                filtered_docs = []
                                for doc in workshop_docs:
                                    # Check for hour in various formats and fields
                                    hour_matched = False
                                    
                                    # Print document for debugging
                                    print(f"Checking document: {str(doc)[:100]}...")
                                    
                                    # Check hour in standard fields
                                    for hour_field in ['hour', 'timeHour', 'time_hour', 'Hour']:
                                        if hour_field in doc:
                                            doc_hour = str(doc[hour_field])
                                            print(f"Found hour field: {hour_field}={doc_hour}")
                                            if (doc_hour == hour_value or 
                                                doc_hour.startswith(f"{hour_value}:") or
                                                hour_value in doc_hour):
                                                hour_matched = True
                                                print(f"Matched hour: {doc_hour}")
                                                break
                                    
                                    # Check date field for hour
                                    if not hour_matched and 'date' in doc and isinstance(doc['date'], str):
                                        date_str = doc['date']
                                        print(f"Checking date field: {date_str}")
                                        if 'T' in date_str:
                                            time_part = date_str.split('T')[1]
                                            if time_part.startswith(f"{hour_value}:") or time_part.startswith(f"{hour_value.zfill(2)}:"):
                                                hour_matched = True
                                                print(f"Matched hour in date: {time_part}")
                                    
                                    if hour_matched:
                                        filtered_docs.append(doc)
                                
                                if filtered_docs:
                                    documents = filtered_docs
                                    collection_used = collection_name
                                    print(f"After filtering: {len(documents)} documents match hour {hour_value}")
                                    break
                                else:
                                    print(f"No documents match hour {hour_value}")
                            else:
                                # If no hour filter, use all the workshops docs
                                documents = workshop_docs
                                collection_used = collection_name
                                break
                    except Exception as e:
                        print(f"Error with flexible workshop query: {e}")
            
            # If still nothing found, try all collections as a last resort
            if not documents:
                print("Last resort: Checking all collections for workshop data...")
                for collection_name in all_collections:
                    try:
                        print(f"Checking collection: {collection_name}")
                        # First get a sample to see if this collection has relevant fields
                        sample = db[collection_name].find_one()
                        if sample:
                            # Check if this collection seems to have workshop-related data
                            has_workshop_field = any(field.lower() in ['workshop', 'workshopid'] for field in sample.keys())
                            
                            if has_workshop_field:
                                print(f"Collection {collection_name} has workshop fields, trying query")
                                all_docs = list(db[collection_name].find(flexible_workshop_query))  # Removed limit
                                if all_docs:
                                    print(f"Found {len(all_docs)} workshop documents in {collection_name}")
                                    if hour_value:
                                        # Filter for hour in memory
                                        hour_docs = []
                                        for doc in all_docs:
                                            for hour_field in ['hour', 'timeHour', 'Hour', 'time']:
                                                if hour_field in doc:
                                                    doc_hour = str(doc[hour_field])
                                                    if doc_hour == hour_value or doc_hour.startswith(f"{hour_value}:"):
                                                        hour_docs.append(doc)
                                                        break
                                        
                                        if hour_docs:
                                            documents = hour_docs
                                            collection_used = collection_name
                                            print(f"Found {len(documents)} documents matching hour {hour_value}")
                                            break
                                    else:
                                        documents = all_docs
                                        collection_used = collection_name
                                        break
                    except Exception as e:
                        print(f"Error checking collection {collection_name}: {e}")

        # If still no documents found, check if there's data at all in the database
        if not documents:
            # Construct a clear message about what we couldn't find
            message = "No performance data found"
            
            if 'workshop' in analysis['filters']:
                message += f" for Workshop {analysis['filters']['workshop']}"
            
            if 'chain' in analysis['filters']:
                message += f" in Chain {analysis['filters']['chain']}"
            
            if analysis.get('date_info'):
                date_info = analysis.get('date_info')
                if date_info['type'] == 'exact_date':
                    message += f" on {date_info['value']}"
                elif date_info['type'] == 'relative_date':
                    if isinstance(date_info['value'], dict):
                        message += f" between {date_info['value']['start']} and {date_info['value']['end']}"
                    else:
                        message += f" for {date_info.get('description', date_info['value'])}"
            
            if 'hour' in analysis['filters']:
                message += f" at {analysis['filters']['hour']}:00"
                
            # Check if there's any production data at all
            for collection_name in performance_collections:
                if collection_name in available_collections:
                    try:
                        count = db[collection_name].count_documents({})
                        if count > 0:
                            message += f". Found {count} total records in {collection_name} collection."
                            
                            # Sample a document to show format
                            sample = db[collection_name].find_one()
                            if sample:
                                if 'workshop' in sample:
                                    message += f" Sample workshop format: '{sample['workshop']}'"
                                if 'hour' in sample:
                                    message += f" Sample hour format: '{sample['hour']}'"
                            break
                    except Exception:
                        pass
            
            return message
        
        # Apply hour filter after database query if needed
        if has_hour_filter and hour_value and documents:
            print(f"Applying hour filter {hour_value} after database query")
            filtered_documents = []
            
            for doc in documents:
                # Check all possible hour field representations
                hour_matched = False
                
                # Try 'hour' field - could be string or integer
                if 'hour' in doc:
                    doc_hour = str(doc['hour'])
                    # Handle formats like "13:00" or just "13"
                    if doc_hour == hour_value or doc_hour.startswith(f"{hour_value}:"):
                        hour_matched = True
                        print(f"Matched hour value: {doc_hour}")
                
                # Try 'timeHour' field - could be string or integer
                elif 'timeHour' in doc:
                    doc_hour = str(doc['timeHour'])
                    # Handle formats like "13:00" or just "13"
                    if doc_hour == hour_value or doc_hour.startswith(f"{hour_value}:"):
                        hour_matched = True
                        print(f"Matched timeHour value: {doc_hour}")
                
                # Try to extract hour from date field if it exists
                elif 'date' in doc and isinstance(doc['date'], str) and 'T' in doc['date']:
                    # Extract hour from ISO date format like "2025-05-09T13:00:00Z"
                    try:
                        date_parts = doc['date'].split('T')
                        if len(date_parts) > 1 and ':' in date_parts[1]:
                            extracted_hour = date_parts[1].split(':')[0]
                            if extracted_hour == hour_value:
                                hour_matched = True
                                print(f"Matched hour from date: {extracted_hour}")
                    except Exception:
                        pass
                
                # Print documents that don't match for debugging
                if not hour_matched and ('hour' in doc or 'timeHour' in doc):
                    print(f"Non-matching hour value: {doc.get('hour', doc.get('timeHour', 'unknown'))}")
                
                if hour_matched:
                    filtered_documents.append(doc)
            
            if filtered_documents:
                print(f"Hour filter applied: Kept {len(filtered_documents)} of {len(documents)} documents")
                documents = filtered_documents
            else:
                print(f"Hour filter applied: No documents match hour {hour_value}")
                # Debug: List some of the documents to see what hours are available
                available_hours = set()
                for doc in documents[:10]:  # Check first 10 docs
                    if 'hour' in doc:
                        available_hours.add(str(doc['hour']))
                    elif 'timeHour' in doc:
                        available_hours.add(str(doc['timeHour']))
                if available_hours:
                    print(f"Available hours in data: {', '.join(available_hours)}")
                
                return f"No performance data found for Workshop {analysis['filters'].get('workshop', '')} at {hour_value}:00 on {analysis.get('date_info', {}).get('value', '')}"
        
        # Apply additional check for workshop format if needed
        if 'workshop' in analysis['filters'] and documents:
            workshop_id = analysis['filters']['workshop']
            expected_formats = [
                workshop_id,  # Plain ID: "3"
                f"Workshop {workshop_id}",  # With prefix: "Workshop 3"
                f"W{workshop_id}",  # Short form: "W3"
                f"workshop {workshop_id}",  # Lowercase: "workshop 3"
                f"Workshop{workshop_id}"  # No space: "Workshop3"
            ]
            
            workshop_filtered_docs = []
            for doc in documents:
                if 'workshop' in doc:
                    doc_workshop = str(doc['workshop'])
                    if any(doc_workshop == expected for expected in expected_formats):
                        workshop_filtered_docs.append(doc)
                        print(f"Matched workshop format: {doc_workshop}")
            
            if workshop_filtered_docs:
                print(f"Workshop format filter applied: Kept {len(workshop_filtered_docs)} of {len(documents)} documents")
                documents = workshop_filtered_docs
                
        # Process the results if we have documents
        if not documents:
            print("[DEBUG] Returning from get_performance_data: no documents found")
            return "No performance data found matching your criteria."
        # Determine the fields available in the documents
        sample_doc = documents[0]
        fields = list(sample_doc.keys())
        
        # Identify field names for production and defects
        production_fields = [f for f in fields if any(p in f.lower() for p in ['produced', 'production', 'output'])]
        defect_fields = [f for f in fields if any(p in f.lower() for p in ['defect', 'quality'])]
        order_fields = [f for f in fields if any(p in f.lower() for p in ['order', 'reference', 'ref'])]
        target_fields = [f for f in fields if any(p in f.lower() for p in ['target', 'goal', 'plan'])]
        
        # Default field names if we couldn't identify specific ones
        production_field = production_fields[0] if production_fields else 'produced'
        defect_field = defect_fields[0] if defect_fields else 'defects'
        order_field = order_fields[0] if order_fields else 'orderRef'
        target_field = target_fields[0] if target_fields else 'productionTarget'
        
        print(f"Using fields - Production: {production_field}, Defects: {defect_field}, Order: {order_field}, Target: {target_field}")
        
        total_produced = 0
        total_defects = 0
        total_target = 0
        
        # Track various dimensions for grouping
        by_workshop = {}
        by_chain = {}
        by_date = {}
        by_hour = {}
        by_order = {}
        
        # Process each document
        for doc in documents:
            # Extract production, defects, and target values
            produced = safe_get_numeric(doc, [production_field, 'produced', 'production', 'output'])
            defects = safe_get_numeric(doc, [defect_field, 'defects', 'qualityIssues'])
            target = safe_get_numeric(doc, [target_field, 'productionTarget', 'target', 'goal'])
            
            # Update totals
            total_produced += produced
            total_defects += defects
            total_target += target
            
            # Get workshop (if available)
            workshop = None
            for w_field in ['workshop', 'workshopId', 'workshop_id']:
                if w_field in doc and doc[w_field] is not None:
                    workshop = str(doc[w_field])
                    break
            
            # Get chain (if available)
            chain = None
            for c_field in ['chain', 'chainId', 'chain_id']:
                if c_field in doc and doc[c_field] is not None:
                    chain = str(doc[c_field])
                    break
            
            # Get order reference (if available)
            order_ref = None
            for o_field in [order_field, 'orderRef', 'order_reference', 'orderReference']:
                if o_field in doc and doc[o_field] is not None:
                    order_ref = str(doc[o_field])
                    break
            
            # Get date and hour (if available)
            date = None
            hour = None
            if 'date' in doc and doc['date']:
                date_str = str(doc['date'])
                # Handle ISO date format (2025-05-09T00:00:00.000Z)
                if 'T' in date_str:
                    date_parts = date_str.split('T')
                    date = date_parts[0]
                    # Extract hour if available
                    if len(date_parts) > 1 and ':' in date_parts[1]:
                        hour = date_parts[1].split(':')[0]
                else:
                    date = date_str
            
            if 'hour' in doc and doc['hour'] is not None:
                hour = str(doc['hour'])
            
            # Group by different dimensions
            if workshop:
                if workshop not in by_workshop:
                    by_workshop[workshop] = {'produced': 0, 'defects': 0, 'target': 0}
                by_workshop[workshop]['produced'] += produced
                by_workshop[workshop]['defects'] += defects
                by_workshop[workshop]['target'] += target
            
            if chain:
                if chain not in by_chain:
                    by_chain[chain] = {'produced': 0, 'defects': 0, 'target': 0}
                by_chain[chain]['produced'] += produced
                by_chain[chain]['defects'] += defects
                by_chain[chain]['target'] += target
            
            if date:
                if date not in by_date:
                    by_date[date] = {'produced': 0, 'defects': 0, 'target': 0}
                by_date[date]['produced'] += produced
                by_date[date]['defects'] += defects
                by_date[date]['target'] += target
            
            if hour:
                if hour not in by_hour:
                    by_hour[hour] = {'produced': 0, 'defects': 0, 'target': 0}
                by_hour[hour]['produced'] += produced
                by_hour[hour]['defects'] += defects
                by_hour[hour]['target'] += target
            
            if order_ref:
                if order_ref not in by_order:
                    by_order[order_ref] = {'produced': 0, 'defects': 0, 'target': 0}
                by_order[order_ref]['produced'] += produced
                by_order[order_ref]['defects'] += defects
                by_order[order_ref]['target'] += target
        
        # Format the response based on the query and available data
        response_parts = []
        
        # Add header based on filters
        header = "Performance Data"
        
        if 'workshop' in analysis['filters']:
            header += f" for Workshop {analysis['filters']['workshop']}"
        
        if 'chain' in analysis['filters']:
            header += f" in Chain {analysis['filters']['chain']}"
        
        if analysis.get('date_info'):
            date_info = analysis.get('date_info')
            if date_info['type'] == 'exact_date':
                header += f" on {date_info['value']}"
            elif date_info['type'] == 'relative_date':
                if isinstance(date_info['value'], dict):
                    header += f" from {date_info['value']['start']} to {date_info['value']['end']}"
                else:
                    header += f" for {date_info.get('description', date_info['value'])}"
        
        response_parts.append(header)
        
        # Add overall statistics
        if 'production' in analysis['metrics'] or 'defects' in analysis['metrics'] or not analysis['metrics']:
            if total_produced > 0:
                response_parts.append(f"Total production: {total_produced:.0f} units")
            
            if total_defects > 0:
                response_parts.append(f"Total defects: {total_defects:.0f}")
                if total_produced > 0:
                    defect_rate = (total_defects / total_produced) * 100
                    response_parts.append(f"Defect rate: {defect_rate:.2f}%")
            
            if total_target > 0:
                response_parts.append(f"Production target: {total_target:.0f} units")
                if total_produced > 0:
                    completion_rate = (total_produced / total_target) * 100
                    response_parts.append(f"Target completion: {completion_rate:.2f}%")
        
        # Add breakdown by specific dimension based on the query
        # If the query is filtered by workshop, show breakdown by date/hour
        # If the query is filtered by date, show breakdown by workshop/chain
        
        if 'workshop' in analysis['filters'] and by_hour and len(by_hour) > 1:
            # Show hour breakdown for specific workshop
            response_parts.append("\nProduction by hour:")
            hour_lines = []
            for hour, data in sorted(by_hour.items(), key=lambda x: x[0]):
                hour_lines.append(f"Hour {hour}: {data['produced']:.0f} units, {data['defects']:.0f} defects")
            response_parts.append(" | ".join(hour_lines[:5]))  # Show top 5
        
        elif 'date' in analysis['filters'] and by_workshop and len(by_workshop) > 1:
            # Show workshop breakdown for specific date
            response_parts.append("\nProduction by workshop:")
            workshop_lines = []
            for workshop, data in sorted(by_workshop.items(), key=lambda x: x[1]['produced'], reverse=True):
                workshop_lines.append(f"Workshop {workshop}: {data['produced']:.0f} units, {data['defects']:.0f} defects")
            response_parts.append(" | ".join(workshop_lines[:5]))  # Show top 5
        
        elif len(by_date) > 1 and not 'date' in analysis['filters']:
            # Show date breakdown if multiple dates and not filtered by date
            response_parts.append("\nProduction by date:")
            date_lines = []
            for date, data in sorted(by_date.items(), key=lambda x: x[0]):
                date_lines.append(f"{date}: {data['produced']:.0f} units, {data['defects']:.0f} defects")
            response_parts.append(" | ".join(date_lines[:5]))  # Show most recent 5
        
        elif len(by_workshop) > 1 and not 'workshop' in analysis['filters']:
            # Show workshop breakdown if multiple workshops and not filtered by workshop
            response_parts.append("\nProduction by workshop:")
            workshop_lines = []
            for workshop, data in sorted(by_workshop.items(), key=lambda x: x[1]['produced'], reverse=True):
                workshop_lines.append(f"Workshop {workshop}: {data['produced']:.0f} units, {data['defects']:.0f} defects")
            response_parts.append(" | ".join(workshop_lines[:5]))  # Show top 5
        
        # If order references are present, show them
        if by_order and len(by_order) > 0:
            response_parts.append("\nProduction by order:")
            order_lines = []
            for order_ref, data in sorted(by_order.items(), key=lambda x: x[1]['produced'], reverse=True):
                # Try to get target from order_references collection if available
                target = data['target']
                if target == 0 and 'order_references' in available_collections:
                    try:
                        order_doc = db.order_references.find_one({"orderRef": order_ref})
                        if order_doc and 'productionTarget' in order_doc:
                            target = float(order_doc['productionTarget'])
                    except Exception:
                        pass
                
                order_line = f"Order {order_ref}: {data['produced']:.0f} units"
                if target > 0:
                    completion = (data['produced'] / target) * 100
                    order_line += f" ({completion:.1f}% of target)"
                order_lines.append(order_line)
            response_parts.append(" | ".join(order_lines[:5]))  # Show top 5
        
        # --- SUM-ONLY LOGIC FOR PRODUCTION ---
        if analysis.get('math_operation') == 'sum' and 'production' in analysis['metrics']:
            total_produced = sum(safe_get_numeric(doc, [production_field, 'produced', 'production', 'output']) for doc in documents)
            return f"Total production: {total_produced:.0f} units"
        
        print(f"[DEBUG] About to call format_response with {len(documents)} docs, analysis: {analysis}")
        return format_response(documents, analysis)
    
    except Exception as e:
        print(f"Error retrieving performance data: {e}")
        return f"Error retrieving performance data: {str(e)}"

if __name__ == "__main__":
    print("Starting chatbot service on port 5001...")
    app.run(host='0.0.0.0', port=5001, debug=True)
