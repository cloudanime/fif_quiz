import 'dart:async';
import 'package:flutter/material.dart';
import 'package:confetti/confetti.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'services/quiz_supabase_service.dart';
import 'models/supabase_models.dart';

import 'dart:math';
import 'rank_history_chart.dart';
import 'mode_selection_page.dart';

class OnlineQuizPage extends StatefulWidget {
  final String gameId;
  final int questionCount;
  final int timerDuration;
  final bool isHost;
  final bool isTeamMode;

  const OnlineQuizPage({
    super.key,
    required this.gameId,
    required this.questionCount,
    this.timerDuration = 60,
    this.isHost = false,
    this.isTeamMode = false,
  });

  @override
  State<OnlineQuizPage> createState() => _OnlineQuizPageState();
}

class _OnlineQuizPageState extends State<OnlineQuizPage>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  final GlobalKey<RankHistoryChartState> _chartKey =
      GlobalKey<RankHistoryChartState>();
  final SupabaseQuizService _quizService = SupabaseQuizService();
  final supabase = Supabase.instance.client;

  bool _isLoading = true;
  bool _hasAnswered = false;
  bool _revealAnswer = false;
  bool _isGameOverShown = false;
  late ConfettiController _confettiControllerTop;
  late ConfettiController _confettiControllerBottom;
  List<GamePlayerModel> _leaderboard = [];
  List<GamePlayerModel> _allPlayers = [];
  RealtimeChannel? _gameChannel;

  Set<int> _answeredIndices = {};
  int? _activeQuestionIndex;
  int? _syncedQuestionIndex;
  final Map<String, int> _tempMarks = {};
  final Set<String> _answeredThisRound = {};
  String? _selectedOption;
  int? _lastScoredIndex;
  int? _celebratedIndex;
  int? _sessionLimit;
  int _timeLeft = 60;
  Timer? _countdownTimer;
  bool _isQuickMatch = false;

  // Grid Adjustments
  double _gridWidthPercent = 1.0;
  double _gridHeightPercent = 1.0;
  double _fontSizeFactor = 0.75;
  final TextEditingController _answerController = TextEditingController();
  bool _canReveal = false;

  String? _adminId;
  final Map<String, List<String>> _shuffledOptionsMap = {};
  Map<String, int> _playerCorrectCounts = {};
  Map<String, int> _playerTotalAnswered = {};
  Map<String, String> _playerAnswersThisRound = {};

  String _stripPrefix(String? opt) {
    if (opt == null || opt.isEmpty) return "";
    if (opt.length >= 3 && opt[1] == '.' && opt[2] == ' ') {
      return opt.substring(3);
    }
    return opt;
  }

  List<String> _getShuffledOptions(QuestionModel q) {
    if (_shuffledOptionsMap.containsKey(q.id)) {
      return _shuffledOptionsMap[q.id]!;
    }
    List<String> raw = (q.options ?? []).map((o) => _stripPrefix(o)).toList();
    final random = Random(q.id.hashCode);
    raw.shuffle(random);
    _shuffledOptionsMap[q.id] = raw;
    return raw;
  }

  List<QuestionModel?> _allQuestionsInOrder = [];
  List<QuestionModel?> _mcqQuestions = [];
  List<QuestionModel?> _pictureQuestions = [];
  List<QuestionModel?> _structuredQuestions = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Initialize confetti controller with a longer duration for burst effect
    _confettiControllerTop =
        ConfettiController(duration: const Duration(milliseconds: 1500));
    _confettiControllerBottom =
        ConfettiController(duration: const Duration(milliseconds: 1500));

    _loadGameData();
    _listenToGame();
    _startHeartbeatSync();
    _startInactivityTimer();
  }

  // Method to trigger confetti burst
  void _triggerConfettiBurst() {
    _confettiControllerTop.stop();
    _confettiControllerBottom.stop();
    _confettiControllerTop.play();
    _confettiControllerBottom.play();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _gameChannel?.unsubscribe();
      _countdownTimer?.cancel();
    } else if (state == AppLifecycleState.resumed) {
      _listenToGame();
      _syncStatusFromDb();
    }
  }

  Timer? _inactivityTimer;
  DateTime _lastRoomActivity = DateTime.now();
  bool _isExiting = false;

  void _startInactivityTimer() {
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(const Duration(minutes: 5), () {
      if (mounted) {
        _exitGame();
      }
    });
  }

  void _resetInactivityTimer() {
    _lastRoomActivity = DateTime.now();
    if (_inactivityTimer != null) {
      _startInactivityTimer();
    }
  }

  Future<void> _exitGame() async {
    if (_isExiting) return;
    _isExiting = true;
    _heartbeatTimer?.cancel();
    _inactivityTimer?.cancel();

    try {
      if (widget.isHost) {
        await supabase
            .from('games')
            .update({'status': 'aborted'})
            .eq('id', widget.gameId)
            .timeout(
              const Duration(seconds: 2),
              onTimeout: () => debugPrint("Exit Quiz: Abort timed out"),
            );
      }
    } catch (e) {
      debugPrint("Error exiting quiz: $e");
    } finally {
      if (mounted) {
        ScaffoldMessenger.of(context).removeCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("You were removed from the room due to inactivity."),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const ModeSelectionPage()),
          (route) => false,
        );
      }
    }
  }

  Timer? _heartbeatTimer;

  void _startHeartbeatSync() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (mounted) {
        if (DateTime.now().difference(_lastRoomActivity).inMinutes >= 5) {
          debugPrint("Quiz: Room inactivity detected. Exiting.");
          _exitGame();
          return;
        }
        _syncStatusFromDb();
      }
    });
  }

  Future<void> _syncStatusFromDb() async {
    try {
      final res = await supabase
          .from('games')
          .select('status, reveal_answer, answered_questions')
          .eq('id', widget.gameId)
          .single();
      final status = res['status']?.toString() ?? "";
      final reveal = res['reveal_answer'] as bool? ?? false;
      final answered = res['answered_questions'] as List<dynamic>? ?? [];

      _handleStatusUpdate(status, reveal, answered: answered.cast<int>());
    } catch (e) {
      debugPrint("Heartbeat sync error: $e");
    }
  }

  void _handleStatusUpdate(String status, bool reveal, {List<int>? answered}) {
    if (answered != null) {
      _answeredIndices = answered.toSet();
    }

    if (status.startsWith('revealed:')) {
      try {
        final activeIndex = int.parse(status.split(':')[1]);
        if (activeIndex != _activeQuestionIndex) {
          if (_activeQuestionIndex != null) {
            _scoreMyself(_activeQuestionIndex!);
          }
          setState(() {
            _activeQuestionIndex = activeIndex;
            _revealAnswer = false;
            _hasAnswered = false;
            _selectedOption = null;
            _answerController.clear();
            _timeLeft = widget.timerDuration;
            _answeredThisRound.clear();
            _playerAnswersThisRound.clear();
            _tempMarks.clear();
            _canReveal = false;
            _leaderboard = _leaderboard
                .map((p) => GamePlayerModel(
                      id: p.id,
                      gameId: p.gameId,
                      userId: p.userId,
                      score: p.score,
                      isReady: p.isReady,
                      joinedAt: p.joinedAt,
                      username: p.username,
                      displayName: p.displayName,
                      lastSelection: null,
                    ))
                .toList();
          });
          _startCountdown();
        }
      } catch (_) {}
    } else if ((status == 'finished' || status == 'winner_review') &&
        !_isGameOverShown) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_isGameOverShown) _showGameOverDialog();
      });
    } else if (status == 'aborted') {
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Host has left. Game aborted.")));
            Navigator.of(context).pop();
          }
        });
      }
    }

    if (reveal != _revealAnswer) {
      setState(() {
        _revealAnswer = reveal;
        if (reveal) {
          _autoFillMarks();
          _countdownTimer?.cancel();
          _timeLeft = 0;

          if (_activeQuestionIndex != null) {
            _scoreMyself(_activeQuestionIndex!);
          }

          if (widget.isHost && _isQuickMatch) {
            Future.delayed(const Duration(seconds: 2), () {
              if (mounted && _revealAnswer) {
                _nextQuestion();
              }
            });
          }
        }
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _countdownTimer?.cancel();
    _heartbeatTimer?.cancel();
    _confettiControllerTop.dispose();
    _confettiControllerBottom.dispose();
    _inactivityTimer?.cancel();
    _gameChannel?.unsubscribe();
    _answerController.dispose();
    super.dispose();
  }

  Future<void> _updateLeaderboard() async {
    final playersData = await supabase
        .from('game_players')
        .select('*, users(username)')
        .eq('game_id', widget.gameId);

    final List<GamePlayerModel> allPlayers = (playersData as List? ?? [])
        .map((json) => GamePlayerModel.fromJson(json))
        .toList();
    _allPlayers = allPlayers;

    final List<AnswerModel> answersList =
        await _quizService.fetchGameAnswers(widget.gameId);
    final Map<String, int> newCorrect = {};
    final Map<String, int> newTotal = {};
    final Map<String, String> currentAnswers = {};

    for (var ans in answersList) {
      newTotal[ans.userId] = (newTotal[ans.userId] ?? 0) + 1;
      if (ans.isCorrect) {
        newCorrect[ans.userId] = (newCorrect[ans.userId] ?? 0) + 1;
      }

      if (_activeQuestionIndex != null) {
        final q = _getQuestionForIndex(_activeQuestionIndex!);
        if (q != null && ans.questionId == q.id) {
          currentAnswers[ans.userId] = ans.answer;
        }
      }
    }

    if (mounted) {
      setState(() {
        if (widget.isTeamMode) {
          final Map<String, GamePlayerModel> teamAggregates = {};

          for (var p in allPlayers) {
            final tName = p.teamName ?? 'No Team';
            if (!teamAggregates.containsKey(tName)) {
              teamAggregates[tName] = GamePlayerModel(
                id: p.teamCode ?? tName,
                gameId: p.gameId,
                userId: p.userId,
                score: 0,
                isReady: true,
                joinedAt: p.joinedAt,
                displayName: tName,
                teamName: tName,
                teamCode: p.teamCode,
              );
            }

            final currentTeam = teamAggregates[tName]!;
            teamAggregates[tName] = GamePlayerModel(
              id: currentTeam.id,
              gameId: currentTeam.gameId,
              userId: currentTeam.userId,
              score: currentTeam.score + p.score,
              isReady: true,
              joinedAt: currentTeam.joinedAt,
              displayName: currentTeam.displayName,
              teamName: currentTeam.teamName,
              teamCode: currentTeam.teamCode,
            );

            final teamKey = tName;
            newTotal[teamKey] =
                (newTotal[teamKey] ?? 0) + (newTotal[p.userId] ?? 0);
            newCorrect[teamKey] =
                (newCorrect[teamKey] ?? 0) + (newCorrect[p.userId] ?? 0);

            if (currentAnswers.containsKey(p.userId)) {
              currentAnswers[teamKey] = (currentAnswers[teamKey] == null)
                  ? currentAnswers[p.userId]!
                  : "${currentAnswers[teamKey]}, ${currentAnswers[p.userId]}";
            }
          }

          _leaderboard = teamAggregates.values.toList();
          _leaderboard.sort((a, b) => b.score.compareTo(a.score));
        } else {
          _leaderboard = allPlayers;
          _leaderboard.sort((a, b) => b.score.compareTo(a.score));
        }

        _playerCorrectCounts = newCorrect;
        _playerTotalAnswered = newTotal;
        _playerAnswersThisRound = currentAnswers;

        _answeredThisRound.clear();
        final question = (_activeQuestionIndex != null)
            ? _getQuestionForIndex(_activeQuestionIndex!)
            : null;
        if (question != null) {
          for (var p in allPlayers) {
            final rawSelection = p.lastSelection;
            if (rawSelection != null && rawSelection.contains(':')) {
              final parts = rawSelection.split(':');
              if (parts[0] == question.id && parts[1].isNotEmpty) {
                final teamKey =
                    widget.isTeamMode ? (p.teamName ?? 'No Team') : p.id;
                _answeredThisRound.add(teamKey);
              }
            }
          }
        }

        if (widget.isHost &&
            !_revealAnswer &&
            _activeQuestionIndex != null &&
            allPlayers.isNotEmpty &&
            question != null) {
          final allAnswered = allPlayers.every((p) {
            final raw = p.lastSelection;
            if (raw == null || !raw.contains(':')) return false;
            final parts = raw.split(':');
            return parts[0] == question.id && parts[1].isNotEmpty;
          });

          if (allAnswered && !_canReveal) {
            _canReveal = true;
          }
        }

        if (_revealAnswer) {
          _autoFillMarks();
        }
      });
    }
  }

  void _autoFillMarks() {
    if (_activeQuestionIndex == null) return;
    final q = _getQuestionForIndex(_activeQuestionIndex!);
    if (q == null || q.questionType != 'multiple_choice') return;

    final correctKey = q.answer?.toUpperCase() ?? "";
    final correctIndex = "ABCDE".indexOf(correctKey);

    String correctText = (q.answer ?? "").trim().toLowerCase();
    if (q.options != null &&
        correctIndex != -1 &&
        correctIndex < q.options!.length) {
      correctText = _stripPrefix(q.options![correctIndex]).trim().toLowerCase();
    }

    setState(() {
      for (var p in _leaderboard) {
        final rawSelection = p.lastSelection;
        String? playerPick;
        if (rawSelection != null && rawSelection.contains(':')) {
          final parts = rawSelection.split(':');
          if (parts[0] == q.id) playerPick = parts[1];
        }

        if (playerPick == null || playerPick.isEmpty) {
          if (!_tempMarks.containsKey(p.userId) ||
              _tempMarks[p.userId] == null) {
            _tempMarks[p.userId] = 0;
          }
          continue;
        }

        final strippedPick = _stripPrefix(playerPick).trim().toLowerCase();

        // Use strict matching for Multiple Choice to avoid false positives
        final isCorrect = strippedPick == correctText;

        _tempMarks[p.userId] = isCorrect ? 1 : -1;
        if (isCorrect) {
          _celebratedIndex = _activeQuestionIndex;
        }
      }
    });
  }

  Future<void> _loadGameData() async {
    try {
      final game = await supabase
          .from('games')
          .select(
              'admin_id, question_ids, question_count, status, answered_questions')
          .eq('id', widget.gameId)
          .single();
      final ids = game['question_ids'] as List<dynamic>? ?? [];
      _sessionLimit = game['question_count'] as int? ?? 100;
      final answered = game['answered_questions'] as List<dynamic>? ?? [];

      final questions = await _quizService.fetchQuestionsByIds(ids);

      final players = await supabase
          .from('game_players')
          .select('*, users(username)')
          .eq('game_id', widget.gameId)
          .order('score', ascending: false);

      setState(() {
        _adminId = game['admin_id'];
        _allQuestionsInOrder = questions;
        _mcqQuestions = questions.take(70).toList();
        _pictureQuestions = questions.skip(70).take(10).toList();
        _structuredQuestions = questions.skip(80).take(20).toList();
        _leaderboard = (players as List? ?? [])
            .map((json) => GamePlayerModel.fromJson(json))
            .toList();
        _isQuickMatch = _sessionLimit == 15;
        _answeredIndices = answered.cast<int>().toSet();
      });

      final status = game['status']?.toString() ?? "";
      if (status.startsWith('revealed:')) {
        try {
          _activeQuestionIndex = int.parse(status.split(':')[1]);
          _timeLeft = widget.timerDuration;
          _startCountdown();
        } catch (_) {}
      }

      if (_isQuickMatch && widget.isHost) {
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted && _activeQuestionIndex == null) {
            _revealQuestion(0);
          }
        });
      }
      setState(() {
        _isLoading = false;
      });
      _updateLeaderboard();
    } catch (e) {
      debugPrint("Error loading game data: $e");
    }
  }

  QuestionModel? _getQuestionForIndex(int index) {
    if (index >= 0 && index < _allQuestionsInOrder.length) {
      return _allQuestionsInOrder[index];
    }
    return null;
  }

  String? _getHostName() {
    if (_adminId == null) return null;
    try {
      final host = _leaderboard.firstWhere((p) => p.userId == _adminId);
      return host.displayName ?? host.username ?? "Admin";
    } catch (_) {
      return "Host";
    }
  }

  void _listenToGame() {
    _gameChannel = supabase.channel('online_quiz:${widget.gameId}')
      ..onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'games',
        filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: widget.gameId),
        callback: (payload) {
          _lastRoomActivity = DateTime.now();
          final status = payload.newRecord['status']?.toString() ?? "";
          final reveal = payload.newRecord['reveal_answer'] as bool? ?? false;
          final answered =
              payload.newRecord['answered_questions'] as List<dynamic>? ?? [];
          _handleStatusUpdate(status, reveal, answered: answered.cast<int>());
        },
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'game_players',
        filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'game_id',
            value: widget.gameId),
        callback: (payload) {
          _lastRoomActivity = DateTime.now();
          _updateLeaderboard();
        },
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'answers',
        filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'game_id',
            value: widget.gameId),
        callback: (payload) {
          _lastRoomActivity = DateTime.now();
          _updateLeaderboard();
        },
      )
      ..subscribe();
  }

  Future<void> _syncSelection(String option) async {
    _resetInactivityTimer();
    setState(() => _selectedOption = option);

    final q = _activeQuestionIndex != null
        ? _getQuestionForIndex(_activeQuestionIndex!)
        : null;
    if (q == null) return;

    final versionedOption = "${q.id}:$option";
    await supabase
        .from('game_players')
        .update({'last_selection': versionedOption})
        .eq('game_id', widget.gameId)
        .eq('user_id', supabase.auth.currentUser!.id);

    bool isCorrect = false;
    if (q.questionType == 'multiple_choice') {
      final correctKey = q.answer?.toUpperCase() ?? "";
      final options = q.options ?? [];
      const labels = "ABCDE";
      final correctIndex = labels.indexOf(correctKey);

      if (correctIndex != -1 && correctIndex < options.length) {
        final correctText =
            _stripPrefix(options[correctIndex]).trim().toLowerCase();
        final selectedText = _stripPrefix(option).trim().toLowerCase();
        if (selectedText == correctText) isCorrect = true;
      }
    }

    await _quizService.submitAnswer(
      gameId: widget.gameId,
      questionId: q.id,
      userId: supabase.auth.currentUser!.id,
      answer: option,
      isCorrect: isCorrect,
    );

    await _updateLeaderboard();
  }

  Future<void> _syncQuestion(int index) async {
    if (index != -1) {
      if (index >= 80 && index <= 99) return;

      if (_sessionLimit != null && _answeredIndices.length >= _sessionLimit!) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('Session limit of $_sessionLimit questions reached!')),
        );
        return;
      }
    }

    await supabase
        .from('game_players')
        .update({'last_selection': null}).eq('game_id', widget.gameId);

    await supabase.from('games').update({
      'active_question_index': index,
      'reveal_answer': false,
    }).eq('id', widget.gameId);

    await supabase
        .from('games')
        .update({'status': 'revealed:$index'}).eq('id', widget.gameId);
  }

  Future<void> _syncReveal(bool reveal) async {
    await supabase
        .from('games')
        .update({'reveal_answer': reveal}).eq('id', widget.gameId);
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    setState(() {
      _timeLeft = widget.timerDuration;
      _canReveal = false;
    });

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;

      setState(() {
        if (_timeLeft > 0) {
          _timeLeft--;
        }

        if (widget.isHost && !_revealAnswer) {
          final question = _activeQuestionIndex != null
              ? _getQuestionForIndex(_activeQuestionIndex!)
              : null;
          bool allAnswered = false;
          if (question != null && _leaderboard.isNotEmpty) {
            allAnswered = _leaderboard.every((p) {
              final raw = p.lastSelection;
              if (raw == null || !raw.contains(':')) return false;
              final parts = raw.split(':');
              return parts[0] == question.id && parts[1].isNotEmpty;
            });
          }

          if (_timeLeft == 0 && !_canReveal) {
            setState(() {
              _canReveal = true;
            });
          }

          if (_timeLeft == 0 || allAnswered) {
            if (!_revealAnswer && _canReveal) {
              _syncReveal(true);
            }
            _countdownTimer?.cancel();
          }
        }
      });
    });
  }

  void _showGameOverDialog() {
    _isGameOverShown = true;

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
              width: double.infinity,
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
                    child: RankHistoryChart(
                      key: _chartKey,
                      gameId: widget.gameId,
                      questions: _allQuestionsInOrder
                          .where((q) =>
                              q != null &&
                              _answeredIndices
                                  .contains(_allQuestionsInOrder.indexOf(q)))
                          .cast<QuestionModel>()
                          .toList(),
                      players: _leaderboard,
                      allPlayers: _allPlayers,
                      adminId: _adminId,
                      isTeamMode: widget.isTeamMode,
                      onBackToLobby: () {
                        Navigator.of(context)
                            .popUntil((route) => route.isFirst);
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

  void _showWinnerReview() {
    if (widget.isHost) {
      _quizService.updateGameStatus(widget.gameId, 'winner_review');
    } else {
      _showGameOverDialog();
    }
  }

  Future<void> _revealQuestion(int index) async {
    if (_activeQuestionIndex != null || _answeredIndices.contains(index))
      return;

    if (index >= 80 && index <= 99) return;

    if (_isQuickMatch && _answeredIndices.length >= (_sessionLimit ?? 12)) {
      _quizService.updateGameStatus(widget.gameId, 'finished');
      setState(() {
        _activeQuestionIndex = -1;
      });
      return;
    }

    setState(() {
      _activeQuestionIndex = index;
      _revealAnswer = false;
      _hasAnswered = false;
      _selectedOption = null;
      _timeLeft = widget.timerDuration;
      _answerController.clear();
      _canReveal = false;
    });

    if (widget.isHost) {
      await _syncQuestion(index);
    }
  }

  Future<void> _nextQuestion() async {
    if (_isGameOverShown) return;

    final currentIndex = _activeQuestionIndex;

    await _syncQuestion(-1);

    await Future.delayed(const Duration(seconds: 3));

    if (!mounted) return;

    final totalAnswered = _answeredIndices.length;
    final limit = _sessionLimit ?? 12;

    if (totalAnswered >= limit) {
      if (widget.isHost) {
        _quizService.updateGameStatus(widget.gameId, 'finished');
      }
    } else if (_isQuickMatch) {
      int nextIndex = (currentIndex ?? -1) + 1;
      if (nextIndex <= 79) {
        _revealQuestion(nextIndex);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final totalAvailable = _allQuestionsInOrder.where((q) => q != null).length;
    if (totalAvailable == 0)
      return const Scaffold(
          body: Center(child: Text("No questions found in database")));

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF450E4E),
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            Image.asset(
              'assets/logo.png',
              width: MediaQuery.of(context).size.width * 0.12,
              height: MediaQuery.of(context).size.height * 0.05,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: 'Legacy Quiz\n',
                      style: TextStyle(
                        fontSize: (MediaQuery.of(context).size.height * 0.02)
                            .clamp(14.0, 22.0),
                        color: const Color.fromARGB(247, 251, 232, 13),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    TextSpan(
                      text: '(Dynamic questions)',
                      style: TextStyle(
                        fontSize: (MediaQuery.of(context).size.height * 0.012)
                            .clamp(10.0, 14.0),
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
          if (widget.isHost ||
              (_adminId == null &&
                  _leaderboard.isNotEmpty &&
                  _leaderboard[0].userId == supabase.auth.currentUser?.id))
            const Center(
                child: Text("HOST CONTROL  ",
                    style: TextStyle(
                        color: Colors.yellow,
                        fontSize: 10,
                        fontWeight: FontWeight.bold)))
          else
            const Center(
                child: Text("GUEST PLAYER  ",
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold))),
          IconButton(
            icon: const Icon(Icons.emoji_events, color: Colors.yellow),
            onPressed: _showWinnerReview,
            tooltip: 'Show Dynamic Bars & Winner Review',
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.yellow),
            onPressed: () async {
              final shouldQuit = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text("Quit Session"),
                  content: const Text(
                      "Are you sure you want to exit the live session?"),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text("Cancel")),
                    TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text("Exit")),
                  ],
                ),
              );
              if (shouldQuit == true) {
                if (widget.isHost) {
                  await supabase
                      .from('games')
                      .update({'status': 'aborted'}).eq('id', widget.gameId);
                }
                if (mounted) {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(
                        builder: (context) => ModeSelectionPage()),
                    (route) => false,
                  );
                }
              }
            },
          ),
        ],
      ),
      body: Listener(
        onPointerDown: (_) => _resetInactivityTimer(),
        onPointerMove: (_) => _resetInactivityTimer(),
        child: Stack(
          children: [
            Column(
              children: [
                if (_sessionLimit != null &&
                    _answeredIndices.length >= _sessionLimit! &&
                    _mcqQuestions.isNotEmpty)
                  Container(
                    width: double.infinity,
                    color: Colors.green,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          "MAXIMUM NUMBER FOR THIS SESSION ($_sessionLimit) HAS BEEN REACHED",
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 10),
                        ),
                        if (widget.isHost) ...[
                          const SizedBox(width: 20),
                          ElevatedButton(
                            onPressed: () => _quizService.updateGameStatus(
                                widget.gameId, 'finished'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.yellow,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 4),
                              minimumSize: const Size(0, 0),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text("FINISH & SHOW WINNER",
                                style: TextStyle(
                                    fontSize: 10, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ],
                    ),
                  ),
                _buildGridLegend(),
                _buildControllers(),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      const double spacing = 1.0;
                      final double maxWidth =
                          constraints.maxWidth * _gridWidthPercent;
                      final double maxHeight =
                          constraints.maxHeight * _gridHeightPercent;

                      final double cellWidth = maxWidth / 10;
                      final double cellHeight = maxHeight / 10;
                      final double aspectRatio =
                          (cellHeight > 0) ? (cellWidth / cellHeight) : 1.0;
                      final double fontSize =
                          (cellHeight * 0.35) * _fontSizeFactor;

                      return Center(
                        child: Container(
                          width: maxWidth,
                          height: maxHeight,
                          padding: const EdgeInsets.all(2.0),
                          child: GridView.builder(
                            padding: EdgeInsets.zero,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 10,
                              childAspectRatio: aspectRatio,
                              crossAxisSpacing: spacing,
                              mainAxisSpacing: spacing,
                            ),
                            itemCount: 100,
                            itemBuilder: (context, index) {
                              final question = _getQuestionForIndex(index);
                              final isSessionQuestion = question != null;
                              final isAnswered =
                                  _answeredIndices.contains(index);
                              final isCurrentSync =
                                  _syncedQuestionIndex == index;
                              final isDisabled = index >= 80 && index <= 99;

                              Color categoryColor;
                              if (index < 70)
                                categoryColor = const Color(0xFF006400);
                              else if (index < 80)
                                categoryColor = const Color(0xFF8B0000);
                              else
                                categoryColor = const Color(0xFF00008B);

                              return GestureDetector(
                                onTap: (widget.isHost &&
                                        isSessionQuestion &&
                                        !isAnswered &&
                                        !isDisabled)
                                    ? () => _syncQuestion(index)
                                    : null,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: isDisabled
                                        ? Colors.grey.shade200
                                        : (isCurrentSync
                                            ? Colors.yellow
                                            : Colors.white),
                                    border: Border.all(
                                      color: isCurrentSync
                                          ? Colors.orange
                                          : (isDisabled
                                              ? Colors.grey.shade400
                                              : categoryColor),
                                      width: 1.5,
                                    ),
                                    borderRadius: BorderRadius.circular(10),
                                    boxShadow: [
                                      if (isCurrentSync)
                                        const BoxShadow(
                                            color: Colors.orangeAccent,
                                            blurRadius: 4),
                                      BoxShadow(
                                          color: Colors.black.withOpacity(0.05),
                                          blurRadius: 2,
                                          offset: const Offset(0, 1)),
                                    ],
                                  ),
                                  child: isAnswered
                                      ? Padding(
                                          padding: const EdgeInsets.all(2),
                                          child: Image.asset(
                                            _getImageForCard(index).imagePath,
                                            fit: BoxFit.contain,
                                          ),
                                        )
                                      : Stack(
                                          alignment: Alignment.center,
                                          children: [
                                            Center(
                                              child: Text(
                                                "${index + 1}",
                                                style: TextStyle(
                                                  fontSize: fontSize,
                                                  fontWeight: FontWeight.bold,
                                                  color: isDisabled
                                                      ? Colors.grey.shade400
                                                      : (isCurrentSync
                                                          ? Colors.black
                                                          : categoryColor),
                                                ),
                                              ),
                                            ),
                                            if (isDisabled)
                                              Positioned(
                                                top: 1,
                                                right: 1,
                                                child: Icon(Icons.lock,
                                                    color: Colors.grey,
                                                    size: cellHeight * 0.25),
                                              ),
                                          ],
                                        ),
                                ),
                              );
                            },
                          ),
                        ),
                      );
                    },
                  ),
                ),
                _buildLeaderboardSection(),
                _buildFooter(),
              ],
            ),
            if (_activeQuestionIndex != null &&
                _activeQuestionIndex! != -1 &&
                _getQuestionForIndex(_activeQuestionIndex!) != null)
              Positioned.fill(
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 500),
                  curve: Curves.elasticOut,
                  builder: (context, value, child) {
                    return Transform.scale(
                      scale: value,
                      child: child,
                    );
                  },
                  child: _buildActiveQuestionView(),
                ),
              ),
            // Fixed ConfettiWidget - removed invalid parameters
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
                              blastDirectionality:
                                  BlastDirectionality.explosive,
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
                              blastDirectionality:
                                  BlastDirectionality.explosive,
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

  Widget _buildFooter() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 0),
      decoration: BoxDecoration(
        color: const Color(0xFF450E4E),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: const Text(
        'Developed by FIFMI Middle East (EGEA and Media)',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.normal,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }

  Widget _buildActiveQuestionView() {
    final index = _activeQuestionIndex;
    if (index == null) return const SizedBox();
    final question = _getQuestionForIndex(index);
    if (question == null) return const SizedBox();

    final options = question.questionType == 'multiple_choice'
        ? _getShuffledOptions(question)
        : (question.options ?? []);
    final labels = ['A', 'B', 'C', 'D', 'E'];

    final screenSize = MediaQuery.of(context).size;
    final bool isSmallScreen = screenSize.width < 600;
    final double baseFontSize =
        isSmallScreen ? 16.0 : (screenSize.width * 0.02).clamp(16.0, 24.0);

    return Stack(
      children: [
        Container(
          width: double.infinity,
          height: double.infinity,
          color: const Color(0xFFFDEFFF),
          child: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 30),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                      color: Colors.purple.shade100,
                                      borderRadius: BorderRadius.circular(15)),
                                  child: Text("Q${_activeQuestionIndex! + 1}",
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.purple,
                                          fontSize: 11)),
                                ),
                                const SizedBox(width: 8),
                                _buildParticipationPill(),
                              ],
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (!_revealAnswer)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: _timeLeft <= 5
                                          ? Colors.red.shade100
                                          : Colors.green.shade100,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(Icons.timer,
                                            size: 14,
                                            color: _timeLeft <= 5
                                                ? Colors.red
                                                : Colors.green),
                                        const SizedBox(width: 4),
                                        const Text("TIME: ",
                                            style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: Colors.green,
                                                fontSize: 10)),
                                        Text(
                                          "$_timeLeft",
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: _timeLeft <= 5
                                                  ? Colors.red
                                                  : Colors.green,
                                              fontSize: 14),
                                        ),
                                      ],
                                    ),
                                  ),
                                if (widget.isHost)
                                  IconButton(
                                    onPressed: () => _syncQuestion(-1),
                                    icon: const Icon(Icons.close,
                                        color: Colors.red, size: 20),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                  )
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          child: Text(
                            question.questionText,
                            style: TextStyle(
                                fontSize: baseFontSize * 1.2,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF450E4E),
                                height: 1.2),
                          ),
                        ),
                        const SizedBox(height: 20),
                        if (question.imageUrls.isNotEmpty) ...[
                          LayoutBuilder(
                            builder: (context, constraints) {
                              return Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: question.imageUrls
                                    .map((url) => ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          child: Container(
                                            decoration: BoxDecoration(
                                              border: Border.all(
                                                  color:
                                                      Colors.purple.shade100),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              color: Colors.white,
                                            ),
                                            child: Image.network(
                                              url,
                                              width: question.imageUrls.length >
                                                      1
                                                  ? (constraints.maxWidth / 2) -
                                                      10
                                                  : constraints.maxWidth,
                                              height: 180,
                                              fit: BoxFit.contain,
                                              errorBuilder: (context, error,
                                                      stackTrace) =>
                                                  Container(
                                                width: 100,
                                                height: 100,
                                                color: Colors.grey.shade100,
                                                child: const Icon(
                                                    Icons.broken_image,
                                                    color: Colors.grey),
                                              ),
                                            ),
                                          ),
                                        ))
                                    .toList(),
                              );
                            },
                          ),
                          const SizedBox(height: 20),
                        ],
                        if (question.questionType != 'multiple_choice' &&
                            (question.options == null ||
                                question.options!.isEmpty)) ...[
                          TextField(
                            controller: _answerController,
                            onChanged: (val) => _syncSelection(val),
                            decoration: InputDecoration(
                              hintText: "Type your answer here...",
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              prefixIcon:
                                  const Icon(Icons.edit, color: Colors.purple),
                            ),
                          ),
                          const SizedBox(height: 20),
                        ],
                        ...options.asMap().entries.map((entry) {
                          final idx = entry.key;
                          final opt = entry.value;
                          final label = idx < labels.length ? labels[idx] : '';
                          final isSelected = _selectedOption == opt;

                          final displayLabel =
                              opt.startsWith('$label. ') ? "" : "$label. ";

                          return GestureDetector(
                            onTap: _revealAnswer
                                ? null
                                : () => _syncSelection(opt),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? Colors.purple.shade100
                                      : Colors.transparent,
                                  border: Border.all(
                                      color: isSelected
                                          ? Colors.purple
                                          : Colors.grey.shade300),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (displayLabel.isNotEmpty)
                                      Text(displayLabel,
                                          style: TextStyle(
                                              fontSize: baseFontSize * 1.1,
                                              fontWeight: FontWeight.bold,
                                              color: isSelected
                                                  ? Colors.purple
                                                  : const Color(0xFF450E4E))),
                                    Expanded(
                                        child: Text(opt,
                                            style: TextStyle(
                                                fontSize: baseFontSize * 1.0,
                                                color: isSelected
                                                    ? Colors.purple
                                                    : const Color(0xFF450E4E),
                                                fontWeight: isSelected
                                                    ? FontWeight.bold
                                                    : FontWeight.normal))),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
                        const SizedBox(height: 30),
                        if (_revealAnswer) ...[
                          const Divider(color: Colors.purple),
                          Text("MARKING TABLE",
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green.shade800)),
                          const SizedBox(height: 10),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.yellow,
                              borderRadius: BorderRadius.circular(8),
                              border:
                                  Border.all(color: Colors.orange, width: 1),
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
                                Builder(builder: (context) {
                                  final correctKey =
                                      question.answer?.toUpperCase() ?? "";
                                  final correctIndex =
                                      "ABCDE".indexOf(correctKey);
                                  final correctText =
                                      (question.options != null &&
                                              correctIndex != -1 &&
                                              correctIndex <
                                                  question.options!.length)
                                          ? _stripPrefix(
                                              question.options![correctIndex])
                                          : (question.answer ?? "");
                                  return Text("CORRECT ANSWER: $correctText",
                                      style: TextStyle(
                                          color: Colors.black,
                                          fontWeight: FontWeight.w900,
                                          fontSize: (MediaQuery.of(context)
                                                      .size
                                                      .width *
                                                  0.022)
                                              .clamp(16.0, 32.0)));
                                }),
                                if (question.source.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text("SOURCE: ${question.source}",
                                      style: TextStyle(
                                          color: Colors.black87,
                                          fontWeight: FontWeight.bold,
                                          fontSize: (MediaQuery.of(context)
                                                      .size
                                                      .width *
                                                  0.018)
                                              .clamp(14.0, 26.0),
                                          fontStyle: FontStyle.italic)),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Builder(builder: (context) {
                              final sortedPlayers = List<GamePlayerModel>.from(
                                  _leaderboard)
                                ..sort(
                                    (a, b) => a.joinedAt.compareTo(b.joinedAt));

                              return Table(
                                defaultColumnWidth: const FixedColumnWidth(80),
                                border: TableBorder.all(
                                    color: Colors.purple.shade200),
                                children: [
                                  TableRow(
                                    children: sortedPlayers
                                        .asMap()
                                        .entries
                                        .map((entry) => Padding(
                                              padding:
                                                  const EdgeInsets.all(4.0),
                                              child: Text("P${entry.key + 1}",
                                                  textAlign: TextAlign.center,
                                                  style: const TextStyle(
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: Colors.purple)),
                                            ))
                                        .toList(),
                                  ),
                                  TableRow(
                                    children: sortedPlayers
                                        .map((p) => Padding(
                                              padding:
                                                  const EdgeInsets.all(4.0),
                                              child: Text(
                                                  p.displayName ??
                                                      p.username ??
                                                      "Player",
                                                  textAlign: TextAlign.center,
                                                  style: const TextStyle(
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: Colors.black87),
                                                  overflow:
                                                      TextOverflow.ellipsis),
                                            ))
                                        .toList(),
                                  ),
                                  TableRow(
                                    children: sortedPlayers.map((p) {
                                      final ans =
                                          _playerAnswersThisRound[p.userId];
                                      return Padding(
                                        padding: const EdgeInsets.all(6.0),
                                        child: Container(
                                          height: 80,
                                          padding: const EdgeInsets.all(4),
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            border: Border.all(
                                                color: Colors.grey.shade300),
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: SingleChildScrollView(
                                            child: Text(
                                              ans ?? "No Answer",
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: ans != null
                                                    ? Colors.purple
                                                    : Colors.grey,
                                                fontStyle: ans != null
                                                    ? FontStyle.normal
                                                    : FontStyle.italic,
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                  TableRow(
                                    children: sortedPlayers
                                        .map((p) => IconButton(
                                              onPressed: (widget.isHost ||
                                                      (_adminId == null &&
                                                          _leaderboard
                                                              .isNotEmpty &&
                                                          _leaderboard[0]
                                                                  .userId ==
                                                              supabase
                                                                  .auth
                                                                  .currentUser
                                                                  ?.id))
                                                  ? () {
                                                      final wasCorrect =
                                                          (_tempMarks[p
                                                                      .userId] ??
                                                                  0) ==
                                                              1;
                                                      setState(() =>
                                                          _tempMarks[p.userId] =
                                                              wasCorrect
                                                                  ? 0
                                                                  : 1);
                                                      // Trigger confetti when marking correct
                                                      if (!wasCorrect) {
                                                        _triggerConfettiBurst();
                                                      }
                                                    }
                                                  : null,
                                              icon: Icon(Icons.check_circle,
                                                  color: _tempMarks[p.userId] ==
                                                          1
                                                      ? Colors.green
                                                      : Colors.grey.shade300),
                                            ))
                                        .toList(),
                                  ),
                                  TableRow(
                                    children: sortedPlayers
                                        .map((p) => IconButton(
                                              onPressed: (widget.isHost ||
                                                      (_adminId == null &&
                                                          _leaderboard
                                                              .isNotEmpty &&
                                                          _leaderboard[0]
                                                                  .userId ==
                                                              supabase
                                                                  .auth
                                                                  .currentUser
                                                                  ?.id))
                                                  ? () {
                                                      setState(() => _tempMarks[
                                                              p.userId] =
                                                          (_tempMarks[p.userId] ??
                                                                      0) ==
                                                                  -1
                                                              ? 0
                                                              : -1);
                                                    }
                                                  : null,
                                              icon: Icon(Icons.cancel,
                                                  color: _tempMarks[p.userId] ==
                                                          -1
                                                      ? Colors.red
                                                      : Colors.grey.shade300),
                                            ))
                                        .toList(),
                                  ),
                                ],
                              );
                            }),
                          ),
                          const SizedBox(height: 100),
                        ],
                      ],
                    ),
                  ),
                ),
                if (widget.isHost)
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 10,
                            offset: const Offset(0, -5)),
                      ],
                    ),
                    child: _revealAnswer
                        ? SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: () async {
                                final correctCount = await _submitManualMarks();
                                if (correctCount > 0) {
                                  _triggerConfettiBurst();
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 15),
                              ),
                              child: const Text("Submit Marks & Next",
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16)),
                            ),
                          )
                        : _canReveal
                            ? SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: () => _syncReveal(true),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF450E4E),
                                    foregroundColor: Colors.yellow,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 15),
                                  ),
                                  child: const Text('Mark the Answers',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16)),
                                ),
                              )
                            : const Text(
                                "Waiting for players to answer...",
                                style: TextStyle(
                                    fontStyle: FontStyle.italic,
                                    color: Colors.purple),
                                textAlign: TextAlign.center,
                              ),
                  )
                else if (!_revealAnswer)
                  Container(
                    padding: const EdgeInsets.all(20),
                    child: const Text(
                      "Waiting for host to mark answers...",
                      style: TextStyle(
                          fontStyle: FontStyle.italic, color: Colors.purple),
                      textAlign: TextAlign.center,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<int> _submitManualMarks() async {
    final currentIdx = _activeQuestionIndex;
    if (currentIdx == null) return 0;

    final q = _getQuestionForIndex(currentIdx);
    if (q == null) return 0;

    final basePoints = q.points;
    final myId = supabase.auth.currentUser!.id;

    final answers = await _quizService.fetchGameAnswers(widget.gameId);
    final questionAnswers = answers.where((a) => a.questionId == q.id).toList();

    questionAnswers.sort((a, b) => a.answeredAt.compareTo(b.answeredAt));

    String? firstFastestId;
    String? secondFastestId;
    int correctCount = 0;

    for (var ans in questionAnswers) {
      if (_tempMarks[ans.userId] == 1) {
        correctCount++;
        if (correctCount == 1) firstFastestId = ans.userId;
        if (correctCount == 2) secondFastestId = ans.userId;
      }
    }

    List<Future> updates = [];
    if (q.questionType != 'multiple_choice') {
      if (widget.isTeamMode) {
        final playersData = await supabase
            .from('game_players')
            .select('user_id, team_name')
            .eq('game_id', widget.gameId);
        final List<dynamic> players = playersData as List;

        for (var entry in _tempMarks.entries) {
          final repId = entry.key;
          final isCorrect = entry.value == 1;

          final teamName =
              players.firstWhere((p) => p['user_id'] == repId)['team_name'];

          final teamMemberIds = players
              .where((p) => p['team_name'] == teamName)
              .map((p) => p['user_id'].toString())
              .toList();

          for (var memberId in teamMemberIds) {
            updates.add(_quizService.updateAnswerCorrectness(
              gameId: widget.gameId,
              questionId: q.id,
              userId: memberId,
              isCorrect: isCorrect,
            ));
          }
        }
      } else {
        for (var entry in _tempMarks.entries) {
          updates.add(_quizService.updateAnswerCorrectness(
            gameId: widget.gameId,
            questionId: q.id,
            userId: entry.key,
            isCorrect: entry.value == 1,
          ));
        }
      }
    }

    if (updates.isNotEmpty) {
      await Future.wait(updates);
    }

    _answeredIndices.add(currentIdx);
    await supabase
        .from('games')
        .update({'answered_questions': _answeredIndices.toList()}).eq(
            'id', widget.gameId);

    await supabase
        .from('game_players')
        .update({'last_selection': null}).eq('game_id', widget.gameId);

    if (mounted) {
      setState(() {
        _tempMarks.clear();
      });
      await _updateLeaderboard();

      await _nextQuestion();
    }

    return correctCount;
  }

  Future<void> _scoreMyself(int questionIndex) async {
    if (_lastScoredIndex == questionIndex) return;

    final q = _getQuestionForIndex(questionIndex);
    if (q == null) return;

    final myId = supabase.auth.currentUser!.id;

    final answers = await _quizService.fetchGameAnswers(widget.gameId);
    final questionAnswers = answers.where((a) => a.questionId == q.id).toList();

    AnswerModel? myAnswer;
    try {
      myAnswer = questionAnswers.firstWhere((a) => a.userId == myId);
    } catch (_) {
      return;
    }

    _lastScoredIndex = questionIndex;
    final isCorrect = myAnswer.isCorrect ?? false;

    if (isCorrect) {
      int pointsToAward = q.points;

      final correctAnswers = questionAnswers.where((a) => a.isCorrect).toList();
      correctAnswers.sort((a, b) => a.answeredAt.compareTo(b.answeredAt));

      if (correctAnswers.isNotEmpty && correctAnswers[0].userId == myId) {
        pointsToAward += 2;
        debugPrint("SCORING: Awarded 1st place speed bonus (+2) to myself");
      } else if (correctAnswers.length > 1 &&
          correctAnswers[1].userId == myId) {
        pointsToAward += 1;
        debugPrint("SCORING: Awarded 2nd place speed bonus (+1) to myself");
      }

      await _quizService.updatePlayerScore(widget.gameId, myId, pointsToAward);

      if (isCorrect) {
        _celebratedIndex = _activeQuestionIndex;
        _triggerConfettiBurst();
      }
    } else {
      await _quizService.updatePlayerScore(widget.gameId, myId, -q.points);
    }
  }

  Widget _buildParticipationPill() {
    final answeredCount = _answeredThisRound.length;
    final totalCount = _leaderboard.length;
    final allAnswered = answeredCount == totalCount && totalCount > 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: allAnswered ? Colors.green.shade50 : Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: allAnswered ? Colors.green.shade200 : Colors.blue.shade200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            allAnswered ? Icons.check_circle : Icons.pending,
            size: 14,
            color: allAnswered ? Colors.green : Colors.blue,
          ),
          const SizedBox(width: 6),
          Text(
            "$answeredCount / $totalCount Answered",
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: allAnswered ? Colors.green.shade700 : Colors.blue.shade700,
            ),
          ),
        ],
      ),
    );
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

  Widget _buildLeaderboardSection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        color: Color(0xFF450E4E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          const Text("Live Leaderboard",
              style: TextStyle(
                  color: Colors.yellow,
                  fontWeight: FontWeight.bold,
                  fontSize: 12)),
          const SizedBox(height: 8),
          SizedBox(
            height: 85,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              itemCount: _leaderboard.length,
              separatorBuilder: (context, index) => const SizedBox(width: 15),
              itemBuilder: (context, index) {
                final p = _leaderboard[index];
                final correct = _playerCorrectCounts[p.userId] ?? 0;
                final total = _playerTotalAnswered[p.userId] ?? 0;
                final percent = total > 0 ? (correct / total * 100) : 0.0;
                final isMe = p.userId == supabase.auth.currentUser?.id;

                return Container(
                  width: 110,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isMe
                        ? Colors.yellow.withOpacity(0.15)
                        : Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isMe ? Colors.yellow : Colors.white10,
                      width: isMe ? 1.5 : 1,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: isMe ? Colors.yellow : Colors.white24,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              "#${index + 1}",
                              style: TextStyle(
                                color: isMe
                                    ? const Color(0xFF450E4E)
                                    : Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              p.displayName ?? p.username ?? "Player",
                              style: TextStyle(
                                color: isMe ? Colors.yellow : Colors.white70,
                                fontSize: 10,
                                fontWeight:
                                    isMe ? FontWeight.bold : FontWeight.normal,
                              ),
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        p.score.toString(),
                        style: TextStyle(
                          color: isMe ? Colors.yellow : Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      Text(
                        "$correct/$total (${percent.toStringAsFixed(1)}%)",
                        style: TextStyle(
                          color: isMe ? Colors.yellow.shade200 : Colors.white54,
                          fontSize: 9,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 25),
        ],
      ),
    );
  }

  _ImageDetails _getImageForCard(int index) {
    final images = [
      'assets/logo.png',
      'assets/image1.png',
      'assets/image2_3.png',
      'assets/baba100new.jpg',
    ];
    return _ImageDetails(images[index % images.length], 0.8);
  }
}

class _ImageDetails {
  final String imagePath;
  final double heightPercentage;
  _ImageDetails(this.imagePath, this.heightPercentage);
}
