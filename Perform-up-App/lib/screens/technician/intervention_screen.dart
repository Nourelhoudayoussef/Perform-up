import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

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
  
  // Mock data - Replace with API data later
  int totalTasks = 3;
  int avgTime = 65;
  int machinesChecked = 2;
  
  List<Map<String, dynamic>> recentInterventions = [
    {
      'reference': 'W2-C3-M01',
      'timeTaken': 20,
      'description': 'Machine won\'t start, Inspected motor.',
    },
    {
      'reference': 'W2-C3-M01',
      'timeTaken': 15,
      'description': 'Motor Overheating, Oil the machine.',
    },
    {
      'reference': 'W2-C3-M01',
      'timeTaken': 30,
      'description': 'Timing Off, May need parts replacement.',
    },
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  // TODO: Implement API integration
  Future<void> _loadData() async {
    // API Integration Point:
    // 1. Fetch technician's statistics (total tasks, avg time, machines checked)
    // 2. Fetch recent interventions
    // Example API endpoints:
    // - GET /api/technician/statistics
    // - GET /api/technician/interventions
    
    setState(() {
      _isLoading = false;
    });
  }

  // TODO: Implement API integration
  Future<void> _submitIntervention() async {
    if (_machineRefController.text.isEmpty ||
        _timeTakenController.text.isEmpty ||
        _descriptionController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all fields')),
      );
      return;
    }

    // API Integration Point:
    // POST /api/technician/interventions
    // Request body should include:
    // - machineReference
    // - timeTaken
    // - description
    // - technicianId (from authentication)

    // Mock success - Replace with actual API call
    setState(() {
      recentInterventions.insert(0, {
        'reference': _machineRefController.text,
        'timeTaken': int.parse(_timeTakenController.text),
        'description': _descriptionController.text,
      });
      _isAddingIntervention = false;
      totalTasks++;
    });

    // Clear form
    _machineRefController.clear();
    _timeTakenController.clear();
    _descriptionController.clear();
  }

  Widget _buildStatCard(IconData icon, String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
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
            children: [
              Icon(icon, size: 16, color: const Color(0xFF6BBFB5)),
              const SizedBox(width: 8),
              Text(
                value,
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 12,
              color: Colors.black54,
            ),
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
                      _buildStatCard(
                        FontAwesomeIcons.tasks,
                        '$totalTasks Tasks',
                        'done',
                      ),
                      _buildStatCard(
                        FontAwesomeIcons.clock,
                        '$avgTime min',
                        'Avg time',
                      ),
                      _buildStatCard(
                        FontAwesomeIcons.wrench,
                        '$machinesChecked Machines',
                        'Checked',
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
                                children: [
                                  Text(
                                    intervention['reference'],
                                    style: GoogleFonts.poppins(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  Text(
                                    '${intervention['timeTaken']} min',
                                    style: GoogleFonts.poppins(
                                      fontSize: 14,
                                      color: Colors.black54,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                intervention['description'],
                                style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  color: Colors.black87,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )),
                ],
              ),
            ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        selectedItemColor: const Color(0xFF6BBFB5),
        unselectedItemColor: const Color(0xA6000000),
        backgroundColor: const Color(0xFFF0F7F5),
        type: BottomNavigationBarType.fixed,
        elevation: 5,
        showSelectedLabels: false,
        showUnselectedLabels: false,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
          switch (index) {
            case 0:
              // File icon - No action needed
              break;
            case 1:
              // Chat icon - Navigate to chat list
              Navigator.pushNamed(context, '/chats');
              break;
            case 2:
              // Home icon - Already on home screen
              break;
            case 3:
              // Profile icon - Navigate to profile
              Navigator.pushNamed(context, '/profile');
              break;
          }
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(FontAwesomeIcons.solidFileLines, size: 24),
            label: "",
          ),
          BottomNavigationBarItem(
            icon: Icon(FontAwesomeIcons.solidCommentDots, size: 24),
            label: "",
          ),
          BottomNavigationBarItem(
            icon: Icon(FontAwesomeIcons.home, size: 24),
            label: "",
          ),
          BottomNavigationBarItem(
            icon: Icon(FontAwesomeIcons.userAlt, size: 24),
            label: "",
          ),
        ],
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
} 