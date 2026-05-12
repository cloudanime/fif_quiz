class QuizResults {
  final String sessionId;
  final int playerCount;
  final int sessionDuration;
  int mcqCorrectAnswers = 0;
  int pictureCorrectAnswers = 0;
  int structuredCorrectAnswers = 0;
  int mcqAttempts = 0;
  int pictureAttempts = 0;
  int structuredAttempts = 0;
  int unattemptedQuestions = 0;

  QuizResults({
    required this.sessionId,
    required this.playerCount,
    required this.sessionDuration,
  });

  // Method to update results
  void updateResults(int questionType, bool isCorrect, bool isAttempted) {
    if (isAttempted) {
      switch (questionType) {
        case 1: // MCQ
          mcqAttempts++;
          if (isCorrect) {
            mcqCorrectAnswers++;
          }
          break;
        case 2: // Picture Question
          pictureAttempts++;
          if (isCorrect) {
            pictureCorrectAnswers++;
          }
          break;
        case 3: // Structured Question
          structuredAttempts++;
          if (isCorrect) {
            structuredCorrectAnswers++;
          }
          break;
        default:
          break;
      }
    } else {
      unattemptedQuestions++;
    }
  }
}
