import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:confetti/confetti.dart';
import 'models/local_models.dart';
import 'mcq_question.dart';
import 'picture_question.dart';
import 'structured_question.dart';

// Allow mouse dragging for horizontal scrolling on web
class MyCustomScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
      };
}

class MarkAnswersPage extends StatefulWidget {
  final dynamic question; // Dynamic to accept multiple question types
  final int playerCount;
  final Function(List<int>) onSubmitMarks;
  final List<GamePlayer>? players;
  final Map<String, int>? playerPoints;

  const MarkAnswersPage({
    super.key,
    required this.question,
    required this.playerCount,
    required this.onSubmitMarks,
    this.players,
    this.playerPoints,
  });

  @override
  _MarkAnswersPageState createState() => _MarkAnswersPageState();
}

class _MarkAnswersPageState extends State<MarkAnswersPage> {
  List<int?> playerMarks = [];
  late ConfettiController _confettiController;
  final ScrollController _horizontalScrollController = ScrollController();
  final ScrollController _footerScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    playerMarks = List<int?>.filled(widget.playerCount, null);
    _confettiController =
        ConfettiController(duration: const Duration(milliseconds: 600));
  }

  Future<void> _submitMarks() async {
    // Check if any marks have been assigned
    bool anyMarked = playerMarks.any((mark) => mark != null);

    if (!anyMarked) {
      // Show confirmation dialog if nothing is marked
      final bool? confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('No Marks Assigned'),
          content: const Text(
              'You haven\'t marked any player as correct or incorrect. Are you sure you want to submit?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Submit Anyway'),
            ),
          ],
        ),
      );

      if (confirm != true) return;
    }

    // Convert null marks to 0 (not marked) before submitting
    List<int> finalMarks = playerMarks.map((mark) => mark ?? 0).toList();
    // Stop any active confetti before returning to grid
    _confettiController.stop();
    widget.onSubmitMarks(finalMarks);
    if (mounted) {
      Navigator.pop(context); // Return to the previous screen
    }
  }

  @override
  void dispose() {
    _confettiController.dispose();
    _horizontalScrollController.dispose();
    _footerScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Size screenSize = MediaQuery.of(context).size;
    final bool isSmallScreen = screenSize.width < 600;
    final double baseFontSize = isSmallScreen
        ? 16.0
        : (screenSize.width * 0.015)
            .clamp(16.0, 22.0); // Clamped for large screens
    double textScaleFactor = MediaQuery.of(context).textScaleFactor;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Image.asset(
              'assets/baba100new.jpg', // Ensure the path to your logo is correct
              height: 40, // Adjust the height for the AppBar
            ),
            const SizedBox(width: 10),
            const Text(
              'Legacy Quiz',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
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
                  // Display the question text
                  Text(
                    _getQuestionText(),
                    style: TextStyle(
                      fontSize: baseFontSize * 1.4,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: screenSize.height * 0.02),

                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.yellow,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange, width: 1),
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
                        const Text(
                          'CORRECT ANSWER:',
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          _getCorrectAnswerText(),
                          style: TextStyle(
                            color: Colors.black,
                            fontSize:
                                (screenSize.width * 0.022).clamp(20.0, 36.0),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (_getSourceText().isNotEmpty) ...[
                          const SizedBox(height: 10),
                          const Text(
                            'SOURCE:',
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            _getSourceText(),
                            style: TextStyle(
                              color: Colors.black87,
                              fontSize:
                                  (screenSize.width * 0.018).clamp(18.0, 30.0),
                              fontWeight: FontWeight.bold,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  SizedBox(height: screenSize.height * 0.01),

                  SizedBox(
                    height: 180,
                    child: Scrollbar(
                      controller: _horizontalScrollController,
                      thumbVisibility: true,
                      thickness: 8.0,
                      radius: const Radius.circular(4),
                      child: ScrollConfiguration(
                        behavior: MyCustomScrollBehavior(),
                        child: SingleChildScrollView(
                          controller: _horizontalScrollController,
                          scrollDirection: Axis.horizontal,
                          physics: const AlwaysScrollableScrollPhysics(),
                          child: Padding(
                            padding: const EdgeInsets.only(
                                bottom: 16), // Space for scrollbar
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children:
                                  List.generate(widget.playerCount, (index) {
                                final p = widget.players != null &&
                                        index < widget.players!.length
                                    ? widget.players![index]
                                    : null;
                                return Container(
                                  width: 150,
                                  height:
                                      140, // Fixed height for the column content
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                        color: Colors.black.withOpacity(0.2)),
                                    color: index % 2 == 0
                                        ? Colors.white.withOpacity(0.5)
                                        : Colors.transparent,
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      // Header
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 8),
                                        color: Colors.black.withOpacity(0.05),
                                        child: Column(
                                          children: [
                                            Text('P${index + 1}',
                                                style: TextStyle(
                                                    fontSize:
                                                        baseFontSize * 0.8,
                                                    color: Colors.grey)),
                                            if (p != null)
                                              Text(p.displayName,
                                                  textAlign: TextAlign.center,
                                                  style: TextStyle(
                                                      fontSize: baseFontSize,
                                                      fontWeight:
                                                          FontWeight.bold),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis),
                                          ],
                                        ),
                                      ),
                                      // Correct Button
                                      IconButton(
                                        onPressed: () {
                                          setState(
                                              () => playerMarks[index] = 1);
                                          _confettiController.play();
                                        },
                                        icon: Icon(Icons.check_circle,
                                            color: playerMarks[index] == 1
                                                ? Colors.green
                                                : Colors.grey.shade300,
                                            size: 32),
                                      ),
                                      // Divider
                                      Divider(
                                          height: 1,
                                          color: Colors.black.withOpacity(0.1)),
                                      // Incorrect Button
                                      IconButton(
                                        onPressed: () => setState(
                                            () => playerMarks[index] = -1),
                                        icon: Icon(Icons.clear,
                                            color: playerMarks[index] == -1
                                                ? Colors.red
                                                : Colors.grey.shade300,
                                            size: 32),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: screenSize.height * 0.02),

                  Text(
                    '\n Do not click the button before marking answers',
                    style: TextStyle(
                      fontWeight: FontWeight.bold, // Bold text
                      fontStyle: FontStyle.italic, // Italic text
                      color: Colors.red, // Red text color
                      fontSize: baseFontSize * 0.9, // Responsive font size
                    ),
                  ),

                  SizedBox(height: screenSize.height * 0.03),
                  ElevatedButton(
                    onPressed: _submitMarks,
                    child: Text(
                      'Submit Marks',
                      style: TextStyle(
                        fontWeight: FontWeight.bold, // Bold text
                        fontSize: baseFontSize * 0.9, // Font size
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),

          // Confetti burst on every mark action
          LayoutBuilder(builder: (context, constraints) {
            if (constraints.maxWidth == 0 || constraints.maxHeight == 0)
              return const SizedBox();
            return Align(
              alignment: Alignment.bottomCenter,
              child: IgnorePointer(
                child: ConfettiWidget(
                  confettiController: _confettiController,
                  blastDirection: -1.5708,
                  blastDirectionality: BlastDirectionality.explosive,
                  shouldLoop: false,
                  numberOfParticles: 20,
                  maxBlastForce: 60,
                  minBlastForce: 30,
                  emissionFrequency: 0.03,
                  gravity: 0.15,
                  colors: const [
                    Colors.green,
                    Colors.yellow,
                    Colors.cyan,
                    Colors.orange,
                    Colors.white,
                    Colors.purple
                  ],
                ),
              ),
            );
          }),
        ],
      ),
      bottomNavigationBar: widget.players == null
          ? null
          : Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              color: const Color(0xFF311B92), // Very dark purple
              child: Row(
                children: [
                  const Text(
                    'SCORE',
                    style: TextStyle(
                      color: Color(0xFFFFD600),
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: ScrollConfiguration(
                      behavior: MyCustomScrollBehavior(),
                      child: Scrollbar(
                        controller: _footerScrollController,
                        thumbVisibility: true,
                        child: SingleChildScrollView(
                          controller: _footerScrollController,
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children:
                                widget.players!.asMap().entries.map((entry) {
                              int idx = entry.key;
                              var p = entry.value;
                              return Container(
                                width: 90, // FORCED WIDTH
                                margin: const EdgeInsets.only(right: 8),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF4527A0),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: Colors.white24),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      'P${idx + 1} ',
                                      style: const TextStyle(
                                          color: Colors.white70, fontSize: 11),
                                    ),
                                    Text(
                                      '${widget.playerPoints![p.displayName] ?? 0}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  // Get the question text based on the type of question
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

  // Get the correct answer text based on the type of question
  String _getCorrectAnswerText() {
    if (widget.question is MCQQuestion) {
      final mcq = widget.question as MCQQuestion;
      String correctLetter = mcq.correctLetter.toUpperCase();
      return _getCorrectOptionText(mcq, correctLetter);
    } else if (widget.question is PictureQuestion) {
      return (widget.question as PictureQuestion).answer;
    } else if (widget.question is StructuredQuestion) {
      return (widget.question as StructuredQuestion).correctAnswer;
    }
    return '';
  }

  String _getSourceText() {
    String source = '';
    if (widget.question is MCQQuestion) {
      source = (widget.question as MCQQuestion).source;
    } else if (widget.question is PictureQuestion) {
      source = (widget.question as PictureQuestion).source;
    } else if (widget.question is StructuredQuestion) {
      source = (widget.question as StructuredQuestion).source;
    }
    return source.length > 2 ? source : '';
  }

  // Helper method to get the correct option text based on the letter
  String _getCorrectOptionText(MCQQuestion mcq, String correctAnswer) {
    switch (correctAnswer) {
      case 'A':
        return ' ${mcq.answers.keys.firstWhere((key) => key.startsWith('A'))}';
      case 'B':
        return ' ${mcq.answers.keys.firstWhere((key) => key.startsWith('B'))}';
      case 'C':
        return ' ${mcq.answers.keys.firstWhere((key) => key.startsWith('C'))}';
      case 'D':
        return ' ${mcq.answers.keys.firstWhere((key) => key.startsWith('D'))}';
      default:
        return 'Unknown option';
    }
  }
}
