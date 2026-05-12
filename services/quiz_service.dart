import 'package:http/http.dart' as http;
import 'dart:convert';

class QuizService {
  static Future<void> recordStatistics(Map<String, dynamic> statistics) async {
    final url = Uri.parse(
        'https://fifmeadmin.online/100quiz_legacy/update_session_statistics.php');
    try {
      final response = await http.post(
        url,
        body: json.encode(statistics),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to record statistics: ${response.body}');
      }
    } catch (e) {
      print('Error recording statistics: $e');
    }
  }
}
