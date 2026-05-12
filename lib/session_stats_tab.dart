import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../services/session_service.dart';

class SessionStatsTab extends StatefulWidget {
  const SessionStatsTab({super.key});

  @override
  State<SessionStatsTab> createState() => _SessionStatsTabState();
}

class _SessionStatsTabState extends State<SessionStatsTab> {
  late Future<List<Map<String, dynamic>>> _sessionData;
  DateTime startDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime endDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _refreshData();
  }

  void _refreshData() {
    setState(() {
      _sessionData = SessionService.fetchSessionsPerDay(
        startDate.toIso8601String().split('T').first,
        endDate.toIso8601String().split('T').first,
      );
    });
  }

  Future<void> _selectDate(BuildContext context, bool isStartDate) async {
    FocusScope.of(context).unfocus(); // Fix for focus error
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: isStartDate ? startDate : endDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        if (isStartDate) {
          startDate = picked;
        } else {
          endDate = picked;
        }
        _refreshData();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => _selectDate(context, true),
                  child: Text(
                    'Start Date: ${DateFormat('yyyy-MM-dd').format(startDate)}',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextButton(
                  onPressed: () => _selectDate(context, false),
                  child: Text(
                    'End Date: ${DateFormat('yyyy-MM-dd').format(endDate)}',
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _sessionData,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              } else if (snapshot.hasError) {
                return Center(
                  child: SelectableText(
                    'Error: Unable to fetch data.\nDetails: ${snapshot.error}',
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                );
              } else if (snapshot.hasData) {
                final sessions = snapshot.data!;
                if (sessions.isEmpty) {
                  return const Center(child: Text('No sessions found.'));
                }

                final List<FlSpot> spots =
                    sessions.asMap().entries.map((entry) {
                  final index = entry.key;
                  final session = entry.value;
                  return FlSpot(
                    index.toDouble(),
                    double.tryParse(session['session_count'].toString()) ?? 0.0,
                  );
                }).toList();

                return LineChart(
                  LineChartData(
                    lineBarsData: [
                      LineChartBarData(
                        spots: spots,
                        isCurved: true,
                        color: Colors.blue,
                        dotData: const FlDotData(show: true),
                      ),
                    ],
                  ),
                );
              } else {
                return const Center(child: Text('No data available.'));
              }
            },
          ),
        ),
      ],
    );
  }
}
