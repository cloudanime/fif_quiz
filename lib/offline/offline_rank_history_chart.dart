import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:confetti/confetti.dart';

import '../models/local_models.dart';

class OfflineRankHistoryChart extends StatefulWidget {
  final String gameId;
  final List<Question> questions;
  final List<GamePlayer> players;
  final List<Answer> answers;
  final VoidCallback? onWatchAgain;
  final VoidCallback? onBackToLobby;

  const OfflineRankHistoryChart({
    super.key,
    required this.gameId,
    required this.questions,
    required this.players,
    required this.answers,
    this.onWatchAgain,
    this.onBackToLobby,
  });

  @override
  State<OfflineRankHistoryChart> createState() =>
      OfflineRankHistoryChartState();
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

class OfflineRankHistoryChartState extends State<OfflineRankHistoryChart>
    with TickerProviderStateMixin {
  int _currentStep = 0;
  bool _showWinner = false;
  Timer? _raceTimer;
  late ConfettiController _confettiControllerTop;
  late ConfettiController _confettiControllerBottom;
  late ConfettiController _trophyConfettiController;

  late AnimationController _sparkleController;

  Map<String, List<int>> _scoreHistory = {};
  List<String> _topPlayerIds = [];

  @override
  void initState() {
    super.initState();

    _sparkleController =
        AnimationController(vsync: this, duration: const Duration(seconds: 25))
          ..repeat();
    _confettiControllerTop =
        ConfettiController(duration: const Duration(seconds: 2));
    _confettiControllerBottom =
        ConfettiController(duration: const Duration(seconds: 2));
    _trophyConfettiController =
        ConfettiController(duration: const Duration(seconds: 10));

    _calculateHistory();
  }

  @override
  void dispose() {
    _raceTimer?.cancel();

    _confettiControllerTop.dispose();
    _confettiControllerBottom.dispose();
    _trophyConfettiController.dispose();
    super.dispose();
  }

  void _calculateHistory() {
    Map<String, List<int>> userScores = {};
    for (var player in widget.players) {
      userScores[player.userId] = [0];
    }

    for (var q in widget.questions) {
      final points = q.points;

      for (var player in widget.players) {
        final answer = widget.answers.firstWhere(
          (a) => a.questionId == q.id && a.userId == player.userId,
          orElse: () => Answer(
              id: '',
              gameId: '',
              questionId: '',
              userId: '',
              answer: '',
              isCorrect: 0,
              answeredAt: ''),
        );

        int scoreChange = 0;
        if (answer.id.isNotEmpty) {
          scoreChange = (answer.isCorrect == 1) ? points : -points;
        }
        final lastScore = userScores[player.userId]!.last;
        userScores[player.userId]!.add(lastScore + scoreChange);
      }
    }

    final finalLeaderboard = List<GamePlayer>.from(widget.players)
      ..sort((a, b) => (userScores[b.userId]?.last ?? 0)
          .compareTo(userScores[a.userId]?.last ?? 0));
    _topPlayerIds = finalLeaderboard.map((p) => p.userId).toList();

    _scoreHistory = userScores;
    _startRace();
  }

  void startRace() {
    _startRace();
  }

  void _startRace() {
    _raceTimer?.cancel();
    _currentStep = 0;
    _showWinner = false;

    // Animation speed: faster if many questions
    int ms = widget.questions.length > 10 ? 1000 : 1500;

    _raceTimer = Timer.periodic(Duration(milliseconds: ms), (timer) {
      if (!mounted) return;
      if (_currentStep < widget.questions.length) {
        setState(() {
          _currentStep++;
        });

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
    if (_scoreHistory.isEmpty)
      return const Center(child: Text("Calculating results..."));

    List<_PlayerRaceState> currentStates = _topPlayerIds.map((id) {
      final player = widget.players.firstWhere((p) => p.userId == id);
      final score = _scoreHistory[id]![_currentStep];
      return _PlayerRaceState(
        userId: id,
        name: player.displayName,
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
    final isPlayer1Winner = winners.any((w) =>
        widget.players.isNotEmpty &&
        w.name == widget.players.first.displayName);

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 5, 20, 20),
      decoration: BoxDecoration(
        color: const Color(0xFFEAC7EF), // Lavender background
        borderRadius: BorderRadius.circular(40),
        border: Border.all(color: Colors.yellow, width: 4.0),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: [
              Column(
                children: [
                  if (isFinished)
                    SizedBox(
                      width: constraints.maxWidth * 0.7,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Text Sparkles
                            for (int i = 0; i < 6; i++) _buildTextSparkle(i),
                            // Purple Outline Layer
                            Text(
                              "W I N N E R",
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: constraints.maxWidth > 1200 ? 48 : 32,
                                letterSpacing: 4,
                                foreground: Paint()
                                  ..style = PaintingStyle.stroke
                                  ..strokeWidth = 12
                                  ..strokeJoin = StrokeJoin.round
                                  ..color = const Color(
                                      0xFF450E4E), // Deep Purple Edge
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
                                "W I N N E R",
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                    fontSize:
                                        constraints.maxWidth > 1200 ? 48 : 32,
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
                          const double barHeight = 40;
                          const double spacing = 12;
                          final double maxBarWidth = constraints.maxWidth - 100;
                          final double topPosition =
                              rank * (barHeight + spacing);

                          return AnimatedPositioned(
                            key: ValueKey(state.userId),
                            duration: const Duration(milliseconds: 800),
                            curve: Curves.easeInOut,
                            top: topPosition,
                            left: 0,
                            width: constraints.maxWidth,
                            child: AnimatedOpacity(
                              duration: const Duration(milliseconds: 500),
                              opacity: _showWinner ? 0.12 : 1.0,
                              child: _buildPlayerBar(state,
                                  barWidth:
                                      (state.score / maxScore).clamp(0.2, 1.0) *
                                          maxBarWidth,
                                  barHeight: barHeight,
                                  maxScore: maxScore.toDouble()),
                            ),
                          );
                        }),
                        if (_showWinner && winners.isNotEmpty)
                          AnimatedPositioned(
                            duration: const Duration(milliseconds: 800),
                            curve: Curves.elasticOut,
                            top: 0,
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: Center(
                              child: ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxWidth: 600),
                                child: SingleChildScrollView(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 10),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const SizedBox(height: 2),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          _buildActionButton(
                                            label: "Watch Again",
                                            icon: Icons.play_circle_filled,
                                            onPressed: widget.onWatchAgain ??
                                                startRace,
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
                                            // Background sparkles (Behind)
                                            for (int i = 0; i < 12; i++)
                                              _buildSparkleParticle(i, 12,
                                                  isForeground: false),

                                            // Trophy
                                            TweenAnimationBuilder<double>(
                                              tween:
                                                  Tween(begin: 0.0, end: 1.0),
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
                                                height: (constraints.maxHeight *
                                                        0.58)
                                                    .clamp(250.0, 500.0),
                                                fit: BoxFit.contain,
                                                errorBuilder: (context, e, s) =>
                                                    const Icon(
                                                        Icons.emoji_events,
                                                        color: Colors.yellow,
                                                        size: 140),
                                              ),
                                            ),

                                            // Foreground sparkles (In front)
                                            for (int i = 0; i < 12; i++)
                                              _buildSparkleParticle(i, 12,
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
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 15, horizontal: 15),
                                        decoration: BoxDecoration(
                                          color: const Color(
                                              0xFF450E4E), // Deep Purple
                                          borderRadius:
                                              BorderRadius.circular(50),
                                          border: Border.all(
                                              color: Colors.yellow, width: 3.0),
                                          boxShadow: [
                                            BoxShadow(
                                              color:
                                                  Colors.black.withOpacity(0.2),
                                              blurRadius: 10,
                                              spreadRadius: 2,
                                            ),
                                          ],
                                        ),
                                        child: Column(
                                          children: winners
                                              .map((w) => Padding(
                                                    padding: const EdgeInsets
                                                        .symmetric(vertical: 4),
                                                    child: Text(
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
                                                  ))
                                              .toList(),
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
                                                  color: Colors.yellow,
                                                  width: 3.0),
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
                                                  errorBuilder: (context, e,
                                                          s) =>
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
                                                      fontWeight:
                                                          FontWeight.bold,
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
                    icon: const Icon(Icons.replay,
                        color: Colors.white70, size: 30),
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
        },
      ),
    );
  }

  Widget _buildPlayerBar(_PlayerRaceState state,
      {required double barWidth,
      required double barHeight,
      required double maxScore}) {
    final color =
        Colors.primaries[state.userId.hashCode % Colors.primaries.length];
    return Row(
      children: [
        Expanded(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 800),
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
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: -8,
                top: 8,
                child: Image.asset('assets/medal.png', width: 24, height: 24),
              ),
              Positioned.fill(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 20),
                    child: Text(
                      state.name.toUpperCase(),
                      style: const TextStyle(
                          color: Color(0xFF450E4E),
                          fontWeight: FontWeight.bold,
                          fontSize: 11),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 40,
          child: Text(
            "${state.score}",
            style: TextStyle(
                color: color, fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ),
      ],
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

  Widget _buildTextSparkle(int index) {
    return AnimatedBuilder(
      animation: _sparkleController,
      builder: (context, child) {
        final rand = Random(index * 999);
        final radiusX = 100.0 + rand.nextDouble() * 80.0;
        final radiusY = 15.0 + rand.nextDouble() * 15.0;
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
              size: 6 + rand.nextDouble() * 6,
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
        final radiusX = 140.0 + rand.nextDouble() * 100.0;
        final radiusY = 40.0 + rand.nextDouble() * 40.0;
        final speedMultiplier = (1 + rand.nextInt(2)).toDouble();
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
            (index % 5 - 2) * 25.0 + (sin(angle * 0.5) * radiusY));

        final List<Widget> particleWidgets = [
          const Icon(Icons.star, color: Colors.yellow, size: 14),
          const Icon(Icons.star, color: Colors.white, size: 10),
          Image.asset('assets/logo.png',
              width: 20,
              height: 20,
              errorBuilder: (c, e, s) => const SizedBox()),
          Image.asset('assets/medal.png',
              width: 18,
              height: 18,
              errorBuilder: (c, e, s) => const SizedBox()),
          Image.asset('assets/medal_2.png',
              width: 18,
              height: 18,
              errorBuilder: (c, e, s) => const SizedBox()),
          Image.asset('assets/baba100new.jpg',
              width: 22,
              height: 22,
              errorBuilder: (c, e, s) => const SizedBox()),
          Image.asset('assets/baba_flags.png',
              width: 22,
              height: 22,
              errorBuilder: (c, e, s) => const SizedBox()),
          Image.asset('assets/babaamai.png',
              width: 22,
              height: 22,
              errorBuilder: (c, e, s) => const SizedBox()),
          const Icon(Icons.auto_awesome, color: Colors.amberAccent, size: 16),
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
