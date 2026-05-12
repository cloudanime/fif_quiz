import 'package:flutter/material.dart';
import 'quiz_results.dart';

class QuizPage extends StatelessWidget {
  final String sessionId;
  final int playerCount;
  final int timerDuration;
  final QuizResults quizResults;

  const QuizPage({
    super.key,
    required this.sessionId,
    required this.playerCount,
    required this.timerDuration,
    required this.quizResults,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Quiz Session')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text('Session ID: ${quizResults.sessionId}'),
            Text('Total Players: ${quizResults.playerCount}'),
            Text('Duration: ${quizResults.sessionDuration} seconds'),
            // Display session results here (correct answers, attempts, etc.)
            Text('MCQ Correct: ${quizResults.mcqCorrectAnswers}'),
            Text('Picture Correct: ${quizResults.pictureCorrectAnswers}'),
            Text('Structured Correct: ${quizResults.structuredCorrectAnswers}'),
            Text('Unattempted Questions: ${quizResults.unattemptedQuestions}'),
          ],
        ),
      ),
    );
  }
}
