import 'package:flutter/material.dart';
import 'collect_data.dart';
import 'session_statistics.dart';

class QuizScreen extends StatefulWidget {
  const QuizScreen({super.key});

  @override
  _QuizScreenState createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> with WidgetsBindingObserver {
  int correctAnswers = 0;
  int wrongAnswers = 0;
  int unattemptedAnswers = 0;
  int highestScore = 0;
  int lowestScore = 0;
  int numberOfQuestionsPlayed = 0;
  String sessionNumber = "SESSION001";
  String countryLocation = "United States";
  bool isSessionActive = true; // Track session state

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      if (isSessionActive) {
        // When app is paused or detached, close the current session if active
        closeSession();
      }
    }
  }

  // Function to close the session and collect/send data
  void closeSession() {
    // Set session to inactive
    setState(() {
      isSessionActive = false;
    });

    // Collect the session data dynamically based on the quiz state
    SessionStatistics sessionStats = SessionStatistics(
      sessionNumber: sessionNumber,
      numberOfQuestionsPlayed: numberOfQuestionsPlayed,
      correctAnswers: correctAnswers,
      wrongAnswers: wrongAnswers,
      unattemptedAnswers: unattemptedAnswers,
      highestScore: highestScore,
      lowestScore: lowestScore,
      countryLocation: countryLocation,
    );

    // Send the collected data to the backend
    sendSessionData(sessionStats);

    // Display a message to the user indicating that the session has ended
    print('Session closed and data sent successfully!');
  }

  void startNewSession() {
    if (isSessionActive) {
      closeSession(); // Close the current session before starting a new one
    }

    // Reset session data for the new session
    setState(() {
      sessionNumber =
          "SESSION${DateTime.now().millisecondsSinceEpoch}"; // Example session ID
      numberOfQuestionsPlayed = 0;
      correctAnswers = 0;
      wrongAnswers = 0;
      unattemptedAnswers = 0;
      highestScore = 0;
      lowestScore = 0;
      countryLocation = "United States";
      isSessionActive = true;
    });

    print("New session started!");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Quiz Session'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text('Session Number: $sessionNumber'),
            Text('Number of Questions Played: $numberOfQuestionsPlayed'),
            Text('Correct Answers: $correctAnswers'),
            Text('Wrong Answers: $wrongAnswers'),
            Text('Unattempted Answers: $unattemptedAnswers'),
            Text('Highest Score: $highestScore'),
            Text('Lowest Score: $lowestScore'),
            Text('Location: $countryLocation'),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                startNewSession(); // Trigger a new session
              },
              child: const Text('Start New Session'),
            ),
          ],
        ),
      ),
    );
  }
}
