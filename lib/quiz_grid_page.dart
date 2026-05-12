import 'instructions.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'mcq_question.dart';
import 'picture_question.dart';
import 'structured_question.dart';
import 'fetch_Mixed_Questions.dart'; // Fetch questions from the service
import 'question_page.dart'; // Page to display individual questions
import 'package:flutter_colorpicker/flutter_colorpicker.dart'; // Flutter Color Picker
import 'add_mcq_page.dart'; // Import the Add MCQ Page
import 'add_picture_question.dart'; // Import the Add Picture Question Page
import 'add_structured_question.dart'; // Import the Add Structured Question Page
import 'web_rank_history_chart.dart'; // Animated Winner Review

class QuizGridPage extends StatefulWidget {
  final String sessionId;
  final int playerCount;
  final int timerDuration;

  const QuizGridPage({
    super.key,
    required this.sessionId,
    required this.playerCount,
    required this.timerDuration,
  });

  @override
  _QuizGridPageState createState() => _QuizGridPageState();
}

class _QuizGridPageState extends State<QuizGridPage> {
  List<MCQQuestion> mcqQuestions = [];
  List<PictureQuestion> pictureQuestions = [];
  List<StructuredQuestion> structuredQuestions = [];
  List<int> scores = [];
  List<List<int>> scoreHistory = [];
  List<bool> answeredQuestions = [];
  bool isLoading = true;
  bool hasError = false;
  double _gridWidthPercent = 1.0;
  double _gridHeightPercent = 1.0;
  double _fontSizeFactor = 0.75;
  Color backgroundColor = const Color(0xFFEAC7EF); // Default background color

  int flippedCards = 0; // Track the number of flipped cards
  int correctAnswers = 0;
  int incorrectAnswers = 0;
  int unansweredQuestions = 0;

  @override
  void initState() {
    super.initState();
    scores = List<int>.filled(widget.playerCount, 0);
    scoreHistory = List.generate(widget.playerCount, (i) => [0]);
    answeredQuestions =
        List<bool>.filled(100, false); // Keep track of answered questions

    fetchQuestions();
  }

  void fetchQuestions() async {
    try {
      final fetchedMcqQuestions =
          await QuizService.fetchQuestions(sessionId: widget.sessionId);
      final fetchedPictureQuestions =
          await QuizService.fetchPictureQuestions(sessionId: widget.sessionId);
      final fetchedStructuredQuestions =
          await QuizService.fetchStructuredQuestions(
              sessionId: widget.sessionId);

      setState(() {
        mcqQuestions = fetchedMcqQuestions;
        pictureQuestions = fetchedPictureQuestions;
        structuredQuestions = fetchedStructuredQuestions;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        isLoading = false;
        hasError = true;
      });
    }
  }

  // Update flippedCards when a question is answered
  void updateScores(List<int> playerMarks, int points, int index) {
    setState(() {
      for (int i = 0; i < widget.playerCount; i++) {
        if (playerMarks[i] == 1) {
          scores[i] += points; // Correct answer
        } else if (playerMarks[i] == -1) {
          scores[i] -= points; // Incorrect answer
        }
        scoreHistory[i].add(scores[i]);
      }

      if (!answeredQuestions[index]) {
        flippedCards++;
      }
      answeredQuestions[index] = true;

      // Update counts for the current question
      updateAnswerCounts(playerMarks);

      // NO CONFETTI ON GRID
    });
  }

// Update session with questions done
  Future<void> closeSession(
      String sessionId,
      int questionsDone,
      int playerCount,
      int correctAnswers,
      int incorrectAnswers,
      int unansweredQuestions) async {
    if (sessionId == 'solo-session') return; // Skip for solo mode
    try {
      final response = await http.post(
        Uri.parse(
            'https://fifmeadmin.online/100quiz_legacy/questions_done.php'),
        body: {
          'session_id': sessionId,
          'questions_done': questionsDone.toString(),
          'players_count': playerCount.toString(),
          'correct_answers': correctAnswers.toString(),
          'incorrect_answers': incorrectAnswers.toString(),
          'unanswered_questions': unansweredQuestions.toString(),
        },
      );

      if (response.statusCode == 200) {
        debugPrint('Session details updated successfully.');
      } else {
        debugPrint('Failed to update session: ${response.body}');
      }
    } catch (e) {
      debugPrint('Error during session update: $e');
    }
  }

  @override
  void dispose() {
    closeSession(
      widget.sessionId,
      flippedCards,
      widget.playerCount, // Add the missing argument
      correctAnswers,
      incorrectAnswers,
      unansweredQuestions,
    ).then((_) {
      debugPrint('Session successfully closed.');
    }).catchError((error) {
      debugPrint('Error during session close: $error');
    }).whenComplete(() {
      super.dispose();
    });
  }

  void showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  void pickColor() async {
    Color pickedColor = backgroundColor;
    double dialogWidth =
        (MediaQuery.of(context).size.width * 0.5).clamp(250.0, 400.0);
    double dialogHeight =
        (MediaQuery.of(context).size.height * 0.4).clamp(300.0, 500.0);

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Pick Background Color"),
          content: Column(
            mainAxisSize: MainAxisSize.min, // Ensures content fits dialog size
            children: [
              SizedBox(
                width: dialogWidth,
                height: dialogHeight,
                child: SingleChildScrollView(
                  child: ColorPicker(
                    pickerColor: backgroundColor,
                    onColorChanged: (color) {
                      pickedColor = color;
                    },
                    enableAlpha: false,
                    displayThumbColor: true,
                  ),
                ),
              ),
              const SizedBox(
                  height: 40.0), // Add spacing between picker and button
              ElevatedButton(
                child: const Text("Select"),
                onPressed: () {
                  setState(() {
                    backgroundColor = pickedColor;
                  });
                  Navigator.of(context).pop();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void updateAnswerCounts(List<int> playerMarks) {
    // Count responses for this question
    int correctForThisQuestion = playerMarks.where((mark) => mark == 1).length;
    int incorrectForThisQuestion =
        playerMarks.where((mark) => mark == -1).length;
    int unansweredForThisQuestion =
        playerMarks.where((mark) => mark == 0).length;

    // Update running totals
    setState(() {
      correctAnswers += correctForThisQuestion;
      incorrectAnswers += incorrectForThisQuestion;
      unansweredQuestions += unansweredForThisQuestion;
    });
  }

  Widget _buildGridLegend() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 10),
      color: Colors.transparent,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _legendItem("1-70 MCQ", const Color(0xFF006400)),
          _legendItem("71-80 Picture", const Color(0xFF8B0000)),
          _legendItem("81-100 Structured", const Color(0xFF00008B)),
        ],
      ),
    );
  }

  Widget _legendItem(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color, width: 1.2),
      ),
      child: Text(
        text,
        style:
            TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Size screenSize = MediaQuery.of(context).size;
    final double calculatedFontSize =
        (screenSize.width * 0.02).clamp(16.0, 24.0);
    final double calculatedLogoHeight =
        (screenSize.height * 0.06).clamp(40.0, 80.0);
    double screenHeight = MediaQuery.of(context).size.height;
    double screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: const Color.fromARGB(255, 96, 5, 105),
        automaticallyImplyLeading: false, // Removes the back arrow
        title: Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 4.0),
              child: Image.asset(
                'assets/baba100new.jpg',
                width: (screenSize.width * 0.12).clamp(30.0, 80.0),
                height: screenSize.height * 0.05,
                fit: BoxFit.contain,
              ),
            ),
            SizedBox(width: screenWidth * 0.02),
            Flexible(
              child: RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: 'Legacy Quiz\n',
                      style: TextStyle(
                        fontSize: (screenHeight * 0.02).clamp(14.0, 22.0),
                        color: const Color.fromARGB(247, 251, 232, 13),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    TextSpan(
                      text: '(Dynamic questions)',
                      style: TextStyle(
                        fontSize: (screenHeight * 0.012).clamp(10.0, 14.0),
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.emoji_events, color: Colors.yellow),
            onPressed: _showWinnerDialog,
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            color: Colors.yellow,
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const InstructionsPage(),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.yellow),
            onPressed: () async {
              final shouldQuit = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Quit Quiz'),
                  content:
                      const Text('Are you sure you want to quit the quiz?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('Quit'),
                    ),
                  ],
                ),
              );
              if (shouldQuit == true) {
                Navigator.of(context).pop();
              }
            },
          ),
          SizedBox(width: screenSize.width * 0.02),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : hasError
              ? const Center(child: Text('Error loading questions'))
              : Stack(
                  children: [
                    Column(
                      children: [
                        buildControlPanel(calculatedFontSize),
                        _buildGridLegend(),
                        Expanded(
                          child: LayoutBuilder(
                              builder: (context, gridConstraints) {
                            return Center(
                              child: SizedBox(
                                width: screenSize.width * _gridWidthPercent,
                                height: gridConstraints.maxHeight *
                                    _gridHeightPercent,
                                child: buildQuestionGrid(
                                    gridConstraints, screenSize),
                              ),
                            );
                          }),
                        ),
                        const SizedBox(height: 2),
                        buildScoreboard(screenSize, calculatedFontSize),
                        const SizedBox(height: 2),
                        buildFooter(screenSize, calculatedFontSize),
                      ],
                    ),
                  ],
                ),
    );
  }

  Widget buildControlPanel(double adjustedFontSize) {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      color: Colors.white.withOpacity(0.9),
      child: Row(
        children: [
          _buildSlider('W', _gridWidthPercent,
              (v) => setState(() => _gridWidthPercent = v)),
          _buildSlider('H', _gridHeightPercent,
              (v) => setState(() => _gridHeightPercent = v)),
          _buildSlider(
              'F', _fontSizeFactor, (v) => setState(() => _fontSizeFactor = v),
              min: 0.5, max: 2.0),
        ],
      ),
    );
  }

  Widget _buildSlider(
      String label, double value, ValueChanged<double> onChanged,
      {double min = 0.1, double max = 1.0}) {
    return Expanded(
      child: Row(
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Colors.purple)),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              ),
              child: Slider(
                value: value,
                min: min,
                max: max,
                activeColor: Colors.purple,
                inactiveColor: Colors.purple.withOpacity(0.2),
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildQuestionGrid(BoxConstraints constraints, Size screenSize) {
    final double gridWidth = constraints.maxWidth;
    final double gridHeight = constraints.maxHeight;

    final double gridItemWidth = gridWidth / 10;
    final double gridItemHeight = gridHeight / 10;

    return GridView.builder(
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(), // Disable scrolling
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 10,
        childAspectRatio:
            (gridItemHeight > 0) ? (gridItemWidth / gridItemHeight) : 1.0,
        crossAxisSpacing: 1.0,
        mainAxisSpacing: 1.0,
      ),
      itemCount: 100, // Fixed grid size
      itemBuilder: (context, index) {
        return buildQuestionCard(
          context,
          index,
          getQuestionForIndex(index),
          gridItemHeight,
        );
      },
    );
  }

  dynamic getQuestionForIndex(int index) {
    if (index < 70) {
      if (index >= mcqQuestions.length) return null;
      return mcqQuestions[index];
    } else if (index < 80) {
      if ((index - 70) >= pictureQuestions.length) return null;
      return pictureQuestions[index - 70];
    } else {
      if ((index - 80) >= structuredQuestions.length) return null;
      return structuredQuestions[index - 80];
    }
  }

  Widget buildPlaceholderCard(int index, double gridItemHeight) {
    return Card(
      elevation: 4,
      shadowColor: Colors.black.withOpacity(0.2),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
      ),
      margin: EdgeInsets.zero,
      child: Center(
        child: Text(
          'No Question $index',
          style: TextStyle(
            fontSize: (gridItemHeight * 0.1) * _fontSizeFactor,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget buildQuestionCard(BuildContext context, int index, dynamic question,
      double gridItemHeight) {
    final ImageDetails imageDetails = getImageForCard(index);
    final double baseFontSize = (gridItemHeight * 0.35) * _fontSizeFactor;

    // Category colors from Image 2
    Color categoryColor;
    if (index < 70)
      categoryColor = const Color(0xFF006400);
    else if (index < 80)
      categoryColor = const Color(0xFF8B0000);
    else
      categoryColor = const Color(0xFF00008B);

    return Container(
      padding: const EdgeInsets.all(1),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: categoryColor, width: 1.5),
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 4,
                offset: const Offset(0, 2)),
          ],
        ),
        child: Card(
          elevation: 0,
          color: Colors.transparent,
          margin: EdgeInsets.zero,
          child: answeredQuestions[index]
              ? Container(
                  padding: const EdgeInsets.all(0),
                  child: Image.asset(
                    imageDetails.imagePath,
                    fit: BoxFit.contain,
                    height: gridItemHeight * imageDetails.heightPercentage,
                  ),
                )
              : GestureDetector(
                  onTap: () async {
                    if (question == null) return;
                    final playerMarks = await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => QuestionPage(
                          question: question,
                          playerCount: widget.playerCount,
                          timerDuration: widget.timerDuration,
                          onSubmitMarks: (playerMarks) {
                            updateScores(playerMarks, question.points, index);
                            Navigator.pop(context);
                          },
                        ),
                      ),
                    );
                    if (playerMarks != null) {
                      updateScores(playerMarks, question.points, index);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(2.0),
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Center(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                '${index + 1}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: question == null
                                      ? Colors.grey
                                      : categoryColor,
                                  fontSize: baseFontSize,
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (question == null)
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              'Empty',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: baseFontSize * 0.4,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  Widget buildScoreboard(Size screenSize, double baseFontSize) {
    final int totalMarked = correctAnswers + incorrectAnswers;
    final double percent =
        totalMarked > 0 ? (correctAnswers / totalMarked * 100) : 0.0;
    final String recordText =
        "$correctAnswers/$totalMarked (${percent.toStringAsFixed(1)}%)";

    return Container(
      height: 60,
      width: screenSize.width * _gridWidthPercent,
      decoration: const BoxDecoration(
        color: Color(0xFF450E4E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 12),
            child: Text(
              "SCORE",
              style: TextStyle(
                  color: Colors.yellow,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                  letterSpacing: 1.0),
            ),
          ),
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              itemCount: widget.playerCount,
              separatorBuilder: (context, index) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        "P${index + 1}",
                        style:
                            const TextStyle(color: Colors.white70, fontSize: 8),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        scores[index].toString(),
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          if (widget.playerCount == 1)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text(
                recordText,
                style: const TextStyle(
                    color: Colors.yellow,
                    fontSize: 11,
                    fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
    );
  }

  Widget buildFooter(Size screenSize, double baseFontSize) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 20),
      decoration: BoxDecoration(
        color: const Color(0xFF450E4E),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: const Text(
        'Developed by FIFMI Middle East (EGEA and Media)',
        style: TextStyle(
          fontSize: 11,
          color: Colors.white,
          fontWeight: FontWeight.normal,
          fontStyle: FontStyle.italic,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  ImageDetails getImageForCard(int index) {
    if (index % 4 == 0) {
      return ImageDetails('assets/logo2.png', 0.92);
    } else if (index % 4 == 1) {
      return ImageDetails('assets/image1.png', 0.6);
    } else if (index % 4 == 2) {
      return ImageDetails('assets/image2_3.png', 0.6);
    } else {
      return ImageDetails('assets/baba_flags3.png', 0.6);
    }
  }

  void _showWinnerDialog() {
    if (scoreHistory.isEmpty || scoreHistory[0].length <= 1) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('No Data'),
          content: const Text('No questions have been answered yet!'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'))
          ],
        ),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
        child: WebRankHistoryChart(
          playerCount: widget.playerCount,
          scoreHistory: scoreHistory,
          onBackToLobby: () => Navigator.pop(context),
        ),
      ),
    );
  }
}

class ImageDetails {
  final String imagePath;
  final double heightPercentage;

  ImageDetails(this.imagePath, this.heightPercentage);
}
