import 'package:flutter/material.dart';
import 'timer_widget.dart';
import 'quiz_question.dart';
import 'scoreboard.dart';

void main() {
  runApp(const ChurchQuizApp());
}

class ChurchQuizApp extends StatelessWidget {
  const ChurchQuizApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Church History Quiz',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const QuizHomePage(),
    );
  }
}

class QuizHomePage extends StatefulWidget {
  const QuizHomePage({super.key});

  @override
  _QuizHomePageState createState() => _QuizHomePageState();
}

class _QuizHomePageState extends State<QuizHomePage> {
  int questionIndex = 0;
  List<int> scores = [0, 0]; // Example for 2 teams

  List<Question> questions = [
    Question(
      'In which year was the first publication of the book?',
      {'1972': false, '1986': false, '1965': false, '1984': true},
      'D. 1984',
    ),
    Question(
      'What did the Angel do when it appeared again to Ezekiel Guti?',
      {
        'He simply said, "Fear not, Sin not"': false,
        'He simply raised and lowered his arm': true,
        'He sang sweet thick music': false,
        'He showed him the stars of the sky': false,
      },
      'B. He simply raised and lowered his arm',
    ),
    // Add more questions here
  ];

  void _answerQuestion(bool isCorrect) {
    setState(() {
      if (isCorrect) {
        // Increment score for a team (for example, team 1 here)
        scores[0] += 10;
      }
      questionIndex++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Church History Quiz'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: questionIndex < questions.length
            ? Column(
                children: [
                  TimerWidget(
                    timeLimit: 30,
                    onTimerComplete: () {
                      setState(() {
                        questionIndex++;
                      });
                    },
                  ),
                  QuizQuestion(
                    question: questions[questionIndex],
                    onAnswerSelected: _answerQuestion,
                  ),
                ],
              )
            : const Center(
                child: Text('You completed the quiz!'),
              ),
      ),
      bottomNavigationBar: Scoreboard(scores: scores),
    );
  }
}
