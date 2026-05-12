import 'session_statistics.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

Future<void> sendSessionData(SessionStatistics sessionStats) async {
  final url =
      Uri.parse('https://fifmeadmin.online/quiz_submit_session_stats.php');
  final response = await http.post(
    url,
    headers: {
      'Content-Type': 'application/json',
    },
    body: json.encode(sessionStats.toJson()),
  );

  if (response.statusCode == 200) {
    print('Data sent successfully!');
  } else {
    print('Failed to send data. Error: ${response.statusCode}');
  }
}
