import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../intervention_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class InterventionScreen extends StatefulWidget {
  const InterventionScreen({super.key});

  @override
  _InterventionScreenState createState() => _InterventionScreenState();
}

class _InterventionScreenState extends State<InterventionScreen> {
  // Form controllers
  final _machineRefController = TextEditingController();
  final _timeTakenController = TextEditingController();
  final _descriptionController = TextEditingController();
  
  // State variables
  bool _isAddingIntervention = false;
  bool _isLoading = true;
  int _currentIndex = 2; // Set to 2 for home icon
  
  // Service instance
  final _interventionService = InterventionService();
  
  // Statistics
  int totalTasks = 0;
  int avgTime = 0;
  int machinesChecked = 0;
  
  List<Map<String, dynamic>> recentInterventions = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      setState(() => _isLoading = true);
      
      // Load recent interventions first
      final interventions = await _interventionService.getRecentInterventions();
      
      // Calculate statistics from interventions
      final uniqueMachines = interventions.map((e) => e['machineReference']).toSet();
      final totalTime = interventions.fold<int>(0, (sum, item) => sum + (item['timeTaken'] as int));
      final averageTime = interventions.isEmpty ? 0 : (totalTime / interventions.length).round();
      
      if (mounted) {
        setState(() {
          totalTasks = interventions.length;
          avgTime = averageTime;
          machinesChecked = uniqueMachines.length;
          recentInterventions = interventions;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading data: $e')),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _submitIntervention() async {
    // Trim whitespace from inputs
    final machineRef = _machineRefController.text.trim();
    final timeTaken = _timeTakenController.text.trim();
    final description = _descriptionController.text.trim();

    // Validate inputs
    if (machineRef.isEmpty || timeTaken.isEmpty || description.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all fields')),
      );
      return;
    }

    // Validate machine reference format (should be like W1-C2-M3)
    final machineRefRegex = RegExp(r'^W\d+-C\d+-M\d+$');
    if (!machineRefRegex.hasMatch(machineRef)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Machine reference should be in format: W1-C2-M3'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Validate time taken is a positive number
    int? parsedTime;
    try {
      parsedTime = int.parse(timeTaken);
      if (parsedTime <= 0) throw FormatException('Time must be positive');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Time taken must be a positive number'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      setState(() => _isLoading = true);
      
      // Create new intervention with sanitized inputs
      final newIntervention = await _interventionService.createIntervention(
        machineReference: machineRef,
        timeTaken: parsedTime,
        description: description,
      );

      // Reload data to get updated statistics and interventions
      await _loadData();

      if (mounted) {
        setState(() => _isAddingIntervention = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Intervention added successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }

      // Clear form
      _machineRefController.clear();
      _timeTakenController.clear();
      _descriptionController.clear();
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error submitting intervention: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildStatCard(IconData icon, String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: const Color(0xFF6BBFB5)),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  value,
                  style: GoogleFonts.poppins(
                    fontSize: 23,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 12,
              color: Colors.black,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildInterventionForm() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Machine reference',
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _machineRefController,
            decoration: InputDecoration(
              hintText: 'Enter Machine Ref like Wx-Cx-Mx',
              filled: true,
              fillColor: const Color(0xFFF1F1F1),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Time Taken',
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _timeTakenController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              hintText: 'Enter time taken in minutes',
              filled: true,
              fillColor: const Color(0xFFF1F1F1),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Description',
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _descriptionController,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'What issue did you face? how did you solve it?',
              filled: true,
              fillColor: const Color(0xFFF1F1F1),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _submitIntervention,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6BBFB5),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              'Save',
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Debug code to check role
    SharedPreferences.getInstance().then((prefs) {
      final role = prefs.getString('role');
      print('DEBUG - Current role in intervention_screen: $role');
      print('DEBUG - All stored preferences:');
      print('token: ${prefs.getString('token') != null ? 'exists' : 'missing'}');
      print('email: ${prefs.getString('email')}');
      print('role: ${prefs.getString('role')}');
      print('userId: ${prefs.getString('userId')}');
      print('username: ${prefs.getString('username')}');
    });

    return Scaffold(
      backgroundColor: const Color(0xFFF0F7F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFFD0ECE8),
        elevation: 4,
        shadowColor: Colors.black.withOpacity(0.25),
        title: Text(
          'Machine Interventions',
          style: GoogleFonts.poppins(
            fontSize: 24,
            fontWeight: FontWeight.w500,
            color: const Color(0xC5000000),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(FontAwesomeIcons.solidBell, color: Color(0xC5000000)),
            onPressed: () => Navigator.pushNamed(context, '/notifications'),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Expanded(
                        flex: 1,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: _buildStatCard(
                            FontAwesomeIcons.tasks,
                            '$totalTasks',
                            'Tasks done',
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 1,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: _buildStatCard(
                            FontAwesomeIcons.clock,
                            '$avgTime',
                            'Avg min',
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 1,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: _buildStatCard(
                            FontAwesomeIcons.wrench,
                            '$machinesChecked',
                            'Machines',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  if (!_isAddingIntervention)
                    ElevatedButton(
                      onPressed: () => setState(() => _isAddingIntervention = true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6BBFB5),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        '+ New Machine Intervention',
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  if (_isAddingIntervention) ...[
                    const SizedBox(height: 16),
                    _buildInterventionForm(),
                  ],
                  const SizedBox(height: 24),
                  Text(
                    'Recent interventions',
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ...recentInterventions.map((intervention) => Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          intervention['machineReference'] ?? '',
                                          style: GoogleFonts.poppins(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          intervention['description'] ?? '',
                                          style: GoogleFonts.poppins(
                                            fontSize: 14,
                                            color: Colors.black87,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${intervention['timeTaken'] ?? 0} min',
                                    style: GoogleFonts.poppins(
                                      fontSize: 14,
                                      color: Colors.black54,
                                    ),
                                  ),
                                ],
                              ),
                              if (intervention['date'] != null) ...[
                                const SizedBox(height: 8),
                                Text(
                                  _formatDate(intervention['date']),
                                  style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    color: Colors.black54,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      )),
                ],
              ),
            ),
      
    );
  }

  @override
  void dispose() {
    _machineRefController.dispose();
    _timeTakenController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  // Add this method to format the date
  String _formatDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
    } catch (e) {
      return dateStr;
    }
  }
} 