import 'package:flutter/material.dart';
import 'package:confetti/confetti.dart';
import 'models/local_models.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' as io;
import 'dart:async'; // For the Timer functionality
// For shuffling options
import 'mcq_question.dart';
import 'picture_question.dart'; // Ensure you import the correct model
import 'structured_question.dart'; // Ensure you import the correct model

import 'mark_answers_page.dart'; // Page to mark answers

class QuestionPage extends StatefulWidget {
  final dynamic question;
  final int playerCount;
  final int timerDuration; // Duration of the timer in seconds
  final Function(List<int>) onSubmitMarks;
  final List<GamePlayer>? players;
  final Map<String, int>? playerPoints;

  const QuestionPage({
    super.key,
    required this.question,
    required this.playerCount,
    required this.timerDuration,
    required this.onSubmitMarks,
    this.players,
    this.playerPoints,
  });

  @override
  _QuestionPageState createState() => _QuestionPageState();
}

class _QuestionPageState extends State<QuestionPage> {
  late Timer _timer;
  late int _remainingTime;
  List<MapEntry<String, bool>> _shuffledOptions = [];
  int? _selectedOptionIndex;
  bool _isAnswered = false;
  late ConfettiController _confettiControllerTop;
  late ConfettiController _confettiControllerBottom;

  @override
  void initState() {
    super.initState();
    _remainingTime = widget.timerDuration;
    _startTimer();
    _initializeOptions();
    _confettiControllerTop =
        ConfettiController(duration: const Duration(seconds: 1));
    _confettiControllerBottom =
        ConfettiController(duration: const Duration(seconds: 1));
  }

  void _initializeOptions() {
    if (widget.question is MCQQuestion) {
      final mcq = widget.question as MCQQuestion;
      _shuffledOptions = mcq.answers.entries.toList();
      _shuffledOptions.shuffle();
    }
  }

  String _stripPrefix(String opt) {
    if (opt.length >= 3 && opt[1] == '.' && opt[2] == ' ') {
      return opt.substring(3);
    }
    return opt;
  }

  // Start the countdown timer
  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingTime > 0) {
        setState(() {
          _remainingTime--;
        });
      } else {
        _timer.cancel(); // Stop the timer when it reaches zero
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    _confettiControllerTop.dispose();
    _confettiControllerBottom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Get screen dimensions and scaling factors
    final Size screenSize = MediaQuery.of(context).size;
    final bool isSmallScreen =
        screenSize.width < 600; // Example breakpoint for small screens
    final double baseFontSize = isSmallScreen
        ? 16.0
        : (screenSize.width * 0.015)
            .clamp(16.0, 22.0); // Clamped and reduced from 0.02

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Image.asset(
              'assets/baba100new.jpg', // Path to your logo image
              height:
                  screenSize.height * 0.05, // Adjusted height for the new logo
            ),
            const SizedBox(width: 10),
            Text(
              'Legacy Quiz',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: baseFontSize * 1.1,
                fontWeight: FontWeight.bold,
                color: Colors.yellow,
              ),
            ),
          ],
        ),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.all((screenSize.width * 0.03)
                  .clamp(16.0, 32.0)), // Clamped padding
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Display the timer
                  Text(
                    'Time remaining: $_remainingTime seconds',
                    style: TextStyle(
                      fontSize: baseFontSize * 1.2, // Responsive font size
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: screenSize.height * 0.02),

                  // Display the question text for all question types
                  Text(
                    _getQuestionText(),
                    style: TextStyle(
                      fontSize: baseFontSize * 1.2, // Responsive font size
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: screenSize.height * 0.02),

                  // Display answer options for MCQ questions
                  if (widget.question is MCQQuestion)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: _shuffledOptions.asMap().entries.map((entry) {
                        final index = entry.key;
                        final option = entry.value;
                        final isCorrect = option.value;
                        final isSelected = _selectedOptionIndex == index;

                        final labels = ['A', 'B', 'C', 'D', 'E'];
                        final label =
                            index < labels.length ? labels[index] : '';
                        final text = _stripPrefix(option.key);

                        return GestureDetector(
                          onTap: (_isAnswered || widget.playerCount != 1)
                              ? null
                              : () {
                                  setState(() {
                                    _selectedOptionIndex = index;
                                    _isAnswered = true;
                                  });
                                  if (isCorrect) {
                                    _confettiControllerTop.play();
                                    _confettiControllerBottom.play();
                                  }
                                },
                          child: Container(
                            width: double.infinity,
                            margin: EdgeInsets.symmetric(
                                vertical: (screenSize.height * 0.005)
                                    .clamp(4.0, 8.0)),
                            padding: EdgeInsets.all((screenSize.width * 0.02)
                                .clamp(12.0, 20.0)), // Reduced padding
                            decoration: BoxDecoration(
                              color: _isAnswered && widget.playerCount == 1
                                  ? (isCorrect
                                      ? Colors.green.withOpacity(0.2)
                                      : (isSelected
                                          ? Colors.red.withOpacity(0.2)
                                          : Colors.transparent))
                                  : (isSelected
                                      ? Colors.blue.withOpacity(0.1)
                                      : Colors.transparent),
                              border: Border.all(
                                color: _isAnswered && widget.playerCount == 1
                                    ? (isCorrect
                                        ? Colors.green
                                        : (isSelected
                                            ? Colors.red
                                            : Colors.grey.shade300))
                                    : (isSelected
                                        ? Colors.blue
                                        : Colors.grey.shade300),
                                width: isSelected || (_isAnswered && isCorrect)
                                    ? 2
                                    : 1,
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 30,
                                  height: 30,
                                  decoration: BoxDecoration(
                                    color:
                                        _isAnswered && widget.playerCount == 1
                                            ? (isCorrect
                                                ? Colors.green
                                                : (isSelected
                                                    ? Colors.red
                                                    : Colors.grey.shade200))
                                            : (isSelected
                                                ? Colors.blue
                                                : Colors.grey.shade200),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Center(
                                    child: Text(
                                      label,
                                      style: TextStyle(
                                        color: isSelected ||
                                                (_isAnswered && isCorrect)
                                            ? Colors.white
                                            : Colors.black,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 15),
                                Expanded(
                                  child: Text(
                                    text,
                                    style: TextStyle(
                                      fontSize: baseFontSize * 1.0,
                                      fontWeight: isSelected
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                  ),
                                ),
                                if (_isAnswered && widget.playerCount == 1)
                                  Icon(
                                    isCorrect
                                        ? Icons.check_circle
                                        : (isSelected ? Icons.cancel : null),
                                    color:
                                        isCorrect ? Colors.green : Colors.red,
                                  ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  if (widget.question is PictureQuestion)
                    Column(
                      children: [
                        // Display images for PictureQuestion type
                        _displayPictureQuestionImages(widget.question),
                        SizedBox(height: screenSize.height * 0.02),
                      ],
                    ),
                  SizedBox(height: screenSize.height * 0.02),

                  if (_isAnswered &&
                      widget.playerCount == 1 &&
                      _getSourceText().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 20.0),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.yellow,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange),
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 4,
                                offset: const Offset(0, 2)),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.info_outline,
                                    size: 16, color: Colors.black),
                                SizedBox(width: 8),
                                Text(
                                  'SOURCE:',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      color: Colors.black,
                                      fontSize: 12),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _getSourceText(),
                              style: const TextStyle(
                                  fontStyle: FontStyle.italic,
                                  color: Colors.black87,
                                  fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // Button to mark the answer
                  ElevatedButton(
                    onPressed: () {
                      if (widget.playerCount == 1 &&
                          widget.question is MCQQuestion) {
                        // In Solo Mode for MCQ, we can directly submit marks if answered
                        if (!_isAnswered) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Please select an answer first')),
                          );
                          return;
                        }
                        final isCorrect =
                            _shuffledOptions[_selectedOptionIndex!].value;
                        widget.onSubmitMarks([isCorrect ? 1 : -1]);
                      } else {
                        // Otherwise, go to the marking page
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => MarkAnswersPage(
                              question: widget.question,
                              playerCount: widget.playerCount,
                              onSubmitMarks: widget.onSubmitMarks,
                              players: widget.players,
                              playerPoints: widget.playerPoints,
                            ),
                          ),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isAnswered && widget.playerCount == 1
                          ? Colors.deepPurple
                          : null,
                      foregroundColor: _isAnswered && widget.playerCount == 1
                          ? Colors.white
                          : null,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(
                      widget.playerCount == 1 && widget.question is MCQQuestion
                          ? (_isAnswered
                              ? 'Confirm & Next'
                              : 'Select an Answer')
                          : 'Mark the Answers',
                      style: TextStyle(
                          fontSize: baseFontSize * 0.8,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 40), // Added bottom space
                ],
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: Stack(
                  children: [
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: SizedBox(
                          width: 10,
                          height: 10,
                          child: ConfettiWidget(
                            confettiController: _confettiControllerTop,
                            blastDirectionality: BlastDirectionality.explosive,
                            maxBlastForce: 8,
                            minBlastForce: 2,
                            emissionFrequency: 0.02,
                            numberOfParticles: 5,
                            gravity: 0.1,
                            shouldLoop: false,
                            colors: const [
                              Colors.green,
                              Colors.yellow,
                              Colors.pink,
                              Colors.orange,
                              Colors.purple
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: SizedBox(
                          width: 10,
                          height: 10,
                          child: ConfettiWidget(
                            confettiController: _confettiControllerBottom,
                            blastDirectionality: BlastDirectionality.explosive,
                            maxBlastForce: 15,
                            minBlastForce: 5,
                            emissionFrequency: 0.05,
                            numberOfParticles: 15,
                            gravity: 0.2,
                            shouldLoop: false,
                            colors: const [
                              Colors.green,
                              Colors.yellow,
                              Colors.pink,
                              Colors.orange,
                              Colors.purple
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Function to get the question text for different question types
  String _getQuestionText() {
    if (widget.question is MCQQuestion) {
      return (widget.question as MCQQuestion).questionText;
    } else if (widget.question is PictureQuestion) {
      return (widget.question as PictureQuestion).question;
    } else if (widget.question is StructuredQuestion) {
      return (widget.question as StructuredQuestion).question;
    } else {
      return 'Unknown question type';
    }
  }

  // Function to get the source text for the question
  String _getSourceText() {
    if (widget.question is MCQQuestion) {
      return (widget.question as MCQQuestion).source;
    } else if (widget.question is PictureQuestion) {
      return (widget.question as PictureQuestion).source;
    } else if (widget.question is StructuredQuestion) {
      return (widget.question as StructuredQuestion).source;
    } else {
      return '';
    }
  }

  // Widget to display images for PictureQuestion type in a single row (1x4 grid)
  Widget _displayPictureQuestionImages(PictureQuestion question) {
    List<String> imageUrls = question.imageUrls;

    if (imageUrls.isEmpty) {
      return const Center(child: Text('No images available for this question'));
    }

    return SizedBox(
      height: MediaQuery.of(context).size.height *
          0.25, // Maximum height for the box
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: imageUrls.map((imageUrl) {
          return Flexible(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Container(
                    constraints: BoxConstraints(
                      maxWidth: constraints.maxWidth, // Maximum width
                      maxHeight: constraints.maxHeight, // Maximum height
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(
                        color: Colors.purple,
                        width: 1.0,
                      ),
                      borderRadius: BorderRadius.circular(8.0),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 4.0,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8.0),
                      child: FittedBox(
                        fit: BoxFit.contain,
                        child: _buildImage(imageUrl),
                      ),
                    ),
                  );
                },
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildImage(String path) {
    if (path.startsWith('http')) {
      return Image.network(
        path,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return const Center(child: CircularProgressIndicator());
        },
        errorBuilder: (context, error, stackTrace) =>
            const Icon(Icons.error, color: Colors.red),
      );
    } else if (path.startsWith('assets/')) {
      return Image.asset(
        path,
        errorBuilder: (context, error, stackTrace) =>
            const Icon(Icons.error, color: Colors.red),
      );
    } else {
      if (!kIsWeb) {
        return Image.file(
          io.File(path),
          errorBuilder: (context, error, stackTrace) =>
              const Icon(Icons.error, color: Colors.red),
        );
      } else {
        return const Icon(Icons.broken_image, color: Colors.grey);
      }
    }
  }
}
