// chart_page.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'chart_widget.dart';
import 'session_data.dart';

class ChartPage extends StatefulWidget {
  const ChartPage({super.key});

  @override
  _ChartPageState createState() => _ChartPageState();
}

class _ChartPageState extends State<ChartPage> {
  List<SessionData> _sessions = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    fetchSessions();
  }

  Future<void> fetchSessions() async {
    try {
      final response = await http.get(Uri.parse(
          'https://fifmeadmin.online/100quiz_legacy/fetch_session_graph.php?start_date=2025-01-01&end_date=2025-12-31'));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        setState(() {
          _sessions = data.map((json) => SessionData.fromJson(json)).toList();
          _isLoading = false;
        });
      } else {
        throw Exception('Failed to load sessions');
      }
    } catch (e) {
      print('Error: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Session Analysis')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _sessions.isEmpty
              ? const Center(child: Text('No data available'))
              : ChartWidget(sessions: _sessions),
    );
  }
}
