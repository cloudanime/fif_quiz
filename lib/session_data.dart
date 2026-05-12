// session_data.dart
class SessionData {
  final int sessionNumber;
  final int playersCount;
  final int correctAnswers;
  final int incorrectAnswers;
  final int unansweredQuestions;
  final String createdAt;

  SessionData({
    required this.sessionNumber,
    required this.playersCount,
    required this.correctAnswers,
    required this.incorrectAnswers,
    required this.unansweredQuestions,
    required this.createdAt,
  });

  factory SessionData.fromJson(Map<String, dynamic> json) {
    return SessionData(
      sessionNumber: json['session_number'],
      playersCount: json['players_count'],
      correctAnswers: json['correct_answers'],
      incorrectAnswers: json['incorrect_answers'],
      unansweredQuestions: json['unanswered_questions'],
      createdAt: json['created_at'],
    );
  }
}
