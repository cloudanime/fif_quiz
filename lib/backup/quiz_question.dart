import 'package:flutter/material.dart';

class QuizQuestion extends StatelessWidget {
  final Question question;
  final Function(bool) onAnswerSelected;

  const QuizQuestion(
      {super.key, required this.question, required this.onAnswerSelected});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          question.questionText,
          style: const TextStyle(fontSize: 24.0, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 20),
        ...question.answers.keys.map((answer) {
          return ElevatedButton(
            onPressed: () => onAnswerSelected(question.answers[answer]!),
            child: Text(answer),
          );
        }),
      ],
    );
  }
}

class Question {
  final String questionText;
  final Map<String, bool> answers;
  final String correctAnswer;

  Question(this.questionText, this.answers, this.correctAnswer);
}
