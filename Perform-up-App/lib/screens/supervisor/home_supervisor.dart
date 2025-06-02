import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../../services/supervisor_service.dart';
import '../../widgets/floating_ai_bubble.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class HomeSupervisorScreen extends StatefulWidget {
  const HomeSupervisorScreen({Key? key}) : super(key: key);

  @override
  State<HomeSupervisorScreen> createState() => _HomeSupervisorScreenState();
}

class _HomeSupervisorScreenState extends State<HomeSupervisorScreen> {
  final SupervisorService _supervisorService = SupervisorService();

  // State for daily target
  String? _selectedProductRef;
  int? _targetQuantity;
  Map<String, int> _productTargets = {};
  DateTime? _lastTargetDate;

  // State for workshop and chains
  String? _selectedWorkshop = '1';
  Map<String, bool> _expandedChains = {'1': false, '2': false, '3': false};
  
  // New: {productRef: {workshop: {chain: {hour: {data}}}}}
  static Map<String, Map<String, Map<String, Map<String, Map<String, dynamic>>>>> _persistentPerformanceData = {};
  Map<String, Map<String, Map<String, Map<String, Map<String, dynamic>>>>> _performanceData = {};

  final List<String> _productRefs = ['101', '102', '103', '104', '105'];
  final List<String> _workshops = ['1', '2', '3'];
  final List<String> _chains = ['1', '2', '3'];
  final List<String> _hours = [
    '08:00', '09:00', '10:00', '11:00', '12:00', '13:00', '14:00', '15:00'
  ];

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadSavedTargets();
    _loadSavedPerformanceData();
  }

  Future<void> _loadSavedTargets() async {
    final prefs = await SharedPreferences.getInstance();
    final savedDate = prefs.getString('lastTargetDate');
    final savedTargets = prefs.getString('productTargets');
    
    if (savedDate != null) {
      _lastTargetDate = DateTime.parse(savedDate);
    }

    if (savedTargets != null) {
      final Map<String, dynamic> decoded = json.decode(savedTargets);
      setState(() {
        _productTargets = decoded.map((key, value) => MapEntry(key, value as int));
      });
    }
  }

  Future<void> _saveTargets() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lastTargetDate', DateTime.now().toIso8601String());
    await prefs.setString('productTargets', json.encode(_productTargets));
  }

  Future<void> _loadSavedPerformanceData() async {
    final prefs = await SharedPreferences.getInstance();
    final savedData = prefs.getString('performanceData');

    // Start with a fresh structure
    Map<String, Map<String, Map<String, Map<String, Map<String, dynamic>>>>> data = {};

    if (savedData != null) {
      final Map<String, dynamic> decoded = json.decode(savedData);
      data = decoded.map((productKey, productData) {
        return MapEntry(
          productKey,
          (productData as Map<String, dynamic>).map((workshopKey, workshopData) {
            return MapEntry(
              workshopKey,
              (workshopData as Map<String, dynamic>).map((chainKey, chainData) {
                return MapEntry(
                  chainKey,
                  (chainData as Map<String, dynamic>).map((hourKey, hourData) {
                    return MapEntry(
                      hourKey,
                      Map<String, dynamic>.from(hourData as Map),
                    );
                  }),
                );
              }),
            );
          }),
        );
      });
    }

    // Ensure all productRefs/workshops/chains/hours are present
    for (var productRef in _productRefs) {
      data.putIfAbsent(productRef, () => {});
      for (var workshop in _workshops) {
        data[productRef]!.putIfAbsent(workshop, () => {});
      for (var chain in _chains) {
          data[productRef]![workshop]!.putIfAbsent(chain, () => {});
        for (var hour in _hours) {
            data[productRef]![workshop]![chain]!.putIfAbsent(hour, () => {
            'produced': '',
            'defected': '',
            'defectType': '',
            });
          }
        }
      }
    }

    setState(() {
      _persistentPerformanceData = data;
    _performanceData = Map.from(_persistentPerformanceData);
    });
  }

  Future<void> _savePerformanceData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('performanceData', json.encode(_persistentPerformanceData));
  }

  bool _canSetNewTargets() {
    if (_lastTargetDate == null) return true;
    
    final now = DateTime.now();
    // Check if it's a new day
    final isNewDay = _lastTargetDate!.year != now.year || 
                     _lastTargetDate!.month != now.month || 
                     _lastTargetDate!.day != now.day;
    
    // If it's a new day, we can set new targets
    if (isNewDay) {
      // Clear previous targets for the new day
      setState(() {
        _productTargets.clear();
        _lastTargetDate = null;
      });
      _saveTargets();
      return true;
    }
    
    // If it's the same day, we can still set targets for products that don't have one yet
    return true;
  }

  void _setDailyTarget() async {
    if (_selectedProductRef == null || _targetQuantity == null) return;

    // Check if this product already has a target for today
    if (_productTargets.containsKey(_selectedProductRef)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This product already has a target set for today.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      await _supervisorService.setDailyTarget(
        int.parse(_selectedProductRef!),
        _targetQuantity!,
      );
      setState(() {
        _productTargets[_selectedProductRef!] = _targetQuantity!;
        if (_lastTargetDate == null) {
          _lastTargetDate = DateTime.now();
        }
        // Save targets after successful API call
        _saveTargets();
        // Reset selection after setting target
        _selectedProductRef = null;
        _targetQuantity = null;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error setting target: $e')),
      );
    }
    setState(() => _isLoading = false);
  }

  void _savePerformance(String chain, String hour) async {
    if (_selectedProductRef == null || _selectedWorkshop == null) return;
    setState(() => _isLoading = true);
    try {
      final entry = _performanceData[_selectedProductRef!]![_selectedWorkshop!]![chain]![hour]!;
      await _supervisorService.recordPerformanceData({
        'hour': hour,
        'workshopInt': int.parse(_selectedWorkshop!),
        'chainInt': int.parse(chain),
        'produced': int.tryParse(entry['produced'].toString()) ?? 0,
        'defectList': [
          {
            'defectType': entry['defectType'],
            'count': int.tryParse(entry['defected'].toString()) ?? 0,
          }
        ],
        'orderRef': int.tryParse(_selectedProductRef ?? ''),
      });
      // Update persistent data
      _persistentPerformanceData[_selectedProductRef!]![_selectedWorkshop!]![chain]![hour] = Map.from(entry);
      // Save to persistent storage
      _savePerformanceData();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Performance saved!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving performance: $e')),
      );
    }
    setState(() => _isLoading = false);
  }

  @override
  void dispose() {
    _saveTargets();
    _savePerformanceData();
    super.dispose();
  }

  Widget _buildTargetSection() {
    final canSetNewTargets = _canSetNewTargets();
    final allProductsHaveTargets = _productRefs.every((ref) => _productTargets.containsKey(ref));
    
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (allProductsHaveTargets)
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Text(
                  'All product targets set for today',
                  style: GoogleFonts.poppins(
                    color: Colors.green[600],
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Product',
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0F7F5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: DropdownButton<String>(
                      value: _selectedProductRef,
                      hint: const Text('Ref'),
                      isExpanded: true,
                      underline: const SizedBox(),
                          items: _productRefs.map((ref) {
                            final hasTarget = _productTargets.containsKey(ref);
                            final isSelected = ref == _selectedProductRef;
                            return DropdownMenuItem(
                              value: ref,
                              child: Text(
                                ref,
                                style: TextStyle(
                                  color: isSelected ? Colors.black : (hasTarget ? Colors.grey : Colors.black),
                                ),
                              ),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setState(() {
                                _selectedProductRef = val;
                                if (_productTargets.containsKey(val)) {
                                  _targetQuantity = _productTargets[val];
                                } else {
                                  _targetQuantity = null;
                                }
                              });
                            }
                          },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Target',
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 6),
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0F7F5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: TextField(
                          enabled: _selectedProductRef != null && !_productTargets.containsKey(_selectedProductRef),
                          keyboardType: TextInputType.number,
                          controller: TextEditingController(
                            text: _selectedProductRef != null && _productTargets.containsKey(_selectedProductRef)
                                ? _productTargets[_selectedProductRef].toString()
                                : '',
                          ),
                          decoration: InputDecoration(
                            hintText: _selectedProductRef == null 
                                ? 'Quantity'
                                : _productTargets.containsKey(_selectedProductRef)
                                    ? 'Target already set'
                                    : 'Quantity',
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          ),
                          onChanged: (val) => _targetQuantity = int.tryParse(val),
                        ),
                      ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            ElevatedButton(
                  onPressed: (_isLoading || _selectedProductRef == null || _productTargets.containsKey(_selectedProductRef))
                      ? null
                      : _setDailyTarget,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6BBFB5),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                minimumSize: const Size(0, 40),
              ),
                  child: const Text('Set Target', style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWorkshopDropdown() {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: const Color(0xFFD0ECE8),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: DropdownButtonFormField<String>(
        value: _selectedWorkshop,
        items: _workshops.map((w) => DropdownMenuItem(value: w, child: Text('Workshop $w'))).toList(),
        onChanged: (val) => setState(() => _selectedWorkshop = val),
        decoration: InputDecoration(
          filled: true,
          fillColor: const Color(0xFFD0ECE8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        ),
      ),
    );
  }

  Widget _buildChainCard(String chain) {
    final isExpanded = _expandedChains[chain]!;
    // Get performance data for current product, workshop and chain
    final chainData = _performanceData[_selectedProductRef]?[_selectedWorkshop]?[chain] ?? {};
    
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: const Color(0xFFE8F6F3),
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        children: [
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF6BBFB5).withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.link, color: Color(0xFF6BBFB5)),
            ),
            title: Text(
              'Chaine $chain',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            trailing: IconButton(
              icon: Icon(
                isExpanded ? Icons.expand_less : Icons.expand_more,
                color: const Color(0xFF6BBFB5),
              ),
              onPressed: () => setState(() => _expandedChains[chain] = !isExpanded),
            ),
          ),
          if (!isExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: _hours.map((hour) {
                  final entry = chainData[hour] ?? {
                    'produced': '',
                    'defected': '',
                    'defectType': '',
                  };
                  final isLogged = entry['produced'].toString().isNotEmpty && 
                                 entry['defected'].toString().isNotEmpty;
                  return Column(
                    children: [
                      Text(
                        hour,
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: isLogged ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          isLogged ? Icons.check_circle : Icons.cancel,
                          color: isLogged ? Colors.green : Colors.red,
                          size: 20,
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          if (isExpanded)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: _hours.map((hour) {
                  final entry = chainData[hour] ?? {
                    'produced': '',
                    'defected': '',
                    'defectType': '',
                  };
                  final producedController = TextEditingController(text: entry['produced'].toString());
                  final defectedController = TextEditingController(text: entry['defected'].toString());
                  final defectTypeController = TextEditingController(text: entry['defectType'].toString());
                  
                  return Card(
                    elevation: 0,
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    color: Colors.white,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 60,
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF6BBFB5).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  hour,
                                  style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.w500,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              const Spacer(),
                              Container(
                                decoration: BoxDecoration(
                                  color: const Color(0xFF6BBFB5).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: IconButton(
                                  icon: const Icon(Icons.save, color: Color(0xFF6BBFB5)),
                                  onPressed: () => _savePerformance(chain, hour),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: producedController,
                                  keyboardType: TextInputType.number,
                                  style: GoogleFonts.poppins(
                                    fontSize: 15,
                                    color: Colors.black87,
                                  ),
                                  decoration: InputDecoration(
                                    labelText: 'Produced',
                                    labelStyle: GoogleFonts.poppins(
                                      fontSize: 14,
                                      color: Colors.black54,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide.none,
                                    ),
                                    filled: true,
                                    fillColor: const Color(0xFFF0F7F5),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                                  ),
                                  onChanged: (val) {
                                    if (_selectedProductRef == null || _selectedWorkshop == null) return;
                                    if (_performanceData[_selectedProductRef!] == null) {
                                      _performanceData[_selectedProductRef!] = {};
                                    }
                                    if (_performanceData[_selectedProductRef!]![_selectedWorkshop!] == null) {
                                      _performanceData[_selectedProductRef!]![_selectedWorkshop!] = {};
                                    }
                                    if (_performanceData[_selectedProductRef!]![_selectedWorkshop!]![chain] == null) {
                                      _performanceData[_selectedProductRef!]![_selectedWorkshop!]![chain] = {};
                                    }
                                    if (_performanceData[_selectedProductRef!]![_selectedWorkshop!]![chain]![hour] == null) {
                                      _performanceData[_selectedProductRef!]![_selectedWorkshop!]![chain]![hour] = {
                                        'produced': '',
                                        'defected': '',
                                        'defectType': '',
                                      };
                                    }
                                    _performanceData[_selectedProductRef!]![_selectedWorkshop!]![chain]![hour]!['produced'] = val;
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextFormField(
                                  controller: defectedController,
                                  keyboardType: TextInputType.number,
                                  style: GoogleFonts.poppins(
                                    fontSize: 15,
                                    color: Colors.black87,
                                  ),
                                  decoration: InputDecoration(
                                    labelText: 'Defected',
                                    labelStyle: GoogleFonts.poppins(
                                      fontSize: 14,
                                      color: Colors.black54,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide.none,
                                    ),
                                    filled: true,
                                    fillColor: const Color(0xFFF0F7F5),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                                  ),
                                  onChanged: (val) {
                                    if (_selectedProductRef == null || _selectedWorkshop == null) return;
                                    if (_performanceData[_selectedProductRef!] == null) {
                                      _performanceData[_selectedProductRef!] = {};
                                    }
                                    if (_performanceData[_selectedProductRef!]![_selectedWorkshop!] == null) {
                                      _performanceData[_selectedProductRef!]![_selectedWorkshop!] = {};
                                    }
                                    if (_performanceData[_selectedProductRef!]![_selectedWorkshop!]![chain] == null) {
                                      _performanceData[_selectedProductRef!]![_selectedWorkshop!]![chain] = {};
                                    }
                                    if (_performanceData[_selectedProductRef!]![_selectedWorkshop!]![chain]![hour] == null) {
                                      _performanceData[_selectedProductRef!]![_selectedWorkshop!]![chain]![hour] = {
                                        'produced': '',
                                        'defected': '',
                                        'defectType': '',
                                      };
                                    }
                                    _performanceData[_selectedProductRef!]![_selectedWorkshop!]![chain]![hour]!['defected'] = val;
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextFormField(
                                  controller: defectTypeController,
                                  style: GoogleFonts.poppins(
                                    fontSize: 15,
                                    color: Colors.black87,
                                  ),
                                  decoration: InputDecoration(
                                    labelText: 'Def-Type',
                                    labelStyle: GoogleFonts.poppins(
                                      fontSize: 14,
                                      color: Colors.black54,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide.none,
                                    ),
                                    filled: true,
                                    fillColor: const Color(0xFFF0F7F5),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                                  ),
                                  onChanged: (val) {
                                    if (_selectedProductRef == null || _selectedWorkshop == null) return;
                                    if (_performanceData[_selectedProductRef!] == null) {
                                      _performanceData[_selectedProductRef!] = {};
                                    }
                                    if (_performanceData[_selectedProductRef!]![_selectedWorkshop!] == null) {
                                      _performanceData[_selectedProductRef!]![_selectedWorkshop!] = {};
                                    }
                                    if (_performanceData[_selectedProductRef!]![_selectedWorkshop!]![chain] == null) {
                                      _performanceData[_selectedProductRef!]![_selectedWorkshop!]![chain] = {};
                                    }
                                    if (_performanceData[_selectedProductRef!]![_selectedWorkshop!]![chain]![hour] == null) {
                                      _performanceData[_selectedProductRef!]![_selectedWorkshop!]![chain]![hour] = {
                                        'produced': '',
                                        'defected': '',
                                        'defectType': '',
                                      };
                                    }
                                    _performanceData[_selectedProductRef!]![_selectedWorkshop!]![chain]![hour]!['defectType'] = val;
                                  },
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F7F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFFD0ECE8),
        elevation: 0,
        shadowColor: Colors.black.withOpacity(0.1),
        toolbarHeight: 70,
        leadingWidth: 56,
        title: Text(
          DateFormat('EEEE, MMMM d').format(DateTime.now()),
          style: GoogleFonts.poppins(
            fontSize: 20,
            fontWeight: FontWeight.w500,
            color: const Color(0xC5000000),
          ),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            child: IconButton(
              icon: const Icon(
                FontAwesomeIcons.solidBell,
                color: Color(0xC5000000),
              ),
              onPressed: () {
                Navigator.pushNamed(context, '/notifications');
              },
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF6BBFB5)))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  _buildTargetSection(),
                  _buildWorkshopDropdown(),
                  ..._chains.map(_buildChainCard).toList(),
                ],
              ),
            ),
          FloatingAIBubble(
            onTap: () => Navigator.pushNamed(context, '/chatbot'),
          ),
        ],
      ),
    );
  }
} 