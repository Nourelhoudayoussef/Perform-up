import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../../services/supervisor_service.dart';

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
  bool _targetSet = false;

  // State for workshop and chains
  String? _selectedWorkshop = '1';
  Map<String, bool> _expandedChains = {'1': false, '2': false, '3': false};
  
  // Static map to persist performance data across navigation
  static Map<String, Map<String, Map<String, dynamic>>> _persistentPerformanceData = {};
  Map<String, Map<String, Map<String, dynamic>>> _performanceData = {};

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
    // Initialize performance data structure if not already initialized
    if (_persistentPerformanceData.isEmpty) {
      for (var chain in _chains) {
        _persistentPerformanceData[chain] = {};
        for (var hour in _hours) {
          _persistentPerformanceData[chain]![hour] = {
            'produced': '',
            'defected': '',
            'defectType': '',
          };
        }
      }
    }
    // Use the persistent data
    _performanceData = Map.from(_persistentPerformanceData);
  }

  void _setDailyTarget() async {
    if (_selectedProductRef == null || _targetQuantity == null) return;
    setState(() => _isLoading = true);
    try {
      await _supervisorService.setDailyTarget(
        int.parse(_selectedProductRef!),
        _targetQuantity!,
      );
      setState(() {
        _targetSet = true;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error setting target: $e')),
      );
    }
    setState(() => _isLoading = false);
  }

  void _savePerformance(String chain, String hour) async {
    setState(() => _isLoading = true);
    try {
      final entry = _performanceData[chain]![hour]!;
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
      _persistentPerformanceData[chain]![hour] = Map.from(entry);
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

  Widget _buildTargetSection() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
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
                      hint: const Text('Product Ref'),
                      isExpanded: true,
                      underline: const SizedBox(),
                      items: _productRefs.map((ref) => DropdownMenuItem(value: ref, child: Text(ref))).toList(),
                      onChanged: _targetSet ? null : (val) => setState(() => _selectedProductRef = val),
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
                  _targetSet
                    ? Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0F7F5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _targetQuantity?.toString() ?? '',
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                    : Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0F7F5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: TextField(
                          enabled: !_targetSet,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            hintText: 'Quantity',
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          ),
                          onChanged: (val) => _targetQuantity = int.tryParse(val),
                        ),
                      ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            ElevatedButton(
              onPressed: _targetSet || _isLoading ? null : _setDailyTarget,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6BBFB5),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                minimumSize: const Size(0, 40),
              ),
              child: const Text('Set Target', style: TextStyle(color: Colors.white) ),
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
                  final entry = _performanceData[chain]![hour]!;
                  final isLogged = entry['produced'].toString().isNotEmpty && entry['defected'].toString().isNotEmpty;
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
                  final entry = _performanceData[chain]![hour]!;
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
                                    hintStyle: GoogleFonts.poppins(
                                      fontSize: 15,
                                      color: Colors.black38,
                                    ),
                                  ),
                                  onChanged: (val) => _performanceData[chain]![hour]!['produced'] = val,
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
                                    hintStyle: GoogleFonts.poppins(
                                      fontSize: 15,
                                      color: Colors.black38,
                                    ),
                                  ),
                                  onChanged: (val) => _performanceData[chain]![hour]!['defected'] = val,
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
                                    labelText: 'Defect Type',
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
                                    hintStyle: GoogleFonts.poppins(
                                      fontSize: 15,
                                      color: Colors.black38,
                                    ),
                                  ),
                                  onChanged: (val) => _performanceData[chain]![hour]!['defectType'] = val,
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
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.5),
              borderRadius: BorderRadius.circular(12),
            ),
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
      body: _isLoading
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.pushNamed(context, '/chatbot'),
        icon: const Icon(Icons.smart_toy),
        label: const Text('AI Help'),
        backgroundColor: const Color(0xFF6BBFB5),
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
} 