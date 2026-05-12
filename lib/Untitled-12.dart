import 'package:http/http.dart' as http;
import 'dart:convert';

class SessionService {
  static Future<List<Map<String, dynamic>>> fetchSessionsPerDay(
      String startDate, String endDate) async {
    final url = Uri.parse(
        'https://fifmeadmin.online/100quiz_legacy/fetch_sessions.php?start_date=$startDate&end_date=$endDate');

    try {
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          return List<Map<String, dynamic>>.from(data['data']);
        } else {
          throw Exception('Error from server: ${data['message']}');
        }
      } else {
        throw Exception('Failed to fetch sessions: HTTP ${response.statusCode}');
      }
    } catch (e) {
      print('Error fetching sessions: $e');
      throw Exception('Could not fetch sessions');
    }
  }
}
