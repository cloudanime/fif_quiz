import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:confetti/confetti.dart';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'services/quiz_supabase_service.dart';
import 'models/supabase_models.dart';

class RankHistoryChart extends StatefulWidget {
  final String gameId;
  final List<QuestionModel> questions;
  final List<GamePlayerModel> players;
  final List<GamePlayerModel>? allPlayers; // Full list for team mapping
  final bool isTeamMode;
  final VoidCallback? onWatchAgain;
  final VoidCallback? onBackToLobby;

  final String? adminId;

  const RankHistoryChart({
    super.key,
    required this.gameId,
    required this.questions,
    required this.players,
    this.allPlayers,
    this.isTeamMode = false,
    this.adminId,
    this.onWatchAgain,
    this.onBackToLobby,
  });

  @override
  State<RankHistoryChart> createState() => RankHistoryChartState();
}

final Animatable<double> trophyScaleTween = TweenSequence<double>([
  TweenSequenceItem(
      tween:
          Tween(begin: 0.0, end: 1.2).chain(CurveTween(curve: Curves.easeOut)),
      weight: 70),
  TweenSequenceItem(
      tween: Tween(begin: 1.2, end: 1.0)
          .chain(CurveTween(curve: Curves.easeInOut)),
      weight: 30),
]);

class RankHistoryChartState extends State<RankHistoryChart>
    with TickerProviderStateMixin {
  final SupabaseQuizService _quizService = SupabaseQuizService();
  final supabase = Supabase.instance.client;
  bool _isLoading = true;
  int _currentStep = 0;
  bool _showWinner = false;
  Timer? _raceTimer;
  late ConfettiController _confettiControllerTop;
  late ConfettiController _confettiControllerBottom;
  late ConfettiController _trophyConfettiController;

  late AnimationController _sparkleController;

  Map<String, List<int>> _scoreHistory = {};
  List<String> _topPlayerIds = [];
  final Random _random = Random();

  @override
  void initState() {
    super.initState();

    _sparkleController =
        AnimationController(vsync: this, duration: const Duration(seconds: 25))
          ..repeat();
    _confettiControllerTop =
        ConfettiController(duration: const Duration(seconds: 5));
    _confettiControllerBottom =
        ConfettiController(duration: const Duration(seconds: 5));
    _trophyConfettiController =
        ConfettiController(duration: const Duration(seconds: 10));

    _loadHistoryWithRetry();
  }

  @override
  void dispose() {
    _raceTimer?.cancel();

    _sparkleController.dispose();
    _confettiControllerTop.dispose();
    _confettiControllerBottom.dispose();
    _trophyConfettiController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    try {
      debugPrint(
          "RankHistoryChart: Loading history for gameId: ${widget.gameId}");
      debugPrint(
          "RankHistoryChart: Players count: ${widget.players.length}, isTeamMode: ${widget.isTeamMode}");

      final answers = await _quizService.fetchGameAnswers(widget.gameId);
      debugPrint("RankHistoryChart: Fetched ${answers.length} answers");

      final questionPoints = {for (var q in widget.questions) q.id: q.points};
      final questionIds = widget.questions.map((q) => q.id).toList();

      Map<String, List<int>> stepScores = {}; // Key: UserID or TeamCode

      if (widget.isTeamMode) {
        final teams = widget.players
            .map((p) => p.teamCode ?? p.teamName)
            .where((c) => c != null && c.isNotEmpty)
            .toSet();

        debugPrint(
            "RankHistoryChart: Identified ${teams.length} teams: $teams");

        for (var tCode in teams) {
          stepScores[tCode!] = [0];
        }

        if (teams.isEmpty && widget.players.isNotEmpty) {
          debugPrint(
              "RankHistoryChart: WARNING: Team mode active but no team codes/names found. Falling back to individual players.");
          for (var player in widget.players) {
            stepScores[player.userId] = [0];
          }
        }
      } else {
        for (var player in widget.players) {
          stepScores[player.userId] = [0];
        }
      }

      for (var qId in questionIds) {
        final points = questionPoints[qId] ?? 0;
        final qAnswers = answers.where((a) => a.questionId == qId).toList();
        qAnswers.sort((a, b) => a.answeredAt.compareTo(b.answeredAt));

        String? firstId, secondId;
        int correctFound = 0;
        for (var ans in qAnswers) {
          if (ans.isCorrect) {
            correctFound++;
            if (correctFound == 1) firstId = ans.userId;
            if (correctFound == 2) secondId = ans.userId;
          }
        }

        Map<String, int> roundChanges = {}; // Key: UserID or TeamCode
        if (widget.isTeamMode) {
          for (var tCode in stepScores.keys) {
            roundChanges[tCode] = 0;
          }

          // Track which teams already got their points/bonus this round
          Set<String> teamsProcessed = {};

          // Since qAnswers is sorted by speed, the first member of a team we encounter is the fastest
          for (var ans in qAnswers) {
            // Find the player's team name from the full list if available
            String? tCode;
            if (widget.allPlayers != null) {
              try {
                final p = widget.allPlayers!
                    .firstWhere((p) => p.userId == ans.userId);
                tCode = p.teamCode ?? p.teamName;
              } catch (_) {}
            }

            // Fallback to searching the provided players list (representatives)
            if (tCode == null) {
              try {
                final p =
                    widget.players.firstWhere((p) => p.userId == ans.userId);
                tCode = p.teamCode ?? p.teamName;
              } catch (_) {}
            }

            if (tCode == null || teamsProcessed.contains(tCode)) continue;

            int change = ans.isCorrect ? points : -points;
            if (ans.isCorrect) {
              if (ans.userId == firstId) {
                change += 2;
              } else if (ans.userId == secondId) change += 1;
            }

            roundChanges[tCode] = change;
            teamsProcessed.add(tCode);
          }

          // Handle teams that didn't answer at all (deduct points to be consistent)
          for (var tCode in stepScores.keys) {
            if (!teamsProcessed.contains(tCode)) {
              roundChanges[tCode] = -points;
            }
          }
        } else {
          for (var pId in stepScores.keys) {
            roundChanges[pId] = 0;
          }
          for (var player in widget.players) {
            final answer = qAnswers.firstWhere(
              (a) => a.userId == player.userId,
              orElse: () => AnswerModel(
                  id: '',
                  gameId: '',
                  questionId: '',
                  userId: '',
                  answer: '',
                  isCorrect: false,
                  answeredAt: DateTime.now()),
            );

            if (answer.id.isNotEmpty) {
              int change = answer.isCorrect ? points : -points;
              if (answer.isCorrect) {
                if (answer.userId == firstId) {
                  change += 2;
                } else if (answer.userId == secondId) change += 1;
              }
              roundChanges[player.userId] = change;
            } else {
              roundChanges[player.userId] = -points;
            }
          }
        }

        for (var key in stepScores.keys) {
          final lastScore = stepScores[key]!.last;
          stepScores[key]!.add(lastScore + (roundChanges[key] ?? 0));
        }
      }

      if (widget.isTeamMode) {
        _topPlayerIds = stepScores.keys.toList();
        // Sort teams by final score for ranking
        _topPlayerIds
            .sort((a, b) => stepScores[b]!.last.compareTo(stepScores[a]!.last));
      } else {
        final finalStandings = widget.players.toList()
          ..sort((a, b) => (stepScores[b.userId]?.last ?? 0)
              .compareTo(stepScores[a.userId]?.last ?? 0));
        _topPlayerIds = finalStandings.take(10).map((p) => p.userId).toList();
      }

      if (mounted) {
        setState(() {
          _scoreHistory = stepScores;
          _isLoading = false;
        });
        _startRace();
      }
    } catch (e) {
      debugPrint("RankHistoryChart: Error loading race history: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadHistoryWithRetry({int retries = 1}) async {
    await _loadHistory();
    if (_scoreHistory.isEmpty && retries > 0) {
      debugPrint(
          "RankHistoryChart: No history found, retrying in 2 seconds...");
      await Future.delayed(const Duration(seconds: 2));
      await _loadHistory();
    }
  }

  void startRace() {
    _startRace();
  }

  void _startRace() {
    _raceTimer?.cancel();
    _currentStep = 0;
    setState(() => _showWinner = false);
    _raceTimer = Timer.periodic(const Duration(milliseconds: 1800), (timer) {
      if (!mounted) return;
      if (_currentStep < widget.questions.length) {
        setState(() {
          _currentStep++;
        });

        // When we hit the last step, wait 4 seconds to show final bars before the winner overlay
        if (_currentStep == widget.questions.length) {
          _raceTimer?.cancel();
          Future.delayed(const Duration(seconds: 4), () {
            if (mounted) {
              setState(() {
                _showWinner = true;
                _confettiControllerTop.play();
                _confettiControllerBottom.play();
                _trophyConfettiController.play();
              });
            }
          });
        }
      } else {
        _raceTimer?.cancel();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: Colors.white));
    }

    if (widget.players.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.people_outline, color: Colors.white38, size: 48),
            const SizedBox(height: 16),
            const Text("Waiting for players to join...",
                style: TextStyle(color: Colors.white70, fontSize: 16)),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => _loadHistory(),
              icon: const Icon(Icons.refresh, color: Colors.white),
              label: const Text("Refresh List",
                  style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF450E4E)),
            ),
          ],
        ),
      );
    }

    if (_scoreHistory.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.history, color: Colors.white38, size: 48),
            const SizedBox(height: 16),
            const Text("No history data available for this game",
                style: TextStyle(color: Colors.white70, fontSize: 16)),
            const SizedBox(height: 8),
            const Text("Try refreshing if the game just ended",
                style: TextStyle(color: Colors.white54, fontSize: 12)),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => _loadHistoryWithRetry(),
              icon: const Icon(Icons.refresh, color: Colors.white),
              label: const Text("Refresh Data",
                  style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF450E4E)),
            ),
          ],
        ),
      );
    }

    List<_PlayerRaceState> currentStates = _topPlayerIds.map((id) {
      String displayName = "Unknown";
      if (widget.isTeamMode) {
        try {
          displayName =
              widget.players.firstWhere((p) => p.teamCode == id).teamName ??
                  "Team $id";
        } catch (_) {
          displayName = "Team $id";
        }
      } else {
        try {
          final player = widget.players.firstWhere((p) => p.userId == id);
          displayName = player.displayName ?? player.username ?? "Player";
        } catch (_) {}
      }

      final score = _scoreHistory[id]![_currentStep];
      return _PlayerRaceState(
        userId: id,
        name: displayName,
        score: score,
      );
    }).toList();

    currentStates.sort((a, b) {
      int cmp = b.score.compareTo(a.score);
      if (cmp == 0) return a.name.compareTo(b.name);
      return cmp;
    });

    int maxScore = 0;
    for (var s in currentStates) {
      if (s.score > maxScore) maxScore = s.score;
    }
    if (maxScore <= 0) maxScore = 1;

    final isFinished = _currentStep == widget.questions.length;
    final maxFinalScore =
        currentStates.isNotEmpty ? currentStates.first.score : -1;
    final winners = currentStates
        .where(
            (s) => isFinished && s.score == maxFinalScore && maxFinalScore > 0)
        .toList();
    final winnersCount = winners.length;
    final isCurrentUserWinner =
        winners.any((w) => w.userId == supabase.auth.currentUser?.id);

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
      decoration: BoxDecoration(
        color: const Color(0xFFEAC7EF), // Lavender background
        borderRadius: BorderRadius.circular(40),
        border: Border.all(color: Colors.yellow, width: 4.0),
      ),
      child: LayoutBuilder(builder: (context, constraints) {
        final double maxBarWidth = constraints.maxWidth - 120;
        return Stack(
          children: [
            Column(
              children: [
                // Sparkle Header
                if (isFinished)
                  SizedBox(
                    width: constraints.maxWidth * 0.7,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Text Sparkles
                          for (int i = 0; i < 8; i++) _buildTextSparkle(i),
                          // Purple Outline Layer
                          Text(
                            winnersCount > 1
                                ? "W I N N E R S"
                                : winnersCount == 1
                                    ? "W I N N E R"
                                    : "G A M E  O V E R",
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: constraints.maxWidth > 1200 ? 48 : 36,
                              letterSpacing: 4,
                              foreground: Paint()
                                ..style = PaintingStyle.stroke
                                ..strokeWidth = 12
                                ..strokeJoin = StrokeJoin.round
                                ..color =
                                    const Color(0xFF450E4E), // Deep Purple Edge
                            ),
                          ),
                          // Golden Fill Layer
                          ShaderMask(
                            shaderCallback: (bounds) => const LinearGradient(
                              colors: [
                                Color(0xFFB8860B), // Dark Gold
                                Color(0xFFFFD700), // Gold
                                Color(0xFFFFF4B1), // Shine
                                Color(0xFFFFD700), // Gold
                                Color(0xFFB8860B), // Dark Gold
                              ],
                              stops: [0.0, 0.3, 0.5, 0.7, 1.0],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ).createShader(bounds),
                            child: Text(
                              winnersCount > 1
                                  ? "W I N N E R S"
                                  : winnersCount == 1
                                      ? "W I N N E R"
                                      : "G A M E  O V E R",
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize:
                                      constraints.maxWidth > 1200 ? 48 : 36,
                                  letterSpacing: 4,
                                  shadows: [
                                    const Shadow(
                                        color: Colors.black45,
                                        blurRadius: 10,
                                        offset: Offset(2, 2)),
                                    Shadow(
                                        color: Colors.orange.withOpacity(0.3),
                                        blurRadius: 20),
                                  ]),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Text(
                    "QUESTION $_currentStep / ${widget.questions.length}",
                    style: const TextStyle(
                        color: Colors.white38,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        letterSpacing: 2),
                  ),

                const SizedBox(height: 5),

                Expanded(
                  child: Stack(
                    children: [
                      ...currentStates.map((state) {
                        final rank = currentStates.indexOf(state);
                        const double barHeight = 44;
                        const double spacing = 14;
                        final double topPosition = rank * (barHeight + spacing);
                        final color = Colors.primaries[
                            _topPlayerIds.indexOf(state.userId) %
                                Colors.primaries.length];
                        final isWinner = isFinished &&
                            state.score == maxFinalScore &&
                            maxFinalScore > 0;

                        return AnimatedPositioned(
                          key: ValueKey(state.userId),
                          duration: const Duration(milliseconds: 1200),
                          curve: Curves.easeInOut,
                          top: topPosition,
                          left: 0,
                          width: constraints.maxWidth,
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 800),
                            opacity: _showWinner
                                ? 0.12
                                : 1.0, // Subtle visibility at the end
                            child: _buildPlayerBar(
                              state,
                              color,
                              barWidth:
                                  (state.score / maxScore).clamp(0.2, 1.0) *
                                      maxBarWidth,
                              barHeight: barHeight,
                              maxScore: maxScore.toDouble(),
                              isWinner: isWinner,
                              isFinished: isFinished,
                            ),
                          ),
                        );
                      }),

                      // 2. Render Consolidated Winners Box
                      if (_showWinner)
                        AnimatedPositioned(
                          duration: const Duration(milliseconds: 1000),
                          curve: Curves.elasticOut,
                          top: 0,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 600),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SizedBox(height: 2),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      _buildActionButton(
                                        label: "Watch Again",
                                        icon: Icons.play_circle_filled,
                                        onPressed:
                                            widget.onWatchAgain ?? startRace,
                                        color1: const Color(0xFFFFD54F),
                                        color2: const Color(0xFFF57C00),
                                      ),
                                      const SizedBox(width: 20),
                                      _buildActionButton(
                                        label: "Back to lobby",
                                        icon: Icons.exit_to_app,
                                        onPressed: widget.onBackToLobby,
                                        color1: const Color(0xFFFFD54F),
                                        color2: const Color(0xFFF57C00),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 5),
                                  // 1. Trophy on top with sparkles around it
                                  RepaintBoundary(
                                    child: Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        // Background sparkles (Behind the trophy)
                                        for (int i = 0; i < 20; i++)
                                          _buildSparkleParticle(i, 20,
                                              isForeground: false),

                                        // The Trophy in the middle
                                        TweenAnimationBuilder<double>(
                                          tween: Tween(begin: 0.0, end: 1.0),
                                          duration: const Duration(
                                              milliseconds: 1200),
                                          builder: (context, val, child) {
                                            return Transform.scale(
                                              scale: trophyScaleTween
                                                  .transform(val),
                                              child: child,
                                            );
                                          },
                                          child: Image.asset(
                                            'assets/trophy_final_winner.png',
                                            height:
                                                (constraints.maxHeight * 0.58)
                                                    .clamp(250.0, 500.0),
                                            fit: BoxFit.contain,
                                            errorBuilder: (context, e, s) =>
                                                const Icon(Icons.emoji_events,
                                                    color: Colors.yellow,
                                                    size: 120),
                                          ),
                                        ),

                                        // Foreground sparkles (In front of the trophy)
                                        for (int i = 0; i < 20; i++)
                                          _buildSparkleParticle(i, 20,
                                              isForeground: true),

                                        // Paper Confetti Burst
                                        ConfettiWidget(
                                          confettiController:
                                              _trophyConfettiController,
                                          blastDirectionality:
                                              BlastDirectionality.explosive,
                                          numberOfParticles: 12,
                                          emissionFrequency: 0.05,
                                          shouldLoop: false,
                                          colors: const [
                                            Colors.green,
                                            Colors.blue,
                                            Colors.pink,
                                            Colors.orange,
                                            Colors.purple,
                                            Colors.yellow,
                                            Color(0xFFFFD700), // Gold
                                          ],
                                          createParticlePath:
                                              _drawPaperConfettiPath,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  // 2. Names Box below trophy
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 15, horizontal: 15),
                                    decoration: BoxDecoration(
                                      color: const Color(
                                          0xFF450E4E), // Deep Purple
                                      borderRadius: BorderRadius.circular(50),
                                      border: Border.all(
                                          color: Colors.yellow, width: 3.0),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.2),
                                          blurRadius: 10,
                                          spreadRadius: 2,
                                        ),
                                      ],
                                    ),
                                    child: Column(
                                      children: winners.isNotEmpty
                                          ? winners.map((w) {
                                              // Find all players in this team
                                              String memberNames = "";
                                              if (widget.isTeamMode) {
                                                final members = widget.players
                                                    .where((p) =>
                                                        p.teamCode == w.userId)
                                                    .map((p) =>
                                                        p.displayName ??
                                                        p.username ??
                                                        "Player")
                                                    .toList();
                                                memberNames =
                                                    members.join(", ");
                                              }

                                              return Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        vertical: 4),
                                                child: Column(
                                                  children: [
                                                    Text(
                                                      w.name.toUpperCase(),
                                                      textAlign:
                                                          TextAlign.center,
                                                      style: const TextStyle(
                                                        color: Colors.white,
                                                        fontWeight:
                                                            FontWeight.w900,
                                                        fontSize: 22,
                                                        letterSpacing: 2,
                                                        shadows: [
                                                          Shadow(
                                                              color: Colors
                                                                  .black26,
                                                              blurRadius: 4,
                                                              offset:
                                                                  Offset(2, 2))
                                                        ],
                                                      ),
                                                    ),
                                                    if (widget.isTeamMode &&
                                                        memberNames.isNotEmpty)
                                                      Text(
                                                        memberNames,
                                                        textAlign:
                                                            TextAlign.center,
                                                        style: TextStyle(
                                                          color: Colors.white
                                                              .withOpacity(0.9),
                                                          fontWeight:
                                                              FontWeight.w500,
                                                          fontSize: 10,
                                                          fontStyle:
                                                              FontStyle.italic,
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                              );
                                            }).toList()
                                          : [
                                              const Padding(
                                                padding: EdgeInsets.symmetric(
                                                    vertical: 20),
                                                child: Text(
                                                  "NO ONE SCORED THIS ROUND",
                                                  textAlign: TextAlign.center,
                                                  style: TextStyle(
                                                    color: Colors.white70,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 16,
                                                    letterSpacing: 1.2,
                                                  ),
                                                ),
                                              )
                                            ],
                                    ),
                                  ),
                                  const SizedBox(height: 15),
                                  if (currentStates.length > 1)
                                    () {
                                      return Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 14, vertical: 12),
                                        decoration: BoxDecoration(
                                          color: const Color(
                                              0xFFFDEFFF), // Light Lavender
                                          borderRadius:
                                              BorderRadius.circular(50),
                                          border: Border.all(
                                              color: Colors.yellow, width: 3.0),
                                          boxShadow: [
                                            BoxShadow(
                                                color: Colors.black
                                                    .withOpacity(0.05),
                                                blurRadius: 4,
                                                offset: const Offset(0, 2)),
                                          ],
                                        ),
                                        child: Row(
                                          children: [
                                            Image.asset(
                                              'assets/medal_2.png',
                                              width: 40,
                                              height: 40,
                                              errorBuilder: (context, e, s) =>
                                                  const Icon(Icons.stars,
                                                      color: Colors.orange,
                                                      size: 30),
                                            ),
                                            const SizedBox(width: 12),
                                            const Expanded(
                                              child: Text(
                                                "All other players won a participant's medal",
                                                style: TextStyle(
                                                  color: Color(0xFF450E4E),
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 14,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }(),
                                  const SizedBox(height: 5),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            if (isFinished)
              Positioned(
                top: 10,
                right: 10,
                child: IconButton(
                  icon:
                      const Icon(Icons.replay, color: Colors.white70, size: 30),
                  onPressed: startRace,
                  tooltip: 'Replay Animation',
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
        );
      }),
    );
  }

  Widget _buildActionButton({
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
    required Color color1,
    required Color color2,
  }) {
    return Container(
      height: 50,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [color1, color2]),
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
              color: color2.withOpacity(0.4),
              blurRadius: 8,
              offset: const Offset(0, 4)),
        ],
      ),
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, color: Colors.purple.shade900, size: 14),
        label: Text(
          label,
          style: TextStyle(
              color: Colors.purple.shade900,
              fontWeight: FontWeight.bold,
              fontSize: 11),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          minimumSize: const Size(0, 50),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        ),
      ),
    );
  }

  Widget _buildPlayerBar(_PlayerRaceState state, Color color,
      {required double barWidth,
      required double barHeight,
      required double maxScore,
      bool isWinner = false,
      bool isFinished = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Expanded(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 1000),
                width: barWidth,
                height: barHeight,
                decoration: BoxDecoration(
                  color: const Color(0xFFFDEFFF),
                  border: Border.all(color: color.withOpacity(0.5), width: 1.5),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.05), blurRadius: 4),
                  ],
                ),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: (state.score / maxScore).clamp(0.01, 1.0),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [color.withOpacity(0.6), color],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: -10,
                top: 5,
                child: Image.asset(
                  (isFinished && !isWinner)
                      ? 'assets/medal_2.png'
                      : 'assets/medal.png',
                  width: 24,
                  height: 24,
                  errorBuilder: (context, e, s) => Icon(
                    (isFinished && !isWinner)
                        ? Icons.stars
                        : Icons.emoji_events,
                    color: (isFinished && !isWinner)
                        ? Colors.orange
                        : Colors.yellow,
                    size: 20,
                  ),
                ),
              ),
              Positioned.fill(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 25),
                    child: Text(
                      state.name.toUpperCase(),
                      style: const TextStyle(
                        color: Color(0xFF450E4E),
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 50,
          child: Text(
            "${state.score}",
            style: TextStyle(
                color: color, fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ),
      ],
    );
  }

  Widget _buildTextSparkle(int index) {
    return AnimatedBuilder(
      animation: _sparkleController,
      builder: (context, child) {
        final rand = Random(index * 999);
        final radiusX = 120.0 + rand.nextDouble() * 100.0;
        final radiusY = 20.0 + rand.nextDouble() * 20.0;
        final speed = 0.5 + rand.nextDouble() * 1.5;
        final phase = rand.nextDouble() * 2 * pi;

        final angle = phase + (_sparkleController.value * 2 * pi * speed);
        final offset = Offset(cos(angle) * radiusX, sin(angle) * radiusY);

        final opacity =
            (sin(_sparkleController.value * 2 * pi * 8 + index) + 1) / 2;

        return Transform.translate(
          offset: offset,
          child: Opacity(
            opacity: opacity.clamp(0.2, 1.0),
            child: Icon(
              rand.nextBool() ? Icons.star : Icons.auto_awesome,
              color: rand.nextBool() ? Colors.yellow : Colors.white,
              size: 8 + rand.nextDouble() * 8,
            ),
          ),
        );
      },
    );
  }

  Widget _buildSparkleParticle(int index, int total,
      {required bool isForeground}) {
    return AnimatedBuilder(
      animation: _sparkleController,
      builder: (context, child) {
        final rand = Random(index * 777);
        final radiusX = 160.0 + rand.nextDouble() * 120.0;
        final radiusY = 50.0 + rand.nextDouble() * 50.0;
        final speedMultiplier = (1 + rand.nextInt(2))
            .toDouble(); // Ensures 1 or 2 full 360s per cycle
        final initialPhase = rand.nextDouble() * 2 * pi;

        final angle = initialPhase +
            (_sparkleController.value * 2 * pi * speedMultiplier);
        final depth = sin(angle);

        final bool shouldShow = isForeground ? depth >= 0 : depth < 0;
        if (!shouldShow) return const SizedBox.shrink();

        final scale = 0.4 + (depth + 1) / 2 * 1.0;
        final depthOpacity = 0.1 + (depth + 1) / 2 * 0.9;
        final flickerOpacity =
            (sin(_sparkleController.value * 2 * pi * 4 + index) + 1) /
                2; // Slower flicker

        final offset = Offset(cos(angle) * radiusX,
            (index % 6 - 3) * 25.0 + (sin(angle * 0.5) * radiusY));

        final List<Widget> particleWidgets = [
          const Icon(Icons.star, color: Colors.yellow, size: 16),
          const Icon(Icons.star, color: Colors.white, size: 12),
          Image.asset('assets/logo.png',
              width: 24,
              height: 24,
              errorBuilder: (c, e, s) => const SizedBox()),
          Image.asset('assets/logo2.png',
              width: 24,
              height: 24,
              errorBuilder: (c, e, s) => const SizedBox()),
          Image.asset('assets/medal.png',
              width: 22,
              height: 22,
              errorBuilder: (c, e, s) => const SizedBox()),
          Image.asset('assets/medal_2.png',
              width: 22,
              height: 22,
              errorBuilder: (c, e, s) => const SizedBox()),
          Image.asset('assets/baba100new.png',
              width: 25,
              height: 25,
              errorBuilder: (c, e, s) => const SizedBox()),
          Image.asset('assets/baba_flags.png',
              width: 25,
              height: 25,
              errorBuilder: (c, e, s) => const SizedBox()),
          Image.asset('assets/baba_flags2.png',
              width: 25,
              height: 25,
              errorBuilder: (c, e, s) => const SizedBox()),
          Image.asset('assets/baba_flags3.png',
              width: 25,
              height: 25,
              errorBuilder: (c, e, s) => const SizedBox()),
          Image.asset('assets/babaamai.png',
              width: 25,
              height: 25,
              errorBuilder: (c, e, s) => const SizedBox()),
          Image.asset('assets/66yrs.png',
              width: 25,
              height: 25,
              errorBuilder: (c, e, s) => const SizedBox()),
          Image.asset('assets/trophy.png',
              width: 25,
              height: 25,
              errorBuilder: (c, e, s) => const SizedBox()),
          Image.asset('assets/image1.png',
              width: 22,
              height: 22,
              errorBuilder: (c, e, s) => const SizedBox()),
          Image.asset('assets/image2.png',
              width: 22,
              height: 22,
              errorBuilder: (c, e, s) => const SizedBox()),
          Image.asset('assets/image3.png',
              width: 22,
              height: 22,
              errorBuilder: (c, e, s) => const SizedBox()),
          const Icon(Icons.auto_awesome, color: Colors.amberAccent, size: 18),
        ];

        return Transform.translate(
          offset: offset,
          child: Transform.scale(
            scale: scale,
            child: Transform.rotate(
              angle: _sparkleController.value * 2 * pi * 4, // Slower spin
              child: Opacity(
                opacity: (depthOpacity * flickerOpacity).clamp(0.1, 1.0),
                child: particleWidgets[index % particleWidgets.length],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Draws a rectangular "paper" confetti shape
  Path _drawPaperConfettiPath(Size size) {
    final path = Path();
    path.addRect(Rect.fromLTWH(0, 0, size.width, size.height * 0.4));
    return path;
  }
}

class _PlayerRaceState {
  final String userId;
  final String name;
  final int score;
  _PlayerRaceState(
      {required this.userId, required this.name, required this.score});
}
