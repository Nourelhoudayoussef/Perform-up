import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:logger/logger.dart';
import 'package:msal_auth/msal_auth.dart';

import 'package:http/http.dart' as http;
import 'package:syncfusion_flutter_charts/charts.dart';
import '../../widgets/floating_ai_bubble.dart';

final Logger _logger = Logger();

class TestScreen extends StatefulWidget {
  const TestScreen({Key? key}) : super(key: key);

  @override
  _TestScreenState createState() => _TestScreenState();
}

class _TestScreenState extends State<TestScreen> {
  SingleAccountPca? singleAccountPca;
  bool isLoading = false;
  bool isError = false;
  final String datasetId = "9861c7df-5e09-4ee8-b504-24cf01753687";
  final List<String> scopes = [
    'https://analysis.windows.net/powerbi/api/Dashboard.Read.All',
    'https://analysis.windows.net/powerbi/api/Workspace.Read.All',
    'https://analysis.windows.net/powerbi/api/Dataset.Read.All',
    'https://analysis.windows.net/powerbi/api/Report.Read.All',
  ];

  List<Map<String, dynamic>> rawData = [];

  List<Map<String, dynamic>> transformedData = [];

  // Summary values
  int? sumProductionTarget;
  int? sumDefects;
  int? sumProduced;

  // Data for treemap by orderRef
  List<Map<String, dynamic>> orderRefData = [];

  // Data for treemap by workshop
  List<Map<String, dynamic>> workshopData = [];

  // Add your brand color palette
  final Color brandBackground = const Color(0xFFF0F7F5);
  final Color brandPrimary = const Color(0xFF2A9D8F);
  final Color brandAccent = const Color(0xFFE9C46A);
  final Color brandError = const Color(0xFFE76F51);
  final Color cardShadow = Colors.black12;

  final List<IconData> summaryIcons = [
    Icons.flag, // production target
    Icons.error_outline, // defects
    Icons.check_circle_outline, // produced
  ];
  final List<Color> summaryColors = [
    Color(0xFF2A9D8F), // production target
    Color(0xFFE76F51), // defects
    Color(0xFF264653), // produced
  ];

  bool isChartRotated = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await fetchData();
      await fetchSummaryCards();
      await fetchOrderRefTreemapData();
      await fetchWorkshopTreemapData();
    });
  }

  Future<void> fetchData() async {
    try {
      setState(() {
        isLoading = true;
        isError = false;
      });
      
    await setupAUTH();
    rawData = await fetchChartData();
    final data = cleanData(rawData);
    transformedData = transformData(data);
      
      setState(() {
        isLoading = false;
      });
    } catch (e) {
      print('Error in fetchData: $e');
      setState(() {
        isLoading = false;
        isError = true;
      });
    }
  }

  Future<void> setupAUTH() async {
    // Create the instance first
    singleAccountPca = await SingleAccountPca.create(
      clientId: 'f418e576-700a-4fc0-b8ed-6204a8af5d0a',
      androidConfig: AndroidConfig(
        configFilePath: 'assets/msal_config.json',
        redirectUri:
            'msauth://com.example.pfe/Pzc/Pz9JRFg/Pz8/Z2s/dHo/Pz8NCg==',
      ),
      appleConfig: AppleConfig(
        authorityType: AuthorityType.aad,
        broker: Broker.safariBrowser,
      ),
    );

    // Now you can sign out
    //await singleAccountPca?.signOut();
    _logger.d('Signed out, now acquiring new token...');
    final authResult = await singleAccountPca?.acquireToken(
      scopes: scopes,
      prompt: Prompt.login,
      loginHint: "Ghezlen1@isima.u-monastir.tn",
    );
    debugPrint('Access token: ${authResult?.accessToken}');
    debugPrint('Id token: ${authResult?.idToken}');
    // List all tables in the dataset for debugging
    //await listTables(authResult?.accessToken ?? '');
/*   final report = await fetchPowerBIReport(
      authResult?.accessToken ?? '', 'c9e46705-d323-462a-90fd-fcee20570ae0');
  _logger.d('Report: ${report}');
  final datasetId = report?['datasetId'];
  if (datasetId == null) {
    _logger.d('❌ Could not find datasetId in report metadata');
    return;
  }
  final chartData =
      await fetchChartData(authResult?.accessToken ?? '', datasetId);
  _logger.d('Chart Data: $chartData'); */
  }

  Future<List<Map<String, dynamic>>> fetchChartData() async {
    final accessToken = (await singleAccountPca?.acquireTokenSilent(
      scopes: scopes,
    ))
        ?.accessToken;
    final url = Uri.parse(
        'https://api.powerbi.com/v1.0/myorg/groups/1fed0f5c-f003-4d7c-8cde-be7fefbf3e57/datasets/$datasetId/executeQueries');

    final body = jsonEncode({
      "queries": [
        {
          "query":
              "EVALUATE SUMMARIZECOLUMNS('performance3 (2)'[date], 'performance3 (2)'[hour], \"Sum of productionTarget\", SUM('performance3 (2)'[productionTarget]), \"Sum of produced\", SUM('performance3 (2)'[produced]), \"Sum of defects\", SUM('performance3 (2)'[defects])) ORDER BY 'performance3 (2)'[date], 'performance3 (2)'[hour]"
        }
      ]
    });

    try {
      isLoading = true;
      final res = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
        body: body,
      );

      if (res.statusCode == 200) {
        final result = jsonDecode(res.body);
        isLoading = false;
        return List<Map<String, dynamic>>.from(
            result['results'][0]['tables'][0]['rows']);
      } else {
        isLoading = false;
        isError = true;
        print('Error response: ${res.body}');
        throw Exception(
            "Failed to load Power BI data: ${res.statusCode} - ${res.body}");
      }
    } catch (e) {
      isLoading = false;
      isError = true;
      print('Exception while fetching chart data: $e');
      throw Exception("Failed to load Power BI data: $e");
    }
  }

  List<Map<String, dynamic>> cleanData(List<Map<String, dynamic>> rawData) {
    print('Cleaning raw data: ${rawData.length} rows');
    final cleaned = rawData.map((row) {
      return {
        'date': row["performance3 (2)[date]"],
        'hour': row["performance3 (2)[hour]"],
        'productionTarget': row["[Sum of productionTarget]"],
        'produced': row["[Sum of produced]"],
        'defects': row["[Sum of defects]"],
      };
    }).toList();
    print('Cleaned data: ${cleaned.length} rows');
    return cleaned;
  }

  List<Map<String, dynamic>> transformData(
      List<Map<String, dynamic>> cleanedData) {
    print('Transforming ${cleanedData.length} rows of cleaned data');
    final transformed = cleanedData.map((entry) {
      try {
      final date = DateTime.parse(entry['date']);
      final timeParts = (entry['hour'] as String).split(':');
      final hour = int.parse(timeParts[0]);

      return {
        'timestamp': DateTime(date.year, date.month, date.day, hour),
        'productionTarget': entry['productionTarget'],
        'produced': entry['produced'],
        'defects': entry['defects'],
      };
      } catch (e) {
        print('Error transforming row: $entry');
        print('Error details: $e');
        rethrow;
      }
    }).toList();
    print('Transformed data: ${transformed.length} rows');
    return transformed;
  }

  Future<void> fetchSummaryCards() async {
    await fetchSingleSummaryCard(
      "EVALUATE ROW(\"Sum of productionTarget\", SUM('performance3 (2)'[productionTarget]))",
      (value) => setState(() => sumProductionTarget = value),
    );
    await fetchSingleSummaryCard(
      "EVALUATE ROW(\"Sum of defects\", SUM('performance3 (2)'[defects]))",
      (value) => setState(() => sumDefects = value),
    );
    await fetchSingleSummaryCard(
      "EVALUATE ROW(\"Sum of produced\", SUM('performance3 (2)'[produced]))",
      (value) => setState(() => sumProduced = value),
    );
  }

  Future<void> fetchSingleSummaryCard(String query, void Function(int) setter) async {
    final accessToken = (await singleAccountPca?.acquireTokenSilent(
      scopes: scopes,
    ))?.accessToken;
    final url = Uri.parse(
        'https://api.powerbi.com/v1.0/myorg/groups/1fed0f5c-f003-4d7c-8cde-be7fefbf3e57/datasets/$datasetId/executeQueries');
    final body = jsonEncode({
      "queries": [
        {"query": query}
      ]
    });
    try {
      final res = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
        body: body,
      );
      if (res.statusCode == 200) {
        final result = jsonDecode(res.body);
        final row = result['results'][0]['tables'][0]['rows'][0];
        final value = row.values.first;
        setter((value as num?)?.toInt() ?? 0);
      } else {
        print('Error fetching summary card: ${res.body}');
      }
    } catch (e) {
      print('Exception fetching summary card: $e');
    }
  }

  Future<void> fetchOrderRefTreemapData() async {
    final accessToken = (await singleAccountPca?.acquireTokenSilent(
      scopes: scopes,
    ))?.accessToken;
    final url = Uri.parse(
        'https://api.powerbi.com/v1.0/myorg/groups/1fed0f5c-f003-4d7c-8cde-be7fefbf3e57/datasets/$datasetId/executeQueries');
    final body = jsonEncode({
      "queries": [
        {
          "query": "EVALUATE SUMMARIZECOLUMNS('performance3 (2)'[orderRef], \"Sum of productionTarget\", SUM('performance3 (2)'[productionTarget]), \"Sum of produced\", SUM('performance3 (2)'[produced]), \"Sum of defects\", SUM('performance3 (2)'[defects]))"
        }
      ]
    });
    try {
      final res = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
        body: body,
      );
      if (res.statusCode == 200) {
        final result = jsonDecode(res.body);
        setState(() {
          orderRefData = List<Map<String, dynamic>>.from(result['results'][0]['tables'][0]['rows']);
        });
      } else {
        print('Error fetching orderRef treemap: ${res.body}');
      }
    } catch (e) {
      print('Exception fetching orderRef treemap: $e');
    }
  }

  Future<void> fetchWorkshopTreemapData() async {
    final accessToken = (await singleAccountPca?.acquireTokenSilent(
      scopes: scopes,
    ))?.accessToken;
    final url = Uri.parse(
        'https://api.powerbi.com/v1.0/myorg/groups/1fed0f5c-f003-4d7c-8cde-be7fefbf3e57/datasets/$datasetId/executeQueries');
    final body = jsonEncode({
      "queries": [
        {
          "query": "EVALUATE SUMMARIZECOLUMNS('performance3 (2)'[workshop], \"Sum of productionTarget\", SUM('performance3 (2)'[productionTarget]), \"Sum of produced\", SUM('performance3 (2)'[produced]), \"Sum of defects\", SUM('performance3 (2)'[defects]))"
        }
      ]
    });
    try {
      final res = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
        body: body,
      );
      if (res.statusCode == 200) {
        final result = jsonDecode(res.body);
        setState(() {
          workshopData = List<Map<String, dynamic>>.from(result['results'][0]['tables'][0]['rows']);
        });
      } else {
        print('Error fetching workshop treemap: ${res.body}');
      }
    } catch (e) {
      print('Exception fetching workshop treemap: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: brandBackground,
      appBar: AppBar(
        backgroundColor: const Color(0xFFD0ECE8),
        elevation: 0,
        shadowColor: Colors.black.withOpacity(0.1),
        title: Text(('Overview'),style: GoogleFonts.poppins(
            fontSize: 20,
            fontWeight: FontWeight.w500,
            color: const Color(0xC5000000),
          ),),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            child: IconButton(
              icon: const Icon(
                Icons.refresh,
                color: Color(0xC5000000),
              ),
              tooltip: 'Refresh',
              onPressed: isLoading
                  ? null
                  : () async {
                      await fetchData();
                      await fetchSummaryCards();
                      await fetchOrderRefTreemapData();
                      await fetchWorkshopTreemapData();
                    },
            ),
          ),
          Container(
            margin: const EdgeInsets.only(right: 8),
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
          isLoading
              ? Center(child: _buildLoadingSkeleton())
              : isError
                  ? Center(child: _buildErrorCard())
                  : RefreshIndicator(
                      onRefresh: () async {
                        await fetchData();
                        await fetchSummaryCards();
                        await fetchOrderRefTreemapData();
                        await fetchWorkshopTreemapData();
                      },
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        child: Padding(
                          padding: const EdgeInsets.all(10.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Horizontally scrollable summary cards to prevent overflow
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: List.generate(3, (i) => Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 4),
                                    child: _animatedSummaryCard(
                                      label: i == 0 ? 'Target' : i == 1 ? 'Defects' : 'Produced',
                                      value: i == 0 ? sumProductionTarget : i == 1 ? sumDefects : sumProduced,
                                      icon: summaryIcons[i],
                                      color: summaryColors[i],
                                      height: 120,
                                      fontSize: 20,
                                      cardWidth: 110,
                                    ),
                                  )),
                                ),
                              ),
                              const SizedBox(height: 15),
                              // Main production chart (horizontal, large, animated)
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 600),
                                child: Center(
                                  key: ValueKey(transformedData.length),
                                  child: Builder(
                                    builder: (context) {
                                      final size = MediaQuery.of(context).size;
                                      final chartWidth = isChartRotated ? size.height * 0.95 : size.width * 0.98;
                                      final chartHeight = isChartRotated ? size.width * 0.98 : size.height * 0.62;
                                      return SizedBox(
                                        width: chartWidth,
                                        height: chartHeight,
                                        child: Stack(
                                          children: [
                                            Card(
                                              elevation: 4,
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(isChartRotated ? 0 : 18)),
                                              color: Colors.white,
                                              shadowColor: cardShadow,
                                              margin: isChartRotated ? EdgeInsets.zero : null,
                                              child: Padding(
                                                padding: EdgeInsets.all(isChartRotated ? 2.0 : 12.0),
                                                child: Transform.rotate(
                                                  angle: isChartRotated ? pi / 2 : 0,
                                                  child: SfCartesianChart(
                                                    zoomPanBehavior: ZoomPanBehavior(
                                                      enablePanning: true,
                                                      enableMouseWheelZooming: true,
                                                      zoomMode: ZoomMode.x,
                                                      enablePinching: true,
                                                    ),
                                                    primaryXAxis: DateTimeAxis(
                                                      intervalType: DateTimeIntervalType.days,
                                                      interval: 1,
                                                      edgeLabelPlacement: EdgeLabelPlacement.shift,
                                                      title: AxisTitle(text: 'Date & Hour'),
                                                    ),
                                                    primaryYAxis: NumericAxis(
                                                      title: AxisTitle(text: 'Quantity'),
                                                    ),
                                                    legend: const Legend(isVisible: true),
                                                    tooltipBehavior: TooltipBehavior(enable: true),
                                                    series: <CartesianSeries>[
                                                      LineSeries<Map<String, dynamic>, DateTime>(
                                                        name: 'Production Target',
                                                        color: brandPrimary,
                                                        dataSource: transformedData,
                                                        xValueMapper: (data, _) => data['timestamp'],
                                                        yValueMapper: (data, _) => data['productionTarget'],
                                                        markerSettings: const MarkerSettings(isVisible: true),
                                                        width: 3,
                                                      ),
                                                      LineSeries<Map<String, dynamic>, DateTime>(
                                                        name: 'Produced',
                                                        color: brandAccent,
                                                        dataSource: transformedData,
                                                        xValueMapper: (data, _) => data['timestamp'],
                                                        yValueMapper: (data, _) => data['produced'],
                                                        markerSettings: const MarkerSettings(isVisible: true),
                                                        width: 3,
                                                      ),
                                                      LineSeries<Map<String, dynamic>, DateTime>(
                                                        name: 'Defects',
                                                        color: brandError,
                                                        dataSource: transformedData,
                                                        xValueMapper: (data, _) => data['timestamp'],
                                                        yValueMapper: (data, _) => data['defects'],
                                                        markerSettings: const MarkerSettings(isVisible: true),
                                                        width: 3,
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ),
                                            Positioned(
                                              top: 3,
                                              right: 1,
                                              child: Material(
                                                color: Colors.transparent,
                                                child: IconButton(
                                                  icon: const Icon(Icons.screen_rotation, size: 28),
                                                  tooltip: 'Rotate Chart',
                                                  onPressed: () {
                                                    Navigator.of(context).push(
                                                      MaterialPageRoute(
                                                        builder: (_) => Scaffold(
                                                          backgroundColor: Colors.white,
                                                          body: SafeArea(
                                                            child: Stack(
                                                              children: [
                                                                Center(
                                                                  child: buildFullScreenRotatedChart(transformedData, brandPrimary, brandAccent, brandError),
                                                                ),
                                                                Positioned(
                                                                  top: 16,
                                                                  right: 16,
                                                                  child: IconButton(
                                                                    icon: const Icon(Icons.close, size: 32),
                                                                    onPressed: () => Navigator.of(context).pop(),
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                        ),
                                                      )
                                                    );
                                                  },
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              // Workshop treemap
                              _sectionHeader('By Workshop', Icons.factory, brandPrimary),
                              _animatedFadeIn(
                                child: SizedBox(
                                  height: 300,
                                  child: Card(
                                    elevation: 4,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                    child: Padding(
                                      padding: const EdgeInsets.all(16.0),
                                      child: SfCircularChart(
                                        legend: Legend(
                                          isVisible: true,
                                          position: LegendPosition.bottom,
                                          orientation: LegendItemOrientation.horizontal,
                                        ),
                                        tooltipBehavior: TooltipBehavior(
                                          enable: true,
                                          builder: (dynamic data, dynamic point, dynamic series,
                                              int pointIndex, int seriesIndex) {
                                            final workshop = data['performance3 (2)[workshop]'] ?? 'Unknown';
                                            final target = (data['[Sum of productionTarget]'] as num?) ?? 0;
                                            final produced = (data['[Sum of produced]'] as num?) ?? 0;
                                            final defects = (data['[Sum of defects]'] as num?) ?? 0;
                                            return Container(
                                              padding: const EdgeInsets.all(8),
                                              decoration: BoxDecoration(
                                                color: Colors.white,
                                                borderRadius: BorderRadius.circular(8),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: Colors.black.withOpacity(0.1),
                                                    blurRadius: 4,
                                                    offset: const Offset(0, 2),
                                                  ),
                                                ],
                                              ),
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    workshop,
                                                    style: const TextStyle(
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 14,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text('Target: ${_formatNumber(target.toInt())}'),
                                                  Text('Produced: ${_formatNumber(produced.toInt())}'),
                                                  Text('Defects: ${_formatNumber(defects.toInt())}'),
                                                ],
                                              ),
                                            );
                                          },
                                        ),
                                        series: <CircularSeries>[
                                          PieSeries<Map<String, dynamic>, String>(
                                            dataSource: workshopData,
                                            xValueMapper: (data, _) => data['performance3 (2)[workshop]'] ?? 'Unknown',
                                            yValueMapper: (data, _) => (data['[Sum of produced]'] as num?) ?? 0,
                                            dataLabelSettings: const DataLabelSettings(
                                              isVisible: true,
                                              labelPosition: ChartDataLabelPosition.outside,
                                              textStyle: TextStyle(fontSize: 12),
                                            ),
                                            enableTooltip: true,
                                            pointColorMapper: (data, _) {
                                              final index = workshopData.indexOf(data);
                                              return index % 3 == 0 ? brandPrimary : 
                                                     index % 3 == 1 ? brandAccent : 
                                                     brandError;
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              // OrderRef treemap
                              _sectionHeader('By Order Reference', Icons.list_alt, brandPrimary),
                              _animatedFadeIn(
                                child: _treemapGrid(
                                  data: orderRefData,
                                  labelKey: 'performance3 (2)[orderRef]',
                                  cardColor: Colors.white,
                                  icon: Icons.list_alt,
                                  textColor: Colors.black87,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
          FloatingAIBubble(
            onTap: () => Navigator.pushNamed(context, '/chatbot'),
          ),
        ],
      ),
    );
  }

  Widget _animatedSummaryCard({required String label, required int? value, required IconData icon, required Color color, double height = 110, double fontSize = 22, double cardWidth = 120}) {
    return Card(
      elevation: 4,
      shadowColor: cardShadow,
      color: color.withOpacity(0.12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: cardWidth,
        height: height,
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 500),
              transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
              child: Text(
                value != null ? _formatNumber(value) : '--',
                key: ValueKey(value),
                style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.bold, color: color),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: Colors.black87),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String title, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: color)),
        ],
      ),
    );
  }

  Widget _treemapGrid({required List<Map<String, dynamic>> data, required String labelKey, required Color cardColor, required IconData icon, Color textColor = Colors.black87}) {
    if (data.isEmpty) {
      return const Center(child: Text('No data'));
    }
    return SizedBox(
      height: 150,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemCount: data.length,
        itemBuilder: (context, idx) {
          final row = data[idx];
          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 500),
            child: Card(
              key: ValueKey(row[labelKey]),
              elevation: 2,
              color: cardColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(icon, color: brandPrimary, size: 18),
                        const SizedBox(width: 6),
                        Text(
                          '${row[labelKey] ?? "-"}',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: brandPrimary),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text('Target: ${_formatNumber((row["[Sum of productionTarget]"] ?? 0) as int)}', style: TextStyle(fontSize: 12, color: textColor)),
                    Text('Produced: ${_formatNumber((row["[Sum of produced]"] ?? 0) as int)}', style: TextStyle(fontSize: 12, color: textColor)),
                    Text('Defects: ${_formatNumber((row["[Sum of defects]"] ?? 0) as int)}', style: TextStyle(fontSize: 12, color: textColor)),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _animatedFadeIn({required Widget child}) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 600),
      child: child,
      transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: child),
    );
  }

  Widget _buildLoadingSkeleton() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(3, (i) => Container(
            margin: const EdgeInsets.symmetric(horizontal: 8),
            width: 120, height: 110,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(16),
            ),
          )),
        ),
        const SizedBox(height: 30),
        Container(
          width: 350, height: 220,
          decoration: BoxDecoration(
            color: Colors.grey[300],
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorCard() {
    return Card(
      color: brandError.withOpacity(0.1),
      margin: const EdgeInsets.all(32),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error, color: brandError, size: 40),
            const SizedBox(height: 12),
            const Text('Error loading data', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(backgroundColor: brandError),
              onPressed: () async {
                await fetchData();
                await fetchSummaryCards();
                await fetchOrderRefTreemapData();
                await fetchWorkshopTreemapData();
              },
            ),
          ],
        ),
      ),
    );
  }

  String _formatNumber(int value) {
    if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}M';
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(0)}K';
    return value.toString();
  }

  // Helper for full-screen chart axis
  Widget buildFullScreenRotatedChart(List<Map<String, dynamic>> transformedData, Color brandPrimary, Color brandAccent, Color brandError) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double chartWidth = constraints.maxHeight;
        final double chartHeight = constraints.maxWidth;
        return SizedBox(
          width: chartWidth,
          height: chartHeight,
          child: Transform.rotate(
            angle: pi / 2,
            child: SfCartesianChart(
              plotAreaBorderWidth: 0,
              zoomPanBehavior: ZoomPanBehavior(
                enablePanning: true,
                enableMouseWheelZooming: true,
                zoomMode: ZoomMode.x,
                enablePinching: true,
              ),
              primaryXAxis: DateTimeAxis(
                intervalType: DateTimeIntervalType.days,
                interval: 1,
                edgeLabelPlacement: EdgeLabelPlacement.none,
              ),
              primaryYAxis: NumericAxis(),
              legend: const Legend(isVisible: true),
              tooltipBehavior: TooltipBehavior(enable: true),
              series: <CartesianSeries>[
                LineSeries<Map<String, dynamic>, DateTime>(
                  name: 'Production Target',
                  color: brandPrimary,
                  dataSource: transformedData,
                  xValueMapper: (data, _) => data['timestamp'],
                  yValueMapper: (data, _) => data['productionTarget'],
                  markerSettings: const MarkerSettings(isVisible: true),
                  width: 3,
                ),
                LineSeries<Map<String, dynamic>, DateTime>(
                  name: 'Produced',
                  color: brandAccent,
                  dataSource: transformedData,
                  xValueMapper: (data, _) => data['timestamp'],
                  yValueMapper: (data, _) => data['produced'],
                  markerSettings: const MarkerSettings(isVisible: true),
                  width: 3,
                ),
                LineSeries<Map<String, dynamic>, DateTime>(
                  name: 'Defects',
                  color: brandError,
                  dataSource: transformedData,
                  xValueMapper: (data, _) => data['timestamp'],
                  yValueMapper: (data, _) => data['defects'],
                  markerSettings: const MarkerSettings(isVisible: true),
                  width: 3,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

Future<List<Map<String, dynamic>>> fetchChartData(
    String accessToken, String datasetId) async {
  final url = Uri.parse(
      'https://api.powerbi.com/v1.0/myorg/groups/1fed0f5c-f003-4d7c-8cde-be7fefbf3e57/datasets/$datasetId/executeQueries');

  final body = jsonEncode({
    "queries": [
      {
        "query":
            "EVALUATE SUMMARIZECOLUMNS('performance3 (2)'[date], 'performance3 (2)'[hour], \"Sum of productionTarget\", SUM('performance3 (2)'[productionTarget]), \"Sum of produced\", SUM('performance3 (2)'[produced]), \"Sum of defects\", SUM('performance3 (2)'[defects])) ORDER BY 'performance3 (2)'[date], 'performance3 (2)'[hour]"
      }
    ]
  });

  try {
    final res = await http.post(
      url,
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
      },
      body: body,
    );

    if (res.statusCode == 200) {
      final result = jsonDecode(res.body);
      return List<Map<String, dynamic>>.from(
          result['results'][0]['tables'][0]['rows']);
    } else {
      print('Error response: ${res.body}');
      throw Exception(
          "Failed to load Power BI data: ${res.statusCode} - ${res.body}");
    }
  } catch (e) {
    print('Exception while fetching chart data: $e');
    throw Exception("Failed to load Power BI data: $e");
  }
}

Future<void> listTables(String accessToken) async {
  final url = Uri.parse(
      'https://api.powerbi.com/v1.0/myorg/datasets/9861c7df-5e09-4ee8-b504-24cf01753687/tables');
  final res = await http.get(
    url,
    headers: {
      'Authorization': 'Bearer $accessToken',
      'Content-Type': 'application/json',
    },
  );
  print('Tables response: \n${res.body}');
}

// Add this extension for color darkening
extension ColorBrightness on Color {
  Color darken([double amount = .1]) {
    assert(amount >= 0 && amount <= 1);
    final hsl = HSLColor.fromColor(this);
    final hslDark = hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0));
    return hslDark.toColor();
  }
}
