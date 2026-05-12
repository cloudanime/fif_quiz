import 'dart:convert';
import 'package:http/http.dart' as http;
import 'picture_question.dart';

class QuizService {
  static const String baseUrl = 'https://fifmeadmin.online';

  // Fetch multiple-choice questions based on session ID
  static Future<List<PictureQuestion>> fetchPictureQuestions() async {
    final response =
        await http.get(Uri.parse('$baseUrl/quiz_fetch_picture_questions.php'));

    if (response.statusCode == 200) {
      final List<dynamic> questionList = json.decode(response.body);
      return questionList
          .map((json) => PictureQuestion.fromJson(json as Map<String, dynamic>))
          .toList();
    } else {
      throw Exception('Failed to load picture questions');
    }
  }
}
