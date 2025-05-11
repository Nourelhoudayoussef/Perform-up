import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../services/supervisor_service.dart'; // Updated import

class HomeSupervisorScreen extends StatefulWidget {
  const HomeSupervisorScreen({Key? key}) : super(key: key);

  @override
  State<HomeSupervisorScreen> createState() => _HomeSupervisorScreenState();
}

class _HomeSupervisorScreenState extends State<HomeSupervisorScreen> {
  final SupervisorService _supervisorService = SupervisorService(); // Updated service

  // State
  String? _selectedProductRef;
  int? _targetQuantity;
  bool _targetSet = false;
  String? _selectedWorkshop;
  Map<String, bool> _expandedChains = {}; // key: chain number, value: expanded/collapsed
  Map<String, List<Map<String, dynamic>>> _performanceData = {}; // key: chain, value: list of hourly data

  bool _isLoading = false;

  // For product ref dropdown
  final List<String> _productRefs = ['101', '102', '103', '104', '105'];
  final List<String> _workshops = ['1', '2', '3'];
  final List<String> _chains = ['1', '2', '3'];
  final List<String> _hours = [
    '08:00', '09:00', '10:00', '11:00', '12:00', '13:00', '14:00', '15:00'
  ];

  @override
  void initState() {
    super.initState();
    _selectedWorkshop = _workshops.first;
    _fetchTargetAndPerformance();
  }

  Future<void> _fetchTargetAndPerformance() async {
    setState(() => _isLoading = true);
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    print('DEBUG: Today being sent to API in _fetchTargetAndPerformance: ' + today);
    try {
      // 1. Get today's target (if any)
      final targetData = await _supervisorService.getDailyPerformanceByDate(today);
      if (targetData != null && targetData['productRef'] != null) {
        setState(() {
          _selectedProductRef = targetData['productRef'].toString();
          _targetQuantity = int.tryParse(targetData['target'].toString());
          _targetSet = true;
        });
      } else {
        // No target set for today
        setState(() {
          _selectedProductRef = null;
          _targetQuantity = null;
          _targetSet = false;
        });
      }
    } catch (e) {
      // If error (e.g., 403 or no data), allow supervisor to set target
      setState(() {
        _selectedProductRef = null;
        _targetQuantity = null;
        _targetSet = false;
      });
    }
    // 2. Fetch performance for all chains in selected workshop (ignore errors, just show empty if needed)
    try {
      await _fetchPerformanceForWorkshop(_selectedWorkshop!, today);
    } catch (e) {
      setState(() {
        _performanceData = {};
      });
    }
    setState(() => _isLoading = false);
  }

  Future<void> _fetchPerformanceForWorkshop(String workshop, String today) async {
    print('DEBUG: Today being sent to API in _fetchPerformanceForWorkshop: ' + today);
    Map<String, List<Map<String, dynamic>>> newData = {};
    for (var chain in _chains) {
      final data = await _supervisorService.getPerformanceByDateWorkshopChain(today, workshop, chain);
      // Assume API returns a list of hourly entries
      newData[chain] = List<Map<String, dynamic>>.from(data ?? []);
    }
    setState(() {
      _performanceData = newData;
      _expandedChains = {for (var c in _chains) c: false};
    });
  }

  Future<void> _setTarget() async {
    if (_selectedProductRef == null || _targetQuantity == null) return;
    setState(() => _isLoading = true);
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    print('DEBUG: Today being sent to API in _setTarget: ' + today);
    await _supervisorService.setDailyTarget({
      'date': today,
      'orderRef': int.tryParse(_selectedProductRef ?? ''),
      'targetQuantity': _targetQuantity,
    });
    setState(() {
      _targetSet = true;
    });
    setState(() => _isLoading = false);
  }

  Future<void> _savePerformance(String chain, String hour, int produced, int defected, String defectType) async {
    setState(() => _isLoading = true);
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    print('DEBUG: Today being sent to API in _savePerformance: ' + today);
    await _supervisorService.recordPerformanceData({
      'date': today,
      'workshop': 'Workshop $_selectedWorkshop',
      'chain': 'Chain $chain',
      'hour': hour,
      'produced': produced,
      'defectList': [
        {
          'defectType': defectType,
          'count': defected,
        }
      ],
      'productionTarget': _targetQuantity,
      'orderRef': _selectedProductRef,
    });
    await _fetchPerformanceForWorkshop(_selectedWorkshop!, today);
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F7F5),
      appBar: AppBar(
        backgroundColor: Color(0xFFD0ECE8),
        elevation: 4.0,
        shadowColor: Colors.black.withOpacity(0.25),
        toolbarHeight: 60,
        leadingWidth: 56, 
        title: Text(
          DateFormat('EEEE, MMMM d').format(DateTime.now()),
          style: GoogleFonts.poppins(fontSize: 20,
                fontWeight: FontWeight.w500,
                color: Color(0xC5000000) ),
        ),
        actions: [
          IconButton(
              icon: const Icon(FontAwesomeIcons.solidBell,
                  color: Color(0xC5000000)),
              onPressed: () {
                Navigator.pushNamed(context, '/notifications');
              },
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Product & Target Section
                  Card(
                    color: Colors.white,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: _targetSet
                          ? Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Product', style: TextStyle(fontWeight: FontWeight.bold)),
                                    Text(_selectedProductRef ?? ''),
                                  ],
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Target', style: TextStyle(fontWeight: FontWeight.bold)),
                                    Text(_targetQuantity?.toString() ?? ''),
                                  ],
                                ),
                              ],
                            )
                          : Row(
                              children: [
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    value: _selectedProductRef,
                                    items: _productRefs
                                        .map((ref) => DropdownMenuItem(
                                              value: ref,
                                              child: Text(ref),
                                            ))
                                        .toList(),
                                    onChanged: (val) => setState(() => _selectedProductRef = val),
                                    decoration: const InputDecoration(labelText: 'Product Ref'),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: TextFormField(
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(labelText: 'Target'),
                                    onChanged: (val) => _targetQuantity = int.tryParse(val),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                ElevatedButton(
                                  onPressed: _setTarget,
                                  child: const Text('Set Target'),
                                ),
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Workshop Selector
                  DropdownButtonFormField<String>(
                    value: _selectedWorkshop,
                    items: _workshops
                        .map((w) => DropdownMenuItem(value: w, child: Text('Workshop $w')))
                        .toList(),
                    onChanged: (val) async {
                      setState(() => _selectedWorkshop = val);
                      await _fetchPerformanceForWorkshop(val!, DateFormat('yyyy-MM-dd').format(DateTime.now()));
                    },
                    decoration: const InputDecoration(labelText: 'Select Workshop'),
                  ),
                  const SizedBox(height: 16),
                  // Chains List
                  ..._chains.map((chain) {
                    final isExpanded = _expandedChains[chain] ?? false;
                    final chainData = _performanceData[chain] ?? [];
                    return Card(
                      color: const Color(0xFFE8F6F3),
                      child: Column(
                        children: [
                          ListTile(
                            leading: const Icon(Icons.link),
                            title: Text('Chaine $chain'),
                            trailing: IconButton(
                              icon: Icon(isExpanded ? Icons.expand_less : Icons.expand_more),
                              onPressed: () {
                                setState(() {
                                  _expandedChains[chain] = !isExpanded;
                                });
                              },
                            ),
                          ),
                          if (!isExpanded)
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                children: _hours.map((hour) {
                                  final entry = chainData.firstWhere(
                                    (e) => e['hour'] == hour,
                                    orElse: () => {},
                                  );
                                  final isLogged = entry.isNotEmpty;
                                  return Column(
                                    children: [
                                      Text(hour, style: const TextStyle(fontSize: 12)),
                                      Icon(
                                        isLogged ? Icons.check_circle : Icons.cancel,
                                        color: isLogged ? Colors.green : Colors.red,
                                        size: 20,
                                      ),
                                    ],
                                  );
                                }).toList(),
                              ),
                            ),
                          if (isExpanded)
                            Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Column(
                                children: _hours.map((hour) {
                                  final entry = chainData.firstWhere(
                                    (e) => e['hour'] == hour,
                                    orElse: () => {},
                                  );
                                  final producedController = TextEditingController(
                                    text: entry['produced']?.toString() ?? '',
                                  );
                                  final defectedController = TextEditingController(
                                    text: entry['defected']?.toString() ?? '',
                                  );
                                  final defectTypeController = TextEditingController(
                                    text: entry['defectType']?.toString() ?? '',
                                  );
                                  return Card(
                                    margin: const EdgeInsets.symmetric(vertical: 4),
                                    child: Padding(
                                      padding: const EdgeInsets.all(8.0),
                                      child: Row(
                                        children: [
                                          SizedBox(width: 60, child: Text(hour)),
                                          Expanded(
                                            child: TextFormField(
                                              controller: producedController,
                                              keyboardType: TextInputType.number,
                                              decoration: const InputDecoration(labelText: 'Produced'),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: TextFormField(
                                              controller: defectedController,
                                              keyboardType: TextInputType.number,
                                              decoration: const InputDecoration(labelText: 'Defected'),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: TextFormField(
                                              controller: defectTypeController,
                                              decoration: const InputDecoration(labelText: 'Defect Type'),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          IconButton(
                                            icon: const Icon(Icons.save, color: Color(0xFF6BBFB5)),
                                            onPressed: () async {
                                              final produced = int.tryParse(producedController.text) ?? 0;
                                              final defected = int.tryParse(defectedController.text) ?? 0;
                                              final defectType = defectTypeController.text;
                                              await _savePerformance(chain, hour, produced, defected, defectType);
                                            },
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
                  }).toList(),
                ],
              ),
            ),
      // AI Help Button (UI only)
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {},
        icon: const Icon(Icons.smart_toy),
        label: const Text('AI Help'),
        backgroundColor: const Color(0xFF6BBFB5),
      ),
    );
  }
}