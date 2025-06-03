import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ReportingScreen extends StatefulWidget {
  const ReportingScreen({super.key});

  @override
  State<ReportingScreen> createState() => _ReportingScreenState();
}

class _ReportingScreenState extends State<ReportingScreen> {
  DateTime? _selectedDate;
  bool _isLoading = false;
  String? _reportFilePath;
  String? _error;

  Future<void> _generateReport() async {
    if (_selectedDate == null) return;
    setState(() {
      _isLoading = true;
      _error = null;
      _reportFilePath = null;
    });
    final formattedDate = DateFormat('yyyy-MM-dd').format(_selectedDate!);

    final url = Uri.parse('http://10.0.2.2:8080/api/reports/daily?date=$formattedDate');
   
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      final response = await http.get(
        url,
        headers: {
          if (token != null) 'Authorization': 'Bearer $token',
        },
      );
      if (response.statusCode == 200) {
        // Save PDF to device
        final dir = await getApplicationDocumentsDirectory();
        final filePath = '${dir.path}/$formattedDate.pdf';
        final file = File(filePath);
        await file.writeAsBytes(response.bodyBytes);
        setState(() {
          _reportFilePath = filePath;
        });
      } else {
        setState(() {
          _error = 'Failed to generate report. (${response.statusCode})';
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Error: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Widget _buildDateSelector() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        DropdownButton<int>(
          hint: const Text('Year'),
          value: _selectedDate?.year,
          items: List.generate(5, (i) {
            final year = DateTime.now().year - 2 + i;
            return DropdownMenuItem(value: year, child: Text(year.toString()));
          }),
          onChanged: (year) {
            if (year == null) return;
            setState(() {
              _selectedDate = DateTime(year, _selectedDate?.month ?? 1, _selectedDate?.day ?? 1);
            });
          },
        ),
        const SizedBox(width: 8),
        DropdownButton<int>(
          hint: const Text('Month'),
          value: _selectedDate?.month,
          items: List.generate(12, (i) {
            final month = i + 1;
            return DropdownMenuItem(value: month, child: Text(month.toString().padLeft(2, '0')));
          }),
          onChanged: (month) {
            if (month == null) return;
            setState(() {
              _selectedDate = DateTime(_selectedDate?.year ?? DateTime.now().year, month, _selectedDate?.day ?? 1);
            });
          },
        ),
        const SizedBox(width: 8),
        DropdownButton<int>(
          hint: const Text('Day'),
          value: _selectedDate?.day,
          items: List.generate(31, (i) {
            final day = i + 1;
            return DropdownMenuItem(value: day, child: Text(day.toString().padLeft(2, '0')));
          }),
          onChanged: (day) {
            if (day == null) return;
            setState(() {
              _selectedDate = DateTime(_selectedDate?.year ?? DateTime.now().year, _selectedDate?.month ?? 1, day);
            });
          },
        ),
      ],
    );
  }

  Widget _buildReportCard() {
    if (_reportFilePath == null) return const SizedBox.shrink();
    final fileName = _reportFilePath!.split(Platform.pathSeparator).last;
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      color: const Color(0xFFF2F2F2),
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 0),
      child: ListTile(
        leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
        title: Text(fileName, style: const TextStyle(fontWeight: FontWeight.w500)),
        subtitle: const Text('Click Here to Download Your Report'),
        onTap: () => OpenFile.open(_reportFilePath!),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Reports',style: GoogleFonts.poppins(
            fontSize: 20,
            fontWeight: FontWeight.w500,
            color: const Color(0xC5000000),
          ),),
        backgroundColor: const Color(0xFFD0ECE8),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            child: IconButton(
              icon: const Icon(
                FontAwesomeIcons.solidBell,
                color: Color(0xC5000000),
              ),
              onPressed: () {},
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Generate Report', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
              const SizedBox(height: 4),
              const Text('Generate Report for the following Date', style: TextStyle(color: Colors.black54, fontSize: 15)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F6F3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    _buildDateSelector(),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isLoading || _selectedDate == null ? null : _generateReport,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6BBFB5),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: _isLoading
                            ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white, ))
                            : const Text('Generate', style: TextStyle(fontSize: 17, color: Colors.white)),
                      ),
                    ),
                  ],
                ),
              ),
              
                const SizedBox(height: 32),
                const Text('Download Report', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F6F3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Click Here to Download Your Report', style: TextStyle(color: Colors.black54, fontSize: 15)),
                      _buildReportCard(),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(_error!, style: const TextStyle(color: Colors.red)),
                        ),
                    ],
                  ),
                ),
              
            ],
          ),
        ),
      ),
    );
  }
}