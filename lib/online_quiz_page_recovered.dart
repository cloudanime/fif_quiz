import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'services/quiz_supabase_service.dart';
import 'models/supabase_models.dart';
import 'dart:math';
import 'rank_history_chart.dart';

class OnlineQuizPageRecovered extends StatefulWidget {
  final String gameId;
  final int questionCount;
  final int timerDuration;
  final bool isHost;
  final bool isTeamMode;

  const OnlineQuizPageRecovered({
    super.key,
    required this.gameId,
    required this.questionCount,
    this.timerDuration = 60,
    this.isHost = false,
    this.isTeamMode = false,
  });

  @override
  State<OnlineQuizPageRecovered> createState() =>
      _OnlineQuizPageRecoveredState();
}

class _OnlineQuizPageRecoveredState extends State<OnlineQuizPageRecovered> {
  final SupabaseQuizService _quizService = SupabaseQuizService();
  final supabase = Supabase.instance.client;
  final GlobalKey<RankHistoryChartState> _chartKey =
      GlobalKey<RankHistoryChartState>();

  bool _isLoading = true;
  bool _hasAnswered = false;
  bool _revealAnswer = false;
  List<GamePlayerModel> _leaderboard = [];
  List<GamePlayerModel> _allPlayers = [];
  RealtimeChannel? _gameChannel;
  final List<Widget> _logoParticles = [];

  Set<int> _answeredIndices = {};
  int? _activeQuestionIndex;
  int? _syncedQuestionIndex;
  final Map<String, int> _tempMarks = {};
  final Set<String> _answeredThisRound = {};
  String? _selectedOption;
  int? _lastScoredIndex;
  int? _celebratedIndex;
  int? _sessionLimit;
  bool _isGameOverShown = false;
  bool _isExiting = false;
  int _timeLeft = 60;
  Timer? _countdownTimer;
  bool _isQuickMatch = false;
  final TextEditingController _answerController = TextEditingController();
  bool _canReveal = false; // NEW: Track if reveal button should be shown

  final Map<String, List<String>> _shuffledOptionsMap = {};
  Map<String, int> _playerCorrectCounts = {};
  Map<String, int> _playerTotalAnswered = {};
  Map<String, String> _playerAnswersThisRound = {}; // userId -> answer

  String _stripPrefix(String? opt) {
    if (opt == null || opt.isEmpty) return "";
    // Strips "A. ", "B. ", etc.
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
    // Use a deterministic seed based on question ID so all players see the same order
    final random = Random(q.id.hashCode);
    raw.shuffle(random);
    _shuffledOptionsMap[q.id] = raw;
    return raw;
  }

  List<QuestionModel> _mcqQuestions = [];
  List<QuestionModel> _pictureQuestions = [];
  List<QuestionModel> _structuredQuestions = [];
  List<QuestionModel> _allQuestionsInOrder = [];

  @override
  void initState() {
    super.initState();
    _loadGameData();
    _listenToGame();
    _startHeartbeatSync();
    _startInactivityTimer();
  }

  Timer? _inactivityTimer;
  void _startInactivityTimer() {
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(const Duration(minutes: 3), () {
      if (mounted) {
        _exitGame();
      }
    });
  }

  void _resetInactivityTimer() {
    if (_inactivityTimer != null) {
      _startInactivityTimer();
    }
  }

  Future<void> _exitGame() async {
    if (_isExiting) return;
    _isExiting = true;
    _heartbeatTimer?.cancel();
    _inactivityTimer?.cancel();

    if (widget.isHost) {
      await supabase
          .from('games')
          .update({'status': 'aborted'}).eq('id', widget.gameId);
    }
    if (mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  Timer? _heartbeatTimer;
  void _startHeartbeatSync() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (mounted) {
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
            _canReveal = false; // Reset reveal button visibility
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
            _logoParticles.clear();
          });
          _startCountdown();
        }
      } catch (_) {}
    } else if (status == 'finished' && !_isGameOverShown) {
      _showGameOverDialog();
    } else if (status == 'aborted') {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Host has left. Game aborted.")));
        Navigator.of(context).pop();
      }
    }

    if (reveal != _revealAnswer) {
      setState(() {
        _revealAnswer = reveal;
        if (reveal) {
          _autoFillMarks();
          _countdownTimer?.cancel();
          _timeLeft = 0;

          // Trigger self-scoring immediately so points update and confetti shows
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
    _countdownTimer?.cancel();
    _gameChannel?.unsubscribe();
    _heartbeatTimer?.cancel();
    _inactivityTimer?.cancel();
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
          // Grouping players by team for team aggregation
          final Map<String, GamePlayerModel> teamAggregates = {};

          for (var p in allPlayers) {
            final tName = p.teamName ?? 'No Team';
            if (!teamAggregates.containsKey(tName)) {
              teamAggregates[tName] = GamePlayerModel(
                id: p.teamCode ?? tName,
                gameId: p.gameId,
                userId: tName,
                score: 0,
                isReady: true,
                joinedAt: p.joinedAt,
                displayName: tName, // Team Name is the display name here
                teamName: tName,
                teamCode: p.teamCode,
              );
            }

            // Add member score to team score
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

            // Map individual stats to the team entry for percent calculation
            final teamKey = tName;
            newTotal[teamKey] =
                (newTotal[teamKey] ?? 0) + (newTotal[p.userId] ?? 0);
            newCorrect[teamKey] =
                (newCorrect[teamKey] ?? 0) + (newCorrect[p.userId] ?? 0);

            // Merge answers this round if any member answered
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

        // Live participation tracking
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
                _answeredThisRound
                    .add(widget.isTeamMode ? (p.teamName ?? 'No Team') : p.id);
              }
            }
          }
        }

        // Check if all players have answered
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

    // Find the actual correct text from the original options
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
          // Don't overwrite if host manually marked
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

        // AUTO-TRIGGER CONFETTI: If we just confirmed the local user is correct
        final myId = supabase.auth.currentUser!.id;
        if (p.userId == myId &&
            isCorrect &&
            _celebratedIndex != _activeQuestionIndex) {
          _celebratedIndex = _activeQuestionIndex;
        }
      }
    });
  }

  Future<void> _loadGameData() async {
    try {
      final game = await supabase
          .from('games')
          .select('question_ids, question_count, status, answered_questions')
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

      final playersList = (players as List? ?? [])
          .map((json) => GamePlayerModel.fromJson(json))
          .toList();

      setState(() {
        _allPlayers = playersList;
        _allQuestionsInOrder = questions;
        _mcqQuestions = questions
            .where((q) => q.questionType == 'multiple_choice')
            .toList();
        _pictureQuestions =
            questions.where((q) => q.questionType == 'picture').toList();
        _structuredQuestions =
            questions.where((q) => q.questionType == 'structured').toList();
        _leaderboard = playersList;
        _isQuickMatch = _sessionLimit == 15;
        _answeredIndices = answered.cast<int>().toSet();

        // Initial status check for revealed question
        final status = game['status']?.toString() ?? "";
        if (status.startsWith('revealed:')) {
          try {
            _activeQuestionIndex = int.parse(status.split(':')[1]);
            _timeLeft = widget.timerDuration;
            _startCountdown();
          } catch (_) {}
        }

        if (_isQuickMatch && widget.isHost) {
          // Automatically start the first question for Quick Match
          Future.delayed(const Duration(seconds: 1), () {
            if (mounted && _activeQuestionIndex == null) {
              _revealQuestion(0);
            }
          });
        }
        _isLoading = false;
      });
      _updateLeaderboard(); // Fetch answer stats immediately
    } catch (e) {
      debugPrint("Error loading game data: $e");
    }
  }

  QuestionModel? _getQuestionForIndex(int index) {
    if (index < 70) {
      if (_mcqQuestions.isEmpty) return null;
      return _mcqQuestions[index % _mcqQuestions.length];
    } else if (index < 80) {
      if (_pictureQuestions.isEmpty) return null;
      return _pictureQuestions[(index - 70) % _pictureQuestions.length];
    } else if (index < 100) {
      if (_structuredQuestions.isEmpty) return null;
      return _structuredQuestions[(index - 80) % _structuredQuestions.length];
    }
    return null;
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
        callback: (payload) => _updateLeaderboard(),
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'answers',
        filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'game_id',
            value: widget.gameId),
        callback: (payload) => _updateLeaderboard(),
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'game_players',
        filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'game_id',
            value: widget.gameId),
        callback: (payload) => _updateLeaderboard(),
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

    // 1. Versioned selection for Realtime sync (game_players)
    final versionedOption = "${q.id}:$option";
    await supabase
        .from('game_players')
        .update({'last_selection': versionedOption})
        .eq('game_id', widget.gameId)
        .eq('user_id', supabase.auth.currentUser!.id);

    // 2. Record in answers table for Host marking
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
  }

  Future<void> _syncQuestion(int index) async {
    if (index != -1) {
      // Disable questions 81-100
      if (index >= 80 && index <= 99) return;

      // Check if we've reached the pick limit (only when opening a new question)
      if (_sessionLimit != null && _answeredIndices.length >= _sessionLimit!) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('Session limit of $_sessionLimit questions reached!')),
        );
        return;
      }
    }

    // 1. First, clear selections for all players in the DB
    await supabase
        .from('game_players')
        .update({'last_selection': null}).eq('game_id', widget.gameId);

    // 2. Then, update the question index and reveal status
    await supabase.from('games').update({
      'active_question_index': index,
      'reveal_answer': false,
    }).eq('id', widget.gameId);

    // 3. Finally, update the status to trigger UI update on clients
    // This ensures selections are cleared before clients even know about the new question
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
      _canReveal = false; // Reset reveal button visibility
    });

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;

      setState(() {
        if (_timeLeft > 0) {
          _timeLeft--;
        }

        // HOST ONLY: Check if timer has lapsed
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

          // Show reveal button when timer reaches 0
          if (_timeLeft == 0 && !_canReveal) {
            setState(() {
              _canReveal = true;
            });
          }

          // Auto-reveal if timer reaches 0 OR all answered (optional)
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

    // Sort leaderboard by score to find the winner
    final finalStandings = List<GamePlayerModel>.from(_leaderboard)
      ..sort((a, b) => b.score.compareTo(a.score));

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(10),
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
                child: RankHistoryChart(
                  key: _chartKey,
                  gameId: widget.gameId,
                  questions: _allQuestionsInOrder
                      .where((q) => _answeredIndices
                          .contains(_allQuestionsInOrder.indexOf(q)))
                      .toList(),
                  players: _leaderboard,
                  allPlayers: _allPlayers,
                  adminId: _adminId,
                  isTeamMode: widget.isTeamMode,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showWinnerReview() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(10),
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
                child: RankHistoryChart(
                  key: GlobalKey(),
                  gameId: widget.gameId,
                  questions: _allQuestionsInOrder
                      .where((q) => _answeredIndices
                          .contains(_allQuestionsInOrder.indexOf(q)))
                      .toList(),
                  players: _leaderboard,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _revealQuestion(int index) async {
    if (_activeQuestionIndex != null || _answeredIndices.contains(index))
      return;

    // Disable questions 81-100 (indices 80-99)
    if (index >= 80 && index <= 99) return;

    // For Quick Match, ensure we don't go past the limit
    if (_isQuickMatch && _answeredIndices.length >= (_sessionLimit ?? 12)) {
      _quizService.updateGameStatus(widget.gameId, 'finished');
      return;
    }

    setState(() {
      _activeQuestionIndex = index;
      _revealAnswer = false;
      _hasAnswered = false;
      _selectedOption = null;
      _timeLeft = widget.timerDuration;
      _answerController.clear();
      _canReveal = false; // Reset reveal button visibility
    });

    if (widget.isHost) {
      await _syncQuestion(index);

      if (_isQuickMatch) {
        // We rely on auto-reveal logic when everyone answers
      }
    }
  }

  Future<void> _nextQuestion() async {
    // If we are already finishing, don't do anything
    if (_isGameOverShown) return;

    final currentIndex = _activeQuestionIndex;

    // First, ensure we go back to the grid
    await _syncQuestion(-1);

    // Wait for 3 seconds on the grid as requested
    await Future.delayed(const Duration(seconds: 3));

    if (!mounted) return;

    // Use the count of answered questions to check for completion
    final totalAnswered = _answeredIndices.length;
    final limit = _sessionLimit ?? 12;

    if (totalAnswered >= limit) {
      if (widget.isHost) {
        _quizService.updateGameStatus(widget.gameId, 'finished');
      }
    } else if (_isQuickMatch) {
      // Auto-open next ONLY in Quick Match mode
      int nextIndex = (currentIndex ?? -1) + 1;
      if (nextIndex <= 79) {
        _revealQuestion(nextIndex);
      }
    }
    // For non-Quick Match, we just stay on the grid (host will pick next)
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final totalAvailable = _mcqQuestions.length +
        _pictureQuestions.length +
        _structuredQuestions.length;
    if (totalAvailable == 0)
      return const Scaffold(
          body: Center(child: Text("No questions found in database")));

    return Scaffold(
      backgroundColor: const Color(0xFFEAC7EF),
      appBar: AppBar(
        title: const Text("Online Challenge"),
        backgroundColor: const Color(0xFF450E4E),
        automaticallyImplyLeading: false,
        actions: [
          if (widget.isHost)
            const Center(
                child: Text("HOST CONTROL  ",
                    style: TextStyle(
                        color: Colors.yellow,
                        fontSize: 10,
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
                if (mounted) Navigator.pop(context);
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
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(2.0),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final gridItemWidth = constraints.maxWidth / 10;
                        final gridItemHeight = constraints.maxHeight / 10;

                        return Stack(
                          children: [
                            GridView.builder(
                              padding: EdgeInsets.zero,
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 10,
                                childAspectRatio:
                                    gridItemWidth / gridItemHeight,
                                crossAxisSpacing: 1.0,
                                mainAxisSpacing: 1.0,
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

                                return GestureDetector(
                                  onTap: (widget.isHost &&
                                          isSessionQuestion &&
                                          !isAnswered &&
                                          !isDisabled)
                                      ? () => _syncQuestion(index)
                                      : null,
                                  child: Container(
                                    margin: const EdgeInsets.all(1.5),
                                    decoration: BoxDecoration(
                                      color: isDisabled
                                          ? Colors.grey.shade200
                                          : (isCurrentSync
                                              ? Colors.yellow
                                              : Colors.white),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: isDisabled
                                            ? Colors.grey.shade400
                                            : (index < 70
                                                ? const Color(0xFF006400)
                                                : (index < 80
                                                    ? const Color(0xFF8B0000)
                                                    : const Color(0xFF00008B))),
                                        width: 1.5,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.05),
                                          blurRadius: 2,
                                          offset: const Offset(0, 1),
                                        ),
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
                                                    fontSize:
                                                        gridItemHeight * 0.28,
                                                    fontWeight: FontWeight.bold,
                                                    color: isDisabled
                                                        ? Colors.grey.shade400
                                                        : (index < 70
                                                            ? const Color(
                                                                0xFF006400)
                                                            : (index < 80
                                                                ? const Color(
                                                                    0xFF8B0000)
                                                                : const Color(
                                                                    0xFF00008B))),
                                                  ),
                                                ),
                                              ),
                                              if (isDisabled)
                                                Positioned(
                                                  top: 2,
                                                  right: 2,
                                                  child: Icon(Icons.lock,
                                                      color: Colors.grey,
                                                      size:
                                                          gridItemHeight * 0.2),
                                                ),
                                            ],
                                          ),
                                  ),
                                );
                              },
                            ),
                            // Section Dividers
                            Positioned(
                              top: gridItemHeight * 7,
                              left: 0,
                              right: 0,
                              child: Container(
                                  height: 3,
                                  color: Colors.red.withOpacity(0.8)),
                            ),
                            Positioned(
                              top: gridItemHeight * 8,
                              left: 0,
                              right: 0,
                              child: Container(
                                  height: 3,
                                  color: Colors.blue.withOpacity(0.8)),
                            ),
                            Positioned(
                              top: 0,
                              left: 0,
                              right: 0,
                              child: Container(
                                  height: 3,
                                  color: Colors.green.withOpacity(0.8)),
                            ),
                          ],
                        );
                      },
                    ),
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
          ],
        ),
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
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 30),
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

                  // Question Text
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

                  // Image Display
                  if (question.imageUrls.isNotEmpty) ...[
                    LayoutBuilder(
                      builder: (context, constraints) {
                        return Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: question.imageUrls
                              .map((url) => ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        border: Border.all(
                                            color: Colors.purple.shade100),
                                        borderRadius: BorderRadius.circular(12),
                                        color: Colors.white,
                                      ),
                                      child: Image.network(
                                        url,
                                        width: question.imageUrls.length > 1
                                            ? (constraints.maxWidth / 2) - 10
                                            : constraints.maxWidth,
                                        height: 180,
                                        fit: BoxFit.contain,
                                        errorBuilder:
                                            (context, error, stackTrace) =>
                                                Container(
                                          width: 100,
                                          height: 100,
                                          color: Colors.grey.shade100,
                                          child: const Icon(Icons.broken_image,
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

                  // TEXT INPUT
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

                  // Options
                  ...options.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final opt = entry.value;
                    final label = idx < labels.length ? labels[idx] : '';
                    final isSelected = _selectedOption == opt;

                    final displayLabel =
                        opt.startsWith('$label. ') ? "" : "$label. ";

                    return GestureDetector(
                      onTap: _revealAnswer ? null : () => _syncSelection(opt),
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

                  // MARKING SECTION
                  if (_revealAnswer) ...[
                    const Divider(color: Colors.purple),
                    Text("MARKING TABLE",
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade800)),
                    const SizedBox(height: 10),
                    Builder(builder: (context) {
                      final correctKey = question.answer?.toUpperCase() ?? "";
                      final correctIndex = "ABCDE".indexOf(correctKey);
                      final correctText = (question.options != null &&
                              correctIndex != -1 &&
                              correctIndex < question.options!.length)
                          ? _stripPrefix(question.options![correctIndex])
                          : (question.answer ?? "");
                      return Text("Correct Answer: $correctText",
                          style: const TextStyle(
                              color: Colors.green,
                              fontWeight: FontWeight.bold));
                    }),
                    if (question.source.isNotEmpty)
                      Text("Source: ${question.source}",
                          style: const TextStyle(
                              fontSize: 12, fontStyle: FontStyle.italic)),
                    const SizedBox(height: 20),

                    // Marking Table
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Builder(builder: (context) {
                        final sortedPlayers = List<GamePlayerModel>.from(
                            _leaderboard)
                          ..sort((a, b) => a.joinedAt.compareTo(b.joinedAt));

                        return Table(
                          defaultColumnWidth: const FixedColumnWidth(80),
                          border:
                              TableBorder.all(color: Colors.purple.shade200),
                          children: [
                            TableRow(
                              children: sortedPlayers
                                  .asMap()
                                  .entries
                                  .map((entry) => Padding(
                                        padding: const EdgeInsets.all(4.0),
                                        child: Text("P${entry.key + 1}",
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.purple)),
                                      ))
                                  .toList(),
                            ),
                            TableRow(
                              children: sortedPlayers
                                  .map((p) => Padding(
                                        padding: const EdgeInsets.all(4.0),
                                        child: Text(
                                            p.displayName ??
                                                p.username ??
                                                "Player",
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.black87),
                                            overflow: TextOverflow.ellipsis),
                                      ))
                                  .toList(),
                            ),
                            TableRow(
                              children: sortedPlayers.map((p) {
                                final ans = _playerAnswersThisRound[p.userId];
                                return Padding(
                                  padding: const EdgeInsets.all(6.0),
                                  child: Container(
                                    height: 80,
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      border: Border.all(
                                          color: Colors.grey.shade300),
                                      borderRadius: BorderRadius.circular(4),
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
                                        onPressed: widget.isHost
                                            ? () {
                                                setState(() =>
                                                    _tempMarks[p.userId] =
                                                        _tempMarks[p.userId] ==
                                                                1
                                                            ? 0
                                                            : 1);
                                              }
                                            : null,
                                        icon: Icon(Icons.check_circle,
                                            color: _tempMarks[p.userId] == 1
                                                ? Colors.green
                                                : Colors.grey.shade300),
                                      ))
                                  .toList(),
                            ),
                            TableRow(
                              children: sortedPlayers
                                  .map((p) => IconButton(
                                        onPressed: widget.isHost
                                            ? () {
                                                setState(() =>
                                                    _tempMarks[p.userId] =
                                                        _tempMarks[p.userId] ==
                                                                -1
                                                            ? 0
                                                            : -1);
                                              }
                                            : null,
                                        icon: Icon(Icons.cancel,
                                            color: _tempMarks[p.userId] == -1
                                                ? Colors.red
                                                : Colors.grey.shade300),
                                      ))
                                  .toList(),
                            ),
                          ],
                        );
                      }),
                    ),
                    const SizedBox(height: 30),
                    if (widget.isHost)
                      Center(
                        child: ElevatedButton(
                          onPressed: _submitManualMarks,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text("Submit Marks & Next"),
                        ),
                      ),
                  ] else if (widget.isHost && _canReveal) ...[
                    // Reveal Button for Host - ONLY SHOWN when conditions are met
                    Center(
                      child: ElevatedButton(
                        onPressed: () async {
                          final correctCount = await _submitManualMarks();
                          if (correctCount > 0) {
                            _triggerConfettiBurst();
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF450E4E),
                          foregroundColor: Colors.yellow,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 40, vertical: 15),
                        ),
                        child: const Text('Mark the Answers',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ] else if (!_revealAnswer &&
                      widget.isHost &&
                      !_canReveal) ...[
                    // Show waiting message while conditions are not met
                    const Center(
                      child: Text(
                        "Waiting for all players to answer or timer to lapse...",
                        style: TextStyle(
                            fontStyle: FontStyle.italic, color: Colors.purple),
                      ),
                    ),
                  ] else if (!widget.isHost && !_revealAnswer) ...[
                    const Center(
                      child: Text(
                        "Waiting for host to mark answers...",
                        style: TextStyle(
                            fontStyle: FontStyle.italic, color: Colors.purple),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),

        // Celebration Layer removed
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

    // 1. Fetch all answers for this question to determine speed
    final answers = await _quizService.fetchGameAnswers(widget.gameId);
    final questionAnswers = answers.where((a) => a.questionId == q.id).toList();

    // Sort by answeredAt to find the fastest
    questionAnswers.sort((a, b) => a.answeredAt.compareTo(b.answeredAt));

    // Identify the winners of the speed bonus
    String? firstFastestId;
    String? secondFastestId;
    int correctCount = 0;

    for (var ans in questionAnswers) {
      // Check if the host marked this player as correct in _tempMarks
      if (_tempMarks[ans.userId] == 1) {
        correctCount++;
        if (correctCount == 1) firstFastestId = ans.userId;
        if (correctCount == 2) secondFastestId = ans.userId;
      }
    }

    // 2. Update correctness in answers table (Host as authority)
    // Only for non-MCQ, as MCQ is auto-marked by players upon submission
    List<Future> updates = [];
    if (q.questionType != 'multiple_choice') {
      for (var entry in _tempMarks.entries) {
        updates.add(_quizService.updateAnswerCorrectness(
          gameId: widget.gameId,
          questionId: q.id,
          userId: entry.key,
          isCorrect: entry.value == 1,
        ));
      }
    }

    // Wait for verdicts to be stored before moving on
    if (updates.isNotEmpty) {
      await Future.wait(updates);
    }

    // Update answered list in DB
    _answeredIndices.add(currentIdx);
    await supabase
        .from('games')
        .update({'answered_questions': _answeredIndices.toList()}).eq(
            'id', widget.gameId);

    // Clear DB selections immediately so players see "No Answer" on next question
    await supabase
        .from('game_players')
        .update({'last_selection': null}).eq('game_id', widget.gameId);

    if (mounted) {
      setState(() {
        _tempMarks.clear();
      });
      await _updateLeaderboard();

      // Auto-progress to next question with grid delay
      await _nextQuestion();
    }

    return correctCount;
  }

  Future<void> _scoreMyself(int questionIndex) async {
    if (_lastScoredIndex == questionIndex) return;

    final q = _getQuestionForIndex(questionIndex);
    if (q == null) return;

    final myId = supabase.auth.currentUser!.id;

    // Fetch all answers for this question to calculate speed bonus and get host's verdict
    final answers = await _quizService.fetchGameAnswers(widget.gameId);
    final questionAnswers = answers.where((a) => a.questionId == q.id).toList();

    // Find my own answer record
    AnswerModel? myAnswer;
    try {
      myAnswer = questionAnswers.firstWhere((a) => a.userId == myId);
    } catch (_) {
      // User didn't answer
      return;
    }

    // Update state to prevent double scoring
    _lastScoredIndex = questionIndex;
    final isCorrect = myAnswer.isCorrect ?? false;

    if (isCorrect) {
      int pointsToAward = q.points;

      // Calculate speed bonus among those who are correct
      final correctAnswers = questionAnswers.where((a) => a.isCorrect).toList();
      correctAnswers.sort((a, b) => a.answeredAt.compareTo(b.answeredAt));

      if (correctAnswers.isNotEmpty && correctAnswers[0].userId == myId) {
        pointsToAward += 2; // 1st fastest
        debugPrint("SCORING: Awarded 1st place speed bonus (+2) to myself");
      } else if (correctAnswers.length > 1 &&
          correctAnswers[1].userId == myId) {
        pointsToAward += 1; // 2nd fastest
        debugPrint("SCORING: Awarded 2nd place speed bonus (+1) to myself");
      }

      await _quizService.updatePlayerScore(widget.gameId, myId, pointsToAward);

      // Trigger celebration
      if (_celebratedIndex != questionIndex) {
        _celebratedIndex = questionIndex;
      }
    } else {
      // Incorrect answer (deduct points to match solo mode)
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
    return _ImageDetails('assets/baba100new.jpg', 0.8);
  }
}

class _ImageDetails {
  final String imagePath;
  final double heightPercentage;
  _ImageDetails(this.imagePath, this.heightPercentage);
}
