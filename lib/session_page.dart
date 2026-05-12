import 'package:flutter/material.dart';
import 'quiz_results.dart'; // Import the QuizResults class
import 'quiz_page.dart'; // Import the QuizPage to navigate after creating session

class SessionPage extends StatefulWidget {
  const SessionPage({super.key});

  @override
  _SessionPageState createState() => _SessionPageState();
}

class _SessionPageState extends State<SessionPage> {
  String? sessionId;
  bool isLoading = false;
  String error = '';
  int playerCount = 3; // Default number of players
  int timerDuration = 60; // Default timer duration
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  // QuizResults object to track session results
  late QuizResults quizResults;

  @override
  void initState() {
    super.initState();
    // Initialize the quiz results object
    quizResults = QuizResults(
      sessionId:
          'session_1234', // Example session ID, can be dynamically generated
      playerCount: playerCount,
      sessionDuration: timerDuration,
    );
  }

  void createSession() async {
    setState(() {
      isLoading = true;
      error = '';
    });

    try {
      // Create session logic here (e.g., fetch session ID from backend)
      sessionId =
          'session_1234'; // Example session ID, can be dynamically generated
      setState(() {
        isLoading = false;
      });

      // Navigate to the quiz page after session is created
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => QuizPage(
            sessionId: sessionId!,
            playerCount: playerCount,
            timerDuration: timerDuration,
            quizResults: quizResults, // Pass the QuizResults object
          ),
        ),
      );
    } catch (e) {
      setState(() {
        isLoading = false;
        error = 'Error creating session: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    double screenHeight = MediaQuery.of(context).size.height;
    double screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Session'),
      ),
      body: Padding(
        padding: EdgeInsets.all(screenWidth * 0.04),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: emailController,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            TextField(
              controller: passwordController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: createSession,
              child: const Text('Create Session'),
            ),
            if (isLoading) const Center(child: CircularProgressIndicator()),
            if (error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  error,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
