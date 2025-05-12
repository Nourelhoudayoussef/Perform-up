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
        'calculation_type': None
    }
    
    # Detect intent for machine failures specifically
    failure_patterns = [
        r'(machine|equipment)\s+(failures?|breakdowns?|issues?|problems?)',
        r'(failures?|breakdowns?)\s+of\s+(machines?|equipment)',
        r'(show|display|get|list|find)\s+.*\s+(machine|equipment)\s+(failures?|breakdowns?)',
        r'(distribution|spread|statistics)\s+of\s+(machine|equipment)\s+(failures?|breakdowns?)'
    ]
    
    for pattern in failure_patterns:
        if re.search(pattern, text, re.IGNORECASE):
            analysis['metrics'].add('failures')
            print("Detected machine failure query intent")
            
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
        'production': r'production|output|produced|units|quantity',
        'defects': r'defects?|errors?|quality issues?',
        'efficiency': r'efficiency|performance|productivity',
        'failures': r'failures?|breakdowns?|maintenance|repairs?',
        'target': r'target|goal|objective',
        'variance': r'variance|deviation|difference'
    }
    
    # Check for general keywords related to each metric
    for metric, pattern in metric_patterns.items():
        if re.search(pattern, text, re.IGNORECASE):
            analysis['metrics'].add(metric)
    
    # Extract filters using generic patterns
    filter_patterns = {
        'workshop': r'workshop\s*(\d+)',
        'machine': r'machine\s+(?:id|reference|ref|number)?\s*([a-zA-Z0-9\-]+)',  # More specific machine pattern
        'technician': r'(?:technician|handled by|fixed by|repaired by)\s+([^\s,.?!][^,.?!]*)',
        'order': r'order\s*(?:reference|ref)?\s*#?\s*(\d+)',
        'chain': r'chain\s*([a-zA-Z0-9\-]+)'
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
        if match:
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
        elif filter_type == 'chain':
            query['chain'] = {'$regex': value, '$options': 'i'}
    
    return query

def format_response(data, analysis):
    """Format the response based on the data and analysis"""
    if not data:
        if 'failures' in analysis['metrics']:
            return "No machine failures found matching your criteria."
        
        # For order reference, give more specific message
        if 'order' in analysis['filters']:
            return f"No data found for order {analysis['filters']['order']}. Please check the order reference number and try again."
            
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
            if not analysis['filters'] and len(query) == 0:
                query = {}  # Clear the query to get all machine failures
                print("Using empty query to find all machine failures")
            else:
                print(f"Applying filters to machine failures query: {analysis['filters']}")
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

@app.route("/chatbot", methods=["POST"])
def chatbot():
    data = request.get_json()
    message = data.get("message", "").lower()
    
    # Analyze the question
    analysis = analyze_question(message)
    
    # Query the database and get response
    response = query_database(analysis)
    
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

if __name__ == "__main__":
    print("Starting chatbot service on port 5001...")
    app.run(host='0.0.0.0', port=5001, debug=True)
