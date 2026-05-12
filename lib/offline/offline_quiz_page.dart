import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

import 'package:uuid/uuid.dart';

import '../models/local_models.dart';
import '../mcq_question.dart';
import '../picture_question.dart';
import '../structured_question.dart';
import '../question_page.dart';
import 'local_db_service.dart';
import 'local_db_service_web.dart';
import 'offline_rank_history_chart.dart';

// Allow mouse dragging for horizontal scrolling on web
class MyCustomScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
      };
}

class OfflineQuizPage extends StatefulWidget {
  final String gameId;

  const OfflineQuizPage({
    super.key,
    required this.gameId,
  });

  @override
  State<OfflineQuizPage> createState() => _OfflineQuizPageState();
}

class _OfflineQuizPageState extends State<OfflineQuizPage>
    with TickerProviderStateMixin {
  final GlobalKey<OfflineRankHistoryChartState> _chartKey =
      GlobalKey<OfflineRankHistoryChartState>();

  // --- DATABASE STATE ---
  List<GamePlayer> players = [];
  List<Question> allRawQuestions = [];
  List<MCQQuestion> mcqPool = [];
  List<PictureQuestion> picPool = [];
  List<StructuredQuestion> structPool = [];
  List<dynamic> answeredHistory = [];

  // --- UI STATE ---
  bool isLoading = true;
  String? errorMessage;
  String? errorStackTrace;

  // Grid tracking
  List<bool> gridStatus = List<bool>.filled(100, false);
  Map<String, int> playerPoints = {};
  int currentPlayerIndex = 0;

  // Stats for the debug bar
  // Stats tracking
  int totalCount = 0;
  int approvedCount = 0;
  int mcqCount = 0;
  int picCount = 0;
  int structCount = 0;

  // Grid Adjustments
  double gridWidthPercent = 1.0;
  double gridHeightPercent = 1.0;
  double fontSizeFactor = 0.75;

  @override
  void initState() {
    super.initState();
    _initializeGame();
  }

  @override
  void dispose() {
    super.dispose();
  }

  // --- CORE LOGIC: THE REVAMPED INITIALIZATION ---

  Future<void> _initializeGame() async {
    debugPrint('OfflineQuiz: [START] Full Revamp Initialization');
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      debugPrint('Checkpoint 1: Loading Players...');
      await _loadPlayers();

      debugPrint('Checkpoint 2: Loading Questions...');
      await _loadQuestions();

      debugPrint('Checkpoint 3: Loading Progress...');
      await _loadProgress();

      debugPrint('Checkpoint 4: Grid Sync...');
      debugPrint('Checkpoint 5: Initialization Complete');

      debugPrint('OfflineQuiz: [SUCCESS] All data loaded correctly');
    } catch (e, stack) {
      debugPrint('OfflineQuiz: [CRITICAL ERROR] $e');
      debugPrint(stack.toString());
      if (mounted) {
        setState(() {
          errorMessage = e.toString();
          errorStackTrace = stack.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  Future<void> _loadPlayers() async {
    final List<GamePlayer> loadedPlayers = [];

    if (kIsWeb) {
      final maps = await WebDatabaseHelper.getAll('game_players');
      for (final m in maps) {
        final p = GamePlayer.fromMap(m);
        if (p.gameId == widget.gameId) loadedPlayers.add(p);
      }
    } else {
      final db = await LocalDbService.database;
      final maps = await db.query('game_players',
          where: 'game_id = ?', whereArgs: [widget.gameId]);
      for (final m in maps) {
        loadedPlayers.add(GamePlayer.fromMap(m));
      }
    }

    if (loadedPlayers.isEmpty) {
      debugPrint(
          'OfflineQuiz: No players found for gameId, using default pool');
      // Try to load any players if specific ones fail
      if (kIsWeb) {
        final maps = await WebDatabaseHelper.getAll('game_players');
        for (final m in maps) loadedPlayers.add(GamePlayer.fromMap(m));
      } else {
        final db = await LocalDbService.database;
        final maps = await db.query('game_players');
        for (final m in maps) loadedPlayers.add(GamePlayer.fromMap(m));
      }
    }

    loadedPlayers.sort((a, b) {
      int cmp = a.joinedAt.compareTo(b.joinedAt);
      if (cmp != 0) return cmp;
      return a.displayName.compareTo(b.displayName);
    });
    players = List<GamePlayer>.from(loadedPlayers);
    playerPoints = {for (var p in players) p.displayName: 0};
    debugPrint('OfflineQuiz: Loaded ${players.length} players');
  }

  Future<void> _loadQuestions() async {
    final List<Question> rawPool = [];

    if (kIsWeb) {
      final maps = await WebDatabaseHelper.getAll('questions');
      for (final m in maps) {
        try {
          rawPool.add(Question.fromMap(m));
        } catch (_) {}
      }
    } else {
      final db = await LocalDbService.database;
      final maps = await db.query('questions');
      for (final m in maps) {
        try {
          rawPool.add(Question.fromMap(m));
        } catch (_) {}
      }
    }

    allRawQuestions = rawPool;
    totalCount = rawPool.length;

    // Filter by type and approval
    final List<Question> mcqItems = [];
    final List<Question> picItems = [];
    final List<Question> structItems = [];

    for (final q in rawPool) {
      if (q.approved != 1 || !q.isValid) continue;

      final type = q.questionType.toLowerCase();
      if (type.contains('mcq') || type.contains('multiple')) {
        mcqItems.add(q);
      } else if (type.contains('picture') || type.contains('image')) {
        picItems.add(q);
      } else if (type.contains('struct')) {
        structItems.add(q);
      }
    }

    approvedCount = mcqItems.length + picItems.length + structItems.length;
    mcqCount = mcqItems.length;
    picCount = picItems.length;
    structCount = structItems.length;

    // Deterministic Shuffle
    final seed = widget.gameId.hashCode;
    mcqItems.shuffle(Random(seed));
    picItems.shuffle(Random(seed + 1));
    structItems.shuffle(Random(seed + 2));

    // Convert to specialized models
    mcqPool = [];
    for (final q in mcqItems.take(70)) {
      try {
        mcqPool.add(MCQQuestion.fromJson(q.toMap()));
      } catch (e) {
        debugPrint('OfflineQuiz: Skipping malformed MCQ question ${q.id}: $e');
      }
    }

    picPool = [];
    for (final q in picItems.take(10)) {
      try {
        picPool.add(PictureQuestion.fromJson(q.toMap()));
      } catch (e) {
        debugPrint('OfflineQuiz: Skipping malformed PIC question ${q.id}: $e');
      }
    }

    structPool = [];
    for (final q in structItems.take(20)) {
      try {
        structPool.add(StructuredQuestion.fromJson(q.toMap()));
      } catch (e) {
        debugPrint(
            'OfflineQuiz: Skipping malformed STRUCT question ${q.id}: $e');
      }
    }

    debugPrint(
        'OfflineQuiz: Pools ready - MCQ:${mcqPool.length}, PIC:${picPool.length}, STRUCT:${structPool.length}');

    if (mcqPool.isEmpty && picPool.isEmpty && structPool.isEmpty) {
      throw 'No approved questions found in the database. Please check your data import.';
    }
  }

  Future<void> _loadProgress() async {
    final List<Answer> loadedAnswers = [];

    if (kIsWeb) {
      final maps = await WebDatabaseHelper.getAll('answers');
      for (final m in maps) {
        final a = Answer.fromMap(m);
        if (a.gameId == widget.gameId) loadedAnswers.add(a);
      }
    } else {
      final db = await LocalDbService.database;
      final maps = await db
          .query('answers', where: 'game_id = ?', whereArgs: [widget.gameId]);
      for (final m in maps) {
        loadedAnswers.add(Answer.fromMap(m));
      }
    }

    answeredHistory = loadedAnswers;

    // Map history to the grid
    _recalculateProgress(loadedAnswers);
  }

  void _recalculateProgress(List<dynamic> history) {
    gridStatus = List<bool>.filled(100, false);
    playerPoints = {for (var p in players) p.displayName: 0};

    // Identify which question ID belongs to which grid index
    final Map<String, int> idToIndex = {};
    for (int i = 0; i < mcqPool.length; i++) idToIndex[_findRawIdForMcq(i)] = i;
    for (int i = 0; i < picPool.length; i++)
      idToIndex[_findRawIdForPic(i)] = 70 + i;
    for (int i = 0; i < structPool.length; i++)
      idToIndex[_findRawIdForStruct(i)] = 80 + i;

    for (final rawAns in history) {
      final ans = rawAns as Answer;
      final idx = idToIndex[ans.questionId];
      if (idx != null) {
        gridStatus[idx] = true;

        // Find player to attribute points
        final player = players.firstWhere((p) => p.userId == ans.userId,
            orElse: () => players.isNotEmpty
                ? players[0]
                : GamePlayer(
                    id: '',
                    gameId: '',
                    userId: '',
                    score: 0,
                    joinedAt: '',
                    displayName: 'Unknown'));

        if (player.displayName != 'Unknown') {
          // Find points for this specific question
          int pts = 2;
          for (final q in allRawQuestions) {
            if (q.id == ans.questionId) {
              pts = q.points;
              break;
            }
          }

          if (ans.isCorrect == 1) {
            playerPoints[player.displayName] =
                (playerPoints[player.displayName] ?? 0) + pts;
          } else {
            // Deduct points for incorrect answers
            playerPoints[player.displayName] =
                (playerPoints[player.displayName] ?? 0) - pts;
          }
        }
      }
    }

    if (mounted) setState(() {});
  }

  String _findRawIdForMcq(int poolIndex) {
    // We need to find the raw ID from the shuffled items
    // Re-calculating correctly:
    final mcqItems = allRawQuestions.where((q) {
      final t = q.questionType.toLowerCase();
      return (t.contains('mcq') || t.contains('multiple')) &&
          q.approved == 1 &&
          q.isValid;
    }).toList();
    mcqItems.shuffle(Random(widget.gameId.hashCode));
    return mcqItems[poolIndex].id;
  }

  String _findRawIdForPic(int poolIndex) {
    final items = allRawQuestions.where((q) {
      final t = q.questionType.toLowerCase();
      return (t.contains('picture') || t.contains('image')) &&
          q.approved == 1 &&
          q.isValid;
    }).toList();
    items.shuffle(Random(widget.gameId.hashCode + 1));
    return items[poolIndex].id;
  }

  String _findRawIdForStruct(int poolIndex) {
    final items = allRawQuestions.where((q) {
      final t = q.questionType.toLowerCase();
      return t.contains('struct') && q.approved == 1 && q.isValid;
    }).toList();
    items.shuffle(Random(widget.gameId.hashCode + 2));
    return items[poolIndex].id;
  }

  // --- UI BUILDERS ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3E5F5),
      appBar: _buildAppBar(),
      body: SafeArea(
        child: Stack(
          children: [
            if (!isLoading && errorMessage == null) _buildMainContent(),
            if (isLoading) _buildLoadingOverlay(),
            if (errorMessage != null) _buildErrorOverlay(),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: const Color(0xFF6A1B9A),
      elevation: 0,
      toolbarHeight: 56,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.white),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: Row(
        children: [
          Image.asset(
            'assets/baba100new.jpg',
            height: 35,
            fit: BoxFit.contain,
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Legacy Quiz',
                  style: TextStyle(
                      color: Color(0xFFFFD600),
                      fontWeight: FontWeight.bold,
                      fontSize: 16)),
              Text('Offline Mode',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.8), fontSize: 9)),
            ],
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.emoji_events, color: Colors.yellow, size: 22),
          onPressed: _showWinnerDialog,
        ),
        IconButton(
          icon: const Icon(Icons.close, color: Colors.white, size: 22),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  Widget _buildMainContent() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        _buildLegend(),
        _buildControllers(),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Center(
                child: _buildGrid(constraints.maxWidth, constraints.maxHeight),
              );
            },
          ),
        ),
        _buildScoreFooter(),
        _buildDevFooter(),
      ],
    );
  }

  Widget _buildLegend() {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildLegendItem('1-70 MCQ', const Color(0xFF006400)),
          _buildLegendItem('71-80 Picture', const Color(0xFF8B0000)),
          _buildLegendItem('81-100 Structured', const Color(0xFF00008B)),
        ],
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color, width: 1.2),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 9, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildGrid(double maxWidth, double maxHeight) {
    const double spacing = 1.5;

    // Apply user adjustments
    final double adjustedWidth = maxWidth * gridWidthPercent;
    final double adjustedHeight = maxHeight * gridHeightPercent;

    final double cellWidth = adjustedWidth / 10;
    final double cellHeight = adjustedHeight / 10;
    final double aspectRatio =
        (cellHeight > 0) ? (cellWidth / cellHeight) : 1.0;

    // Calculate an adjustable font size
    final double baseFontSize = cellHeight * 0.25;
    final double fontSize = baseFontSize * fontSizeFactor;

    return Container(
      width: adjustedWidth,
      height: adjustedHeight,
      padding: const EdgeInsets.all(2.0),
      child: GridView.builder(
        itemCount: 100,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 10,
          childAspectRatio: aspectRatio,
          crossAxisSpacing: spacing,
          mainAxisSpacing: spacing,
        ),
        itemBuilder: (context, index) {
          final answered = gridStatus[index];
          final categoryColor = _getCategoryColor(index);
          final question = _getQuestionForIndex(index);

          return GestureDetector(
            onTap: (answered || question == null)
                ? null
                : () => _onSlotTapped(index, question),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: categoryColor, width: 1.5),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 2,
                      offset: const Offset(0, 1)),
                ],
              ),
              child: answered
                  ? Padding(
                      padding: const EdgeInsets.all(2.0),
                      child: Image.asset(_getImagePath(index),
                          fit: BoxFit.contain),
                    )
                  : Center(
                      child: Text(
                        '${index + 1}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: categoryColor,
                          fontSize: fontSize, // Use adjustable font size
                        ),
                      ),
                    ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildControllers() {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      color: Colors.white.withOpacity(0.9),
      child: Row(
        children: [
          _buildSlider('W', gridWidthPercent,
              (v) => setState(() => gridWidthPercent = v)),
          _buildSlider('H', gridHeightPercent,
              (v) => setState(() => gridHeightPercent = v)),
          _buildSlider(
              'F', fontSizeFactor, (v) => setState(() => fontSizeFactor = v),
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

  Widget _buildScoreFooter() {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: const Color(0xFF311B92),
      child: Row(
        children: [
          const Text('SCORE',
              style: TextStyle(
                  color: Color(0xFFFFD600),
                  fontWeight: FontWeight.bold,
                  fontSize: 13)),
          const SizedBox(width: 8),
          Expanded(
            child: ScrollConfiguration(
              behavior: MyCustomScrollBehavior(),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const AlwaysScrollableScrollPhysics(),
                child: Row(
                  children: players.asMap().entries.map((e) {
                    final p = e.value;
                    return Container(
                      width: 80, // FORCED WIDTH
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                          color: Colors.white10,
                          borderRadius: BorderRadius.circular(3)),
                      child: Text(
                        '${p.displayName}: ${playerPoints[p.displayName] ?? 0}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDevFooter() {
    return Container(
      height: 24,
      color: const Color(0xFF311B92),
      child: const Center(
        child: Text('Developed by FIFMI Middle East',
            style: TextStyle(
                fontSize: 8,
                color: Colors.white54,
                fontStyle: FontStyle.italic)),
      ),
    );
  }

  Widget _buildLoadingOverlay() {
    return Container(
      color: Colors.white.withOpacity(0.8),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.purple),
            SizedBox(height: 10),
            Text('Syncing Offline Data...',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.purple,
                    fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorOverlay() {
    return Container(
      color: Colors.white.withOpacity(0.95),
      padding: const EdgeInsets.all(20),
      child: Align(
        alignment: Alignment.topCenter,
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(top: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 50),
              const SizedBox(height: 15),
              const Text('DATABASE SYNC ERROR',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.red)),
              const SizedBox(height: 10),
              Text(errorMessage ?? 'Unknown Error',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              if (errorStackTrace != null) ...[
                const SizedBox(height: 20),
                const Text('TECHNICAL DETAILS:',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey)),
                Container(
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(top: 5),
                  color: Colors.grey.shade100,
                  child: Text(errorStackTrace!,
                      style: const TextStyle(
                          fontSize: 8, fontFamily: 'monospace')),
                ),
              ],
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red, foregroundColor: Colors.white),
                child: const Text('Go Back'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- ACTIONS ---

  void _onSlotTapped(int index, dynamic question) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => QuestionPage(
          question: question,
          playerCount: players.length,
          timerDuration: 60,
          players: players,
          playerPoints: playerPoints,
          onSubmitMarks: (marks) => _submitMarks(index, marks, question),
        ),
      ),
    );
  }

  Future<void> _submitMarks(int index, List<int> marks, dynamic q) async {
    // Find the raw Question ID
    String qId = '';
    if (index < 70)
      qId = _findRawIdForMcq(index);
    else if (index < 80)
      qId = _findRawIdForPic(index - 70);
    else
      qId = _findRawIdForStruct(index - 80);

    final now = DateTime.now().toIso8601String();

    for (int i = 0; i < players.length && i < marks.length; i++) {
      if (marks[i] == 0) continue;

      final player = players[i];
      final answer = Answer(
        id: const Uuid().v4(),
        gameId: widget.gameId,
        questionId: qId,
        userId: player.userId,
        answer: (marks[i] == 1) ? 'Correct' : 'Incorrect',
        isCorrect: (marks[i] == 1) ? 1 : 0,
        answeredAt: now,
      );

      if (kIsWeb) {
        await WebDatabaseHelper.insert('answers', answer.id, answer.toMap());
      } else {
        final db = await LocalDbService.database;
        await db.insert('answers', answer.toMap());
      }
    }

    // Refresh everything
    await _loadProgress();

    if (mounted) Navigator.of(context).pop();
  }

  // --- HELPERS ---

  dynamic _getQuestionForIndex(int index) {
    if (index < 70) return mcqPool.length > index ? mcqPool[index] : null;
    if (index < 80)
      return picPool.length > (index - 70) ? picPool[index - 70] : null;
    return structPool.length > (index - 80) ? structPool[index - 80] : null;
  }

  Color _getCategoryColor(int index) {
    if (index < 70) return const Color(0xFF006400);
    if (index < 80) return const Color(0xFF8B0000);
    return const Color(0xFF00008B);
  }

  String _getImagePath(int index) {
    if (index % 4 == 0) return 'assets/logo2.png';
    if (index % 4 == 1) return 'assets/image1.png';
    if (index % 4 == 2) return 'assets/image2_3.png';
    return 'assets/baba_flags3.png';
  }

  Future<void> _showWinnerDialog() async {
    if (answeredHistory.isEmpty) {
      _showSimpleWinnerDialog();
      return;
    }

    // Identify race questions
    List<String> qIds = answeredHistory
        .cast<Answer>()
        .map((a) => a.questionId)
        .toSet()
        .toList();
    List<Question> raceQuestions = [];
    for (final id in qIds) {
      for (final q in allRawQuestions) {
        if (q.id == id) {
          raceQuestions.add(q);
          break;
        }
      }
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: Container(
              width: MediaQuery.of(context).size.width * 0.9,
              height: MediaQuery.of(context).size.height * 0.92,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFEAC7EF), Color(0xFF450E4E)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(40),
                border: Border.all(color: Colors.yellow, width: 4),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.5),
                      blurRadius: 20,
                      spreadRadius: 5),
                ],
              ),
              child: Column(
                children: [
                  Expanded(
                    child: OfflineRankHistoryChart(
                      key: _chartKey,
                      gameId: widget.gameId,
                      questions: raceQuestions,
                      players: players,
                      answers: List<Answer>.from(answeredHistory),
                      onBackToLobby: () {
                        Navigator.of(context).pop();
                        Navigator.of(context).pop();
                      },
                      onWatchAgain: () => _chartKey.currentState?.startRace(),
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

  void _showSimpleWinnerDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Quiz Status'),
        content: const Text('No questions have been answered yet!'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('OK'))
        ],
      ),
    );
  }
}
