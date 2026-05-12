class SessionStatistics {
  final String sessionNumber;
  final int numberOfQuestionsPlayed;
  final int correctAnswers;
  final int wrongAnswers;
  final int unattemptedAnswers;
  final int highestScore;
  final int lowestScore;
  final String countryLocation;

  SessionStatistics({
    required this.sessionNumber,
    required this.numberOfQuestionsPlayed,
    required this.correctAnswers,
    required this.wrongAnswers,
    required this.unattemptedAnswers,
    required this.highestScore,
    required this.lowestScore,
    required this.countryLocation,
  });

  Map<String, dynamic> toJson() {
    return {
      'session_number': sessionNumber,
      'number_of_questions_played': numberOfQuestionsPlayed,
      'correct_answers': correctAnswers,
      'wrong_answers': wrongAnswers,
      'unattempted_answers': unattemptedAnswers,
      'highest_score': highestScore,
      'lowest_score': lowestScore,
      'country_location': countryLocation,
    };
  }
}
