import 'tabs/super_user_tab.dart';
import 'tabs/offline_usage_tab.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart'; // For Line Chart
import 'package:intl/intl.dart'; // For date formatting
import '../services/session_service.dart'; // Backend service for session data
import 'services/user_service.dart';
import 'tabs/all_mcq_tab.dart'; // Tab for MCQs
import 'tabs/all_picture_tab.dart' as allPicture; // Tab for Picture questions
import 'tabs/all_structured_tab.dart'; // Tab for Structured questions
import 'tabs/users_tab.dart';
import 'package:url_launcher/url_launcher.dart';

// ✅ Remove dart:html import, fixing the issue
// Detects platform for back button behavior

class AdminPanelPage extends StatefulWidget {
  const AdminPanelPage({super.key});

  @override
  _AdminPanelPageState createState() => _AdminPanelPageState();
}

class _AdminPanelPageState extends State<AdminPanelPage>
    with SingleTickerProviderStateMixin {
  bool isSuperAdmin = false;

  @override
  void initState() {
    super.initState();
    _checkSuperAdmin();
  }

  Future<void> _checkSuperAdmin() async {
    final superStatus = await UserService.isSuperAdmin();
    if (mounted) {
      setState(() {
        isSuperAdmin = superStatus;
      });
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  /// 🔹 Handles Back Navigation
  void _handleBack() {
    if (Navigator.canPop(context)) {
      Navigator.pop(context); // Goes back if possible
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: UserService.isSuperAdmin(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        
        final superStatus = snapshot.data == true;
        final tabCount = superStatus ? 7 : 3;

        return DefaultTabController(
          length: tabCount,
          child: Scaffold(
            appBar: AppBar(
              leading: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: _handleBack,
              ),
              title: Text(
                'Admin Panel',
                style: TextStyle(
                  fontSize: (MediaQuery.of(context).size.height * 0.02).clamp(14.0, 22.0),
                  fontWeight: FontWeight.bold,
                ),
              ),
              bottom: TabBar(
                labelColor: Colors.yellow,
                unselectedLabelColor: Colors.white70,
                indicatorColor: Colors.yellow,
                isScrollable: true,
                tabs: [
                  const Tab(text: 'MCQ'),
                  const Tab(text: 'Picture'),
                  const Tab(text: 'Structured'),
                  if (superStatus) const Tab(text: 'Statistics'),
                  if (superStatus) const Tab(text: 'Downloads'),
                  if (superStatus) const Tab(text: 'Users'),
                  if (superStatus) const Tab(text: 'Super User'),
                ],
              ),
            ),
            body: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: TabBarView(
                  children: [
                    const AllMCQTab(),
                    const allPicture.AllPictureTab(),
                    const AllStructuredTab(),
                    if (superStatus) const SessionStatsTab(),
                    if (superStatus) const OfflineUsageTab(),
                    if (superStatus) const UsersManagementTab(),
                    if (superStatus) const SuperUserTab(),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class SessionStatsTab extends StatefulWidget {
  const SessionStatsTab({super.key});

  @override
  State<SessionStatsTab> createState() => _SessionStatsTabState();
}

class _SessionStatsTabState extends State<SessionStatsTab> {
  late Future<List<Map<String, dynamic>>> _statsData;
  DateTime startDate = DateTime.now().subtract(const Duration(days: 7));
  DateTime endDate = DateTime.now();
  int _minGamesFilter = 1;
  String _statType = 'Sessions'; // 'Sessions' or 'Users Joined'
  String _viewType = 'General'; // 'General' or 'Insights'
  String _searchQuery = '';
  final Set<String> _hiddenUsers = {}; // Track toggled-off users in trends

  @override
  void initState() {
    super.initState();
    _refreshData();
  }

  /// Refreshes data from backend
  void _refreshData() {
    final startStr = startDate.toIso8601String().split('T').first;
    final endStr = endDate.toIso8601String().split('T').first;

    setState(() {
      if (_statType == 'Sessions') {
        _statsData = SessionService.fetchSessionsPerDay(startStr, endStr);
      } else {
        _statsData = UserService.fetchUsersJoinedPerDay(startStr, endStr);
      }
    });
  }

  /// Opens date picker
  Future<void> _selectDate(BuildContext context, bool isStartDate) async {
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
        // Top Selection Area
        Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          color: Colors.white,
          child: Column(
            children: [
              // Main View Switcher
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'General', label: Text('General Stats'), icon: Icon(Icons.show_chart)),
                  ButtonSegment(value: 'Insights', label: Text('Advanced Insights'), icon: Icon(Icons.insights)),
                  ButtonSegment(value: 'Reports', label: Text('Detailed Reports'), icon: Icon(Icons.analytics)),
                ],
                selected: {_viewType},
                onSelectionChanged: (set) => setState(() => _viewType = set.first),
              ),
              const SizedBox(height: 12),
              if (_viewType == 'General' || _viewType == 'Reports') ...[
                if (_viewType == 'General') 
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ChoiceChip(
                        label: const Text('Sessions'),
                        selected: _statType == 'Sessions',
                        onSelected: (s) { if(s) setState(() { _statType = 'Sessions'; _refreshData(); }); },
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('New Users'),
                        selected: _statType == 'Users Joined',
                        onSelected: (s) { if(s) setState(() { _statType = 'Users Joined'; _refreshData(); }); },
                      ),
                    ],
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _selectDate(context, true),
                        icon: const Icon(Icons.calendar_today, size: 14),
                        label: Text('From: ${DateFormat('MMM dd').format(startDate)}'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _selectDate(context, false),
                        icon: const Icon(Icons.calendar_today, size: 14),
                        label: Text('To: ${DateFormat('MMM dd').format(endDate)}'),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),

        // Content Area
        Expanded(
          child: _viewType == 'General' 
              ? _buildGeneralStats() 
              : _viewType == 'Insights' 
                  ? _buildAdvancedInsights()
                  : _buildDetailedReports(),
        ),
      ],
    );
  }

  Widget _buildGeneralStats() {
    return SingleChildScrollView(
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _statsData,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const SizedBox(height: 300, child: Center(child: CircularProgressIndicator()));
          }
          if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
            return const SizedBox(height: 300, child: Center(child: Text('No data found.')));
          }

          final data = snapshot.data!;
          final List<FlSpot> spots = [];
          final List<String> dates = [];
          double maxCount = 0;

          for (var i = 0; i < data.length; i++) {
            final count = double.tryParse(data[i]['session_count'].toString()) ?? 0.0;
            if (count > maxCount) maxCount = count;
            spots.add(FlSpot(i.toDouble(), count));
            dates.add(DateFormat('dd-MM').format(DateTime.parse(data[i]['session_date'])));
          }

          // Filter data based on search query
          final filteredData = data.where((item) {
            final date = item['session_date'].toString().toLowerCase();
            final count = item['session_count'].toString().toLowerCase();
            return date.contains(_searchQuery.toLowerCase()) || count.contains(_searchQuery.toLowerCase());
          }).toList();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Text('Daily Trend: $_statType', style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 250,
                      child: LineChart(
                        LineChartData(
                          lineBarsData: [
                            LineChartBarData(
                              spots: spots,
                              isCurved: true,
                              color: _statType == 'Sessions' ? Colors.blue : Colors.green,
                              barWidth: 3,
                              belowBarData: BarAreaData(show: true, color: (_statType == 'Sessions' ? Colors.blue : Colors.green).withOpacity(0.1)),
                              dotData: const FlDotData(show: true),
                            ),
                          ],
                          titlesData: FlTitlesData(
                            leftTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true, 
                                reservedSize: 40, 
                                interval: maxCount > 10 ? (maxCount / 5).ceil().toDouble() : 1, // Dynamic interval to prevent overlapping
                                getTitlesWidget: (v, m) => Text(v.toInt().toString(), style: const TextStyle(fontSize: 10))
                              )
                            ),
                            bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 30, interval: 1, getTitlesWidget: (v, meta) {
                              final i = v.toInt();
                              if (v % 1 == 0 && i >= 0 && i < dates.length && (data.length <= 10 || i % (data.length / 5).ceil() == 0)) {
                                return Text(dates[i], style: const TextStyle(fontSize: 10));
                              }
                              return const SizedBox.shrink();
                            })),
                            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          ),
                          gridData: const FlGridData(show: true, drawVerticalLine: false),
                          borderData: FlBorderData(show: true, border: Border.all(color: Colors.grey.shade300)),
                          minY: 0,
                          maxY: (maxCount < 5 ? 5 : maxCount * 1.2).ceilToDouble(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Search Filter
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: TextField(
                  onChanged: (val) => setState(() => _searchQuery = val),
                  decoration: InputDecoration(
                    hintText: 'Search by date or count...',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: Colors.grey.shade100,
                    contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
                  ),
                ),
              ),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DataTable(
                        columns: [const DataColumn(label: Text('Date')), DataColumn(label: Text('Count'))],
                        rows: filteredData.map((item) => DataRow(cells: [DataCell(Text(item['session_date'])), DataCell(Text(item['session_count'].toString()))])).toList(),
                      ),
                      if (filteredData.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(20.0),
                          child: Center(child: Text('No matching results found.')),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 80),
            ],
          );
        },
      ),
    );
  }

  Widget _buildAdvancedInsights() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPeakHoursSection(),
          const SizedBox(height: 24),
          _buildToughQuestionsSection(),
          const SizedBox(height: 24),
          _buildRetentionCard(),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildPeakHoursSection() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: SessionService.fetchPeakHours(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final data = snapshot.data!;
        
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Peak Activity Hours', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const Text('When are users most active?', style: TextStyle(color: Colors.grey, fontSize: 12)),
                const SizedBox(height: 20),
                SizedBox(
                  height: 200,
                  child: BarChart(
                    BarChartData(
                      barGroups: data.map((e) => BarChartGroupData(x: e['hour'], barRods: [BarChartRodData(toY: e['count'].toDouble(), color: Colors.deepPurple, width: 8)])).toList(),
                      titlesData: FlTitlesData(
                        bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (v, m) => v % 4 == 0 ? Text('${v.toInt()}h', style: const TextStyle(fontSize: 10)) : const SizedBox.shrink())),
                        leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      ),
                      gridData: const FlGridData(show: false),
                      borderData: FlBorderData(show: false),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildToughQuestionsSection() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: SessionService.fetchToughQuestions(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final questions = snapshot.data!;
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('🔥 Toughest Questions', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            ...questions.map((q) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(q['text'], maxLines: 2, overflow: TextOverflow.ellipsis),
                trailing: Text('${q['failure_rate'].toInt()}% Fail', style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                subtitle: Text('Attempts: ${q['total']}'),
              ),
            )),
          ],
        );
      },
    );
  }

  Widget _buildRetentionCard() {
    return Card(
      color: Colors.blue.shade900,
      child: const Padding(
        padding: EdgeInsets.all(20.0),
        child: Column(
          children: [
            Icon(Icons.loop, color: Colors.white, size: 40),
            SizedBox(height: 10),
            Text('User Retention (Mock)', style: TextStyle(color: Colors.white70)),
            Text('64%', style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
            Text('Users returning within 7 days', style: TextStyle(color: Colors.white60, fontSize: 12)),
          ],
        ),
      ),
    );
  }
  Widget _buildDetailedReports() {
    final startStr = startDate.toIso8601String().split('T').first;
    final endStr = endDate.toIso8601String().split('T').first;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Filter: Min Games Played:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              Expanded(
                child: Slider(
                  value: _minGamesFilter.toDouble(),
                  min: 1,
                  max: 20,
                  divisions: 19,
                  label: _minGamesFilter.toString(),
                  onChanged: (v) => setState(() => _minGamesFilter = v.toInt()),
                ),
              ),
              Text('$_minGamesFilter+', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF450E4E))),
            ],
          ),
          const SizedBox(height: 16),
          _buildTrendAnalysis(),
          const SizedBox(height: 32),
          
          // Participant Trends Graph
          FutureBuilder<List<Map<String, dynamic>>>(
            future: SessionService.fetchDailyParticipantTrends(startStr, endStr, _minGamesFilter),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const SizedBox.shrink();
              final data = snapshot.data!;
              if (data.isEmpty) return const SizedBox.shrink();

              // Calculate total activity per user to pick the truly "Top" users
              final Map<String, int> userTotals = {};
              for (var d in data) {
                (d['participants'] as Map<String, int>).forEach((user, count) {
                  userTotals[user] = (userTotals[user] ?? 0) + count;
                });
              }
              
              // Sort by total activity descending and take top 5 for better readability
              final sortedUsers = userTotals.entries.toList()
                ..sort((a, b) => b.value.compareTo(a.value));
              final topUsers = sortedUsers.take(5).map((e) => e.key).toList();
              
              final List<Color> userColors = [
                Colors.blue, Colors.green, Colors.orange, Colors.red, Colors.purple,
              ];

              final dates = data.map((e) => DateFormat('dd/MM').format(DateTime.parse(e['date']))).toList();

              return Card(
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      const Text('Top Participant Activity Trends', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      // Legend
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        alignment: WrapAlignment.center,
                        children: topUsers.asMap().entries.map((e) {
                          final uname = e.value;
                          final isHidden = _hiddenUsers.contains(uname);
                          return GestureDetector(
                            onTap: () => setState(() {
                              if (isHidden) _hiddenUsers.remove(uname);
                              else _hiddenUsers.add(uname);
                            }),
                            child: Opacity(
                              opacity: isHidden ? 0.3 : 1.0,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(width: 8, height: 8, color: userColors[e.key % userColors.length]),
                                  const SizedBox(width: 4),
                                  Text(uname, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        height: 220,
                        child: LineChart(
                          LineChartData(
                            minX: 0,
                            maxX: (dates.length - 1).toDouble(),
                            lineBarsData: topUsers.asMap().entries.where((e) => !_hiddenUsers.contains(e.value)).map((e) {
                              final uname = e.value;
                              return LineChartBarData(
                                spots: data.asMap().entries.map((de) {
                                  final count = de.value['participants'][uname] ?? 0;
                                  return FlSpot(de.key.toDouble(), count.toDouble());
                                }).toList(),
                                isCurved: true,
                                color: userColors[e.key % userColors.length],
                                barWidth: 3,
                                dotData: const FlDotData(show: true),
                              );
                            }).toList(),
                            titlesData: FlTitlesData(
                              bottomTitles: AxisTitles(sideTitles: SideTitles(
                                showTitles: true, 
                                reservedSize: 22,
                                interval: 1, // Fix: Only call for whole indices
                                getTitlesWidget: (v, m) {
                                  final i = v.toInt();
                                  if (i >= 0 && i < dates.length) {
                                    // Logic to show titles at reasonable intervals
                                    int skip = (dates.length / 5).ceil();
                                    if (skip < 1) skip = 1;
                                    if (i % skip == 0 || i == dates.length - 1) {
                                      return Padding(
                                        padding: const EdgeInsets.only(top: 4.0),
                                        child: Text(dates[i], style: const TextStyle(fontSize: 10)),
                                      );
                                    }
                                  }
                                  return const SizedBox.shrink();
                                },
                              )),
                              leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 30, getTitlesWidget: (v, m) => Text(v.toInt().toString(), style: const TextStyle(fontSize: 10)))),
                              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            ),
                            gridData: const FlGridData(show: true, drawVerticalLine: false),
                            borderData: FlBorderData(show: false),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          
          const SizedBox(height: 32),
          _buildReportSection(
            title: 'Top Participants (by Username)',
            future: SessionService.fetchTopParticipants(startStr, endStr, _minGamesFilter),
            columns: ['Username', 'Games Played'],
            rowBuilder: (data) => [
              DataCell(Text(data['username'], style: const TextStyle(fontWeight: FontWeight.bold))),
              DataCell(Text(data['count'].toString())),
            ],
          ),
          
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildTrendAnalysis() {
    final startStr = startDate.toIso8601String().split('T').first;
    final endStr = endDate.toIso8601String().split('T').first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Visual Trend Analysis', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF450E4E))),
        const SizedBox(height: 16),
        
        // 1. Daily Active Users Trend
        FutureBuilder<List<Map<String, dynamic>>>(
          future: SessionService.fetchUserParticipationTrend(startStr, endStr),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const SizedBox.shrink();
            final data = snapshot.data!;
            if (data.isEmpty) return const SizedBox.shrink();

            final spots = data.asMap().entries.map((e) => FlSpot(e.key.toDouble(), double.parse(e.value['count'].toString()))).toList();
            final dates = data.map((e) => DateFormat('dd/MM').format(DateTime.parse(e['date']))).toList();

            return Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    const Text('Daily Active Users', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 200,
                      child: LineChart(
                        LineChartData(
                          minX: 0,
                          maxX: (dates.length - 1).toDouble(),
                          lineBarsData: [
                            LineChartBarData(
                              spots: spots,
                              isCurved: true,
                              color: Colors.orange,
                              barWidth: 4,
                              belowBarData: BarAreaData(show: true, color: Colors.orange.withOpacity(0.1)),
                              dotData: const FlDotData(show: false),
                            ),
                          ],
                          titlesData: FlTitlesData(
                            bottomTitles: AxisTitles(sideTitles: SideTitles(
                              showTitles: true, 
                              reservedSize: 22,
                              interval: 1,
                              getTitlesWidget: (v, m) {
                                final i = v.toInt();
                                if (i >= 0 && i < dates.length) {
                                  int skip = (dates.length / 5).ceil();
                                  if (skip < 1) skip = 1;
                                  if (i % skip == 0 || i == dates.length - 1) {
                                    return Text(dates[i], style: const TextStyle(fontSize: 10));
                                  }
                                }
                                return const SizedBox.shrink();
                              },
                            )),
                            leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 30, getTitlesWidget: (v, m) => Text(v.toInt().toString(), style: const TextStyle(fontSize: 10)))),
                            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          ),
                          gridData: const FlGridData(show: true, drawVerticalLine: false),
                          borderData: FlBorderData(show: false),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        
        const SizedBox(height: 16),

        // 2. Weekly Sessions Trend
        FutureBuilder<List<Map<String, dynamic>>>(
          future: SessionService.fetchWeeklySessionsTrend(startStr, endStr),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const SizedBox.shrink();
            final data = snapshot.data!;
            if (data.isEmpty) return const SizedBox.shrink();

            final spots = data.asMap().entries.map((e) => FlSpot(e.key.toDouble(), double.parse(e.value['count'].toString()))).toList();
            final weeks = data.map((e) => 'Wk ${DateFormat('dd/MM').format(DateTime.parse(e['week']))}').toList();

            return Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    const Text('Weekly Sessions Trend', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 200,
                      child: LineChart(
                        LineChartData(
                          minX: 0,
                          maxX: (weeks.length - 1).toDouble(),
                          lineBarsData: [
                            LineChartBarData(
                              spots: spots,
                              isCurved: false,
                              color: Colors.blue,
                              barWidth: 4,
                              belowBarData: BarAreaData(show: true, color: Colors.blue.withOpacity(0.1)),
                              dotData: const FlDotData(show: true),
                            ),
                          ],
                          titlesData: FlTitlesData(
                            bottomTitles: AxisTitles(sideTitles: SideTitles(
                              showTitles: true, 
                              reservedSize: 22,
                              interval: 1,
                              getTitlesWidget: (v, m) {
                                final i = v.toInt();
                                if (i >= 0 && i < weeks.length) {
                                  int skip = (weeks.length / 5).ceil();
                                  if (skip < 1) skip = 1;
                                  if (i % skip == 0 || i == weeks.length - 1) {
                                    return Text(weeks[i], style: const TextStyle(fontSize: 10));
                                  }
                                }
                                return const SizedBox.shrink();
                              },
                            )),
                            leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 30, getTitlesWidget: (v, m) => Text(v.toInt().toString(), style: const TextStyle(fontSize: 10)))),
                            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          ),
                          gridData: const FlGridData(show: true, drawVerticalLine: true),
                          borderData: FlBorderData(show: false),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        
        const SizedBox(height: 16),

        // 3. Daily Game Mode Trends
        FutureBuilder<List<Map<String, dynamic>>>(
          future: SessionService.fetchDailyGameModeTrends(startStr, endStr),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const SizedBox.shrink();
            final data = snapshot.data!;
            if (data.isEmpty) return const SizedBox.shrink();

            final Set<String> allModes = {};
            for (var d in data) {
              allModes.addAll((d['modes'] as Map<String, int>).keys);
            }
            final sortedModes = allModes.toList()..sort();
            
            final List<Color> modeColors = [
              Colors.deepPurple, Colors.indigo, Colors.amber, Colors.cyan, Colors.pink, Colors.brown
            ];

            final dates = data.map((e) => DateFormat('dd/MM').format(DateTime.parse(e['date']))).toList();

            return Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    const Text('Daily Game Mode Trends', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 12,
                      children: sortedModes.asMap().entries.map((e) => Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(width: 8, height: 8, color: modeColors[e.key % modeColors.length]),
                          const SizedBox(width: 4),
                          Text(e.value, style: const TextStyle(fontSize: 10)),
                        ],
                      )).toList(),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 200,
                      child: LineChart(
                        LineChartData(
                          minX: 0,
                          maxX: (dates.length - 1).toDouble(),
                          lineBarsData: sortedModes.asMap().entries.map((e) {
                            final mode = e.value;
                            return LineChartBarData(
                              spots: data.asMap().entries.map((de) {
                                  final count = de.value['modes'][mode] ?? 0;
                                  return FlSpot(de.key.toDouble(), count.toDouble());
                                }).toList(),
                              isCurved: true,
                              color: modeColors[e.key % modeColors.length],
                              barWidth: 3,
                              dotData: const FlDotData(show: false),
                            );
                          }).toList(),
                          titlesData: FlTitlesData(
                            bottomTitles: AxisTitles(sideTitles: SideTitles(
                              showTitles: true, 
                              reservedSize: 22,
                              interval: 1,
                              getTitlesWidget: (v, m) {
                                final i = v.toInt();
                                if (i >= 0 && i < dates.length) {
                                  int skip = (dates.length / 5).ceil();
                                  if (skip < 1) skip = 1;
                                  if (i % skip == 0 || i == dates.length - 1) {
                                    return Text(dates[i], style: const TextStyle(fontSize: 10));
                                  }
                                }
                                return const SizedBox.shrink();
                              },
                            )),
                            leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 30, getTitlesWidget: (v, m) => Text(v.toInt().toString(), style: const TextStyle(fontSize: 10)))),
                            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          ),
                          gridData: const FlGridData(show: true, drawVerticalLine: false),
                          borderData: FlBorderData(show: false),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        
        const SizedBox(height: 16),

        // 4. Daily Room Popularity Trends
        FutureBuilder<List<Map<String, dynamic>>>(
          future: SessionService.fetchDailyRoomTypeTrends(startStr, endStr),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const SizedBox.shrink();
            final data = snapshot.data!;
            if (data.isEmpty) return const SizedBox.shrink();

            final Set<int> allCounts = {};
            for (var d in data) {
              allCounts.addAll((d['counts'] as Map<int, int>).keys);
            }
            final sortedCounts = allCounts.toList()..sort();
            
            final List<Color> lineColors = [
              Colors.teal, Colors.blue, Colors.orange, Colors.red, Colors.purple, Colors.green
            ];

            final dates = data.map((e) => DateFormat('dd/MM').format(DateTime.parse(e['date']))).toList();

            return Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    const Text('Daily Room Popularity Trends', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 12,
                      children: sortedCounts.asMap().entries.map((e) => Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(width: 8, height: 8, color: lineColors[e.key % lineColors.length]),
                          const SizedBox(width: 4),
                          Text('${e.value}P', style: const TextStyle(fontSize: 10)),
                        ],
                      )).toList(),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 200,
                      child: LineChart(
                        LineChartData(
                          minX: 0,
                          maxX: (dates.length - 1).toDouble(),
                          lineBarsData: sortedCounts.asMap().entries.map((e) {
                            final pCount = e.value;
                            return LineChartBarData(
                              spots: data.asMap().entries.map((de) {
                                  final count = de.value['counts'][pCount] ?? 0;
                                  return FlSpot(de.key.toDouble(), count.toDouble());
                                }).toList(),
                              isCurved: true,
                              color: lineColors[e.key % lineColors.length],
                              barWidth: 3,
                              dotData: const FlDotData(show: false),
                            );
                          }).toList(),
                          titlesData: FlTitlesData(
                            bottomTitles: AxisTitles(sideTitles: SideTitles(
                              showTitles: true, 
                              reservedSize: 22,
                              interval: 1,
                              getTitlesWidget: (v, m) {
                                final i = v.toInt();
                                if (i >= 0 && i < dates.length) {
                                  int skip = (dates.length / 5).ceil();
                                  if (skip < 1) skip = 1;
                                  if (i % skip == 0 || i == dates.length - 1) {
                                    return Text(dates[i], style: const TextStyle(fontSize: 10));
                                  }
                                }
                                return const SizedBox.shrink();
                              },
                            )),
                            leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 30, getTitlesWidget: (v, m) => Text(v.toInt().toString(), style: const TextStyle(fontSize: 10)))),
                            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          ),
                          gridData: const FlGridData(show: true, drawVerticalLine: false),
                          borderData: FlBorderData(show: false),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildReportSection({
    required String title,
    required Future<List<Map<String, dynamic>>> future,
    required List<String> columns,
    required List<DataCell> Function(Map<String, dynamic>) rowBuilder,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 12),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()));
            }
            if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
              return const Card(child: Padding(padding: EdgeInsets.all(20), child: Center(child: Text('No data found for this period.'))));
            }

            return Card(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: columns.map((c) => DataColumn(label: Text(c, style: const TextStyle(fontWeight: FontWeight.bold)))).toList(),
                  rows: snapshot.data!.map((item) => DataRow(cells: rowBuilder(item))).toList(),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
