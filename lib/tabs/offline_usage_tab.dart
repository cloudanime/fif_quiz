import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../services/session_service.dart';

class OfflineUsageTab extends StatefulWidget {
  const OfflineUsageTab({super.key});

  @override
  State<OfflineUsageTab> createState() => _OfflineUsageTabState();
}

class _OfflineUsageTabState extends State<OfflineUsageTab> {
  DateTime startDate = DateTime.now().subtract(const Duration(days: 7));
  DateTime endDate = DateTime.now();
  String _filterType = 'All'; 
  late Future<List<Map<String, dynamic>>> _syncStats;

  @override
  void initState() {
    super.initState();
    _refreshData();
  }

  void _refreshData() {
    final startStr = startDate.toIso8601String().split('T').first;
    final endStr = endDate.toIso8601String().split('T').first;
    setState(() {
      _syncStats = SessionService.fetchOfflineSyncLogs(startStr, endStr);
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _syncStats,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        
        final data = snapshot.data ?? [];
        
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildFilters(),
              const SizedBox(height: 20),
              _buildGraphCard(data),
              const SizedBox(height: 20),
              _buildSummaryCards(data),
              const SizedBox(height: 20),
              _buildDetailsTable(data),
              const SizedBox(height: 80),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFilters() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _selectDate(true),
                    icon: const Icon(Icons.calendar_today, size: 16),
                    label: Text('From: ${DateFormat('MMM dd').format(startDate)}'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _selectDate(false),
                    icon: const Icon(Icons.calendar_today, size: 16),
                    label: Text('To: ${DateFormat('MMM dd').format(endDate)}'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGraphCard(List<Map<String, dynamic>> data) {
    if (data.isEmpty) return const Card(child: Padding(padding: EdgeInsets.all(20), child: Text('No download data for this period.')));

    final List<FlSpot> spots = [];
    final List<String> labels = [];
    double maxVal = 0;

    for (int i = 0; i < data.length; i++) {
      final val = double.tryParse(data[i]['downloads'].toString()) ?? 0;
      if (val > maxVal) maxVal = val;
      spots.add(FlSpot(i.toDouble(), val));
      labels.add(DateFormat('dd/MM').format(DateTime.parse(data[i]['date'])));
    }

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Offline Download Activity', 
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Text('Number of questions synced for offline use', style: TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 24),
            SizedBox(
              height: 250,
              child: LineChart(
                LineChartData(
                  gridData: const FlGridData(show: true, drawVerticalLine: false),
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (val, meta) {
                          int index = val.toInt();
                          if (index >= 0 && index < labels.length && (data.length < 10 || index % (data.length / 5).ceil() == 0)) {
                            return Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Text(labels[index], style: const TextStyle(fontSize: 10)),
                            );
                          }
                          return const SizedBox.shrink();
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        getTitlesWidget: (val, meta) => Text(val.toInt().toString(), style: const TextStyle(fontSize: 10)),
                      ),
                    ),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      color: Colors.green.shade700,
                      barWidth: 4,
                      isStrokeCapRound: true,
                      dotData: const FlDotData(show: true),
                      belowBarData: BarAreaData(
                        show: true,
                        color: Colors.green.withOpacity(0.1),
                      ),
                    ),
                  ],
                  minY: 0,
                  maxY: (maxVal * 1.2).ceilToDouble().clamp(5.0, 1000000.0),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCards(List<Map<String, dynamic>> data) {
    int total = 0;
    for (var d in data) {
      total += int.tryParse(d['downloads'].toString()) ?? 0;
    }

    return Row(
      children: [
        _buildStatCard('Total Questions Synced', total.toString(), Icons.download_done, Colors.blue),
        const SizedBox(width: 12),
        _buildStatCard('Sync Events', data.length.toString(), Icons.sync, Colors.orange),
      ],
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color),
              const SizedBox(height: 8),
              Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              Text(title, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailsTable(List<Map<String, dynamic>> data) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text('Daily Sync Summary', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          DataTable(
            columns: const [
              DataColumn(label: Text('Date')),
              DataColumn(label: Text('Questions Synced')),
            ],
            rows: data.reversed.map((e) => DataRow(cells: [
              DataCell(Text(e['date'])),
              DataCell(Text(e['downloads'].toString())),
            ])).toList(),
          ),
        ],
      ),
    );
  }

  Future<void> _selectDate(bool isStart) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? startDate : endDate,
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        if (isStart) startDate = picked; else endDate = picked;
        _refreshData();
      });
    }
  }
}
