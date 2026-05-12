import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:confetti/confetti.dart';

class WebRankHistoryChart extends StatefulWidget {
  final int playerCount;
  final List<List<int>> scoreHistory; // [playerIndex][step]
  final VoidCallback? onWatchAgain;
  final VoidCallback? onBackToLobby;

  const WebRankHistoryChart({
    super.key,
    required this.playerCount,
    required this.scoreHistory,
    this.onWatchAgain,
    this.onBackToLobby,
  });

  @override
  State<WebRankHistoryChart> createState() => WebRankHistoryChartState();
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

class WebRankHistoryChartState extends State<WebRankHistoryChart>
    with TickerProviderStateMixin {
  int _currentStep = 0;
  bool _showWinner = false;
  Timer? _raceTimer;
  late ConfettiController _confettiController;
  late ConfettiController _trophyConfettiController;

  late AnimationController _sparkleController;

  List<int> _topPlayerIndices = [];

  @override
  void initState() {
    super.initState();

    _sparkleController =
        AnimationController(vsync: this, duration: const Duration(seconds: 25))
          ..repeat();
    _confettiController =
        ConfettiController(duration: const Duration(seconds: 2));
    _trophyConfettiController =
        ConfettiController(duration: const Duration(seconds: 10));

    // Initial order
    _topPlayerIndices = List.generate(widget.playerCount, (i) => i);
    _startRace();
  }

  @override
  void dispose() {
    _raceTimer?.cancel();

    _sparkleController.dispose();
    _confettiController.dispose();
    _trophyConfettiController.dispose();
    super.dispose();
  }

  void startRace() {
    _startRace();
  }

  void _startRace() {
    _raceTimer?.cancel();
    _currentStep = 0;
    _showWinner = false;

    if (widget.scoreHistory.isEmpty || widget.scoreHistory[0].isEmpty) return;
    final int totalSteps = widget.scoreHistory[0].length - 1;

    int ms = totalSteps > 10 ? 1000 : 1500;

    _raceTimer = Timer.periodic(Duration(milliseconds: ms), (timer) {
      if (!mounted) return;
      if (_currentStep < totalSteps) {
        setState(() {
          _currentStep++;
        });

        if (_currentStep == totalSteps) {
          _raceTimer?.cancel();
          Future.delayed(const Duration(seconds: 4), () {
            if (mounted) {
              setState(() {
                _showWinner = true;
                _confettiController.play();
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
    if (widget.scoreHistory.isEmpty) {
      return const Center(
          child: Text("No history data available for this game",
              style: TextStyle(color: Colors.white70)));
    }
    if (widget.scoreHistory[0].isEmpty) {
      return const Center(
          child: Text("No history data found",
              style: TextStyle(color: Colors.white70)));
    }

    final int totalSteps = widget.scoreHistory[0].length - 1;

    List<_PlayerRaceState> currentStates =
        List.generate(widget.playerCount, (i) {
      // Safely access score history
      int step = _currentStep;
      if (step >= widget.scoreHistory[i].length) {
        step = widget.scoreHistory[i].length - 1;
      }
      final score = widget.scoreHistory[i][step];
      return _PlayerRaceState(
        index: i,
        name: "Player ${i + 1}",
        score: score,
      );
    });

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

    final isFinished = _currentStep == totalSteps;
    final maxFinalScore =
        currentStates.isNotEmpty ? currentStates.first.score : -1;
    final winners = currentStates
        .where(
            (s) => isFinished && s.score == maxFinalScore && maxFinalScore > 0)
        .toList();
    final winnersCount = winners.length;
    final isPlayer1Winner = winners.any((w) => w.index == 0);

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
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
                              winnersCount > 1
                                  ? "W I N N E R S"
                                  : winnersCount == 1
                                      ? "W I N N E R"
                                      : "G A M E  O V E R",
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 36,
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
                                winnersCount > 1
                                    ? "W I N N E R S"
                                    : winnersCount == 1
                                        ? "W I N N E R"
                                        : "G A M E  O V E R",
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 36,
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
                      "QUESTION $_currentStep / $totalSteps",
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
                          final double maxBarWidth = constraints.maxWidth - 120;
                          final double topPosition =
                              rank * (barHeight + spacing);
                          final color = Colors
                              .primaries[state.index % Colors.primaries.length];

                          return AnimatedPositioned(
                            key: ValueKey(state.index),
                            duration: const Duration(milliseconds: 1200),
                            curve: Curves.easeInOut,
                            top: topPosition,
                            left: 0,
                            width: constraints.maxWidth,
                            child: AnimatedOpacity(
                              duration: const Duration(milliseconds: 800),
                              opacity: _showWinner ? 0.12 : 1.0,
                              child: _buildPlayerBar(
                                state,
                                color,
                                barWidth:
                                    (state.score / maxScore).clamp(0.2, 1.0) *
                                        maxBarWidth,
                                barHeight: barHeight,
                                maxScore: maxScore.toDouble(),
                                isWinner: isFinished &&
                                    state.score == maxFinalScore &&
                                    maxFinalScore > 0,
                                isFinished: isFinished,
                              ),
                            ),
                          );
                        }),
                        if (_showWinner)
                          AnimatedPositioned(
                            duration: const Duration(milliseconds: 1000),
                            curve: Curves.elasticOut,
                            top: 0,
                            left: constraints.maxWidth * 0.1,
                            right: constraints.maxWidth * 0.1,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const SizedBox(height: 2),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceEvenly,
                                  children: [
                                    _buildActionButton(
                                      label: "Watch Again",
                                      icon: Icons.play_circle_filled,
                                      onPressed:
                                          widget.onWatchAgain ?? startRace,
                                      color1: const Color(0xFFFFD54F),
                                      color2: const Color(0xFFF57C00),
                                    ),
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
                                RepaintBoundary(
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      // Background sparkles (Behind)
                                      // Background sparkles (Behind)
                                      for (int i = 0; i < 20; i++)
                                        _buildSparkleParticle(i, 20,
                                            isForeground: false),

                                      // Trophy in the middle
                                      TweenAnimationBuilder<double>(
                                        tween: Tween(begin: 0.0, end: 1.0),
                                        duration:
                                            const Duration(milliseconds: 1200),
                                        builder: (context, val, child) {
                                          return Transform.scale(
                                            scale:
                                                trophyScaleTween.transform(val),
                                            child: child,
                                          );
                                        },
                                        child: Image.asset(
                                          'assets/trophy_final_winner.png',
                                          height: (constraints.maxHeight * 0.58)
                                              .clamp(250.0, 500.0),
                                          fit: BoxFit.contain,
                                          errorBuilder: (context, e, s) =>
                                              const Icon(Icons.emoji_events,
                                                  color: Colors.yellow,
                                                  size: 120),
                                        ),
                                      ),

                                      // Foreground sparkles (In front)
                                      // Foreground sparkles (In front)
                                      for (int i = 0; i < 20; i++)
                                        _buildSparkleParticle(i, 20,
                                            isForeground: true),

                                      // Paper Confetti Burst
                                      ConfettiWidget(
                                        confettiController:
                                            _trophyConfettiController,
                                        blastDirectionality:
                                            BlastDirectionality.explosive,
                                        emissionFrequency: 0.05,
                                        numberOfParticles: 12,
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
                                    color:
                                        const Color(0xFF450E4E), // Deep Purple
                                    borderRadius: BorderRadius.circular(50),
                                    border: Border.all(
                                        color: Colors.yellow, width: 2.0),
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
                                        ? winners
                                            .map((w) => Padding(
                                                  padding: const EdgeInsets
                                                      .symmetric(vertical: 4),
                                                  child: Text(
                                                    w.name.toUpperCase(),
                                                    textAlign: TextAlign.center,
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontWeight:
                                                          FontWeight.w900,
                                                      fontSize: 22,
                                                      letterSpacing: 2,
                                                      shadows: [
                                                        Shadow(
                                                            color:
                                                                Colors.black26,
                                                            blurRadius: 4,
                                                            offset:
                                                                Offset(2, 2))
                                                      ],
                                                    ),
                                                  ),
                                                ))
                                            .toList()
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
                                        borderRadius: BorderRadius.circular(50),
                                        border: Border.all(
                                            color: const Color(0xFF450E4E)
                                                .withOpacity(0.3),
                                            width: 1.5),
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
                  child: Stack(
                    children: [
                      Align(
                        alignment: Alignment.topCenter,
                        child: ConfettiWidget(
                          confettiController: _confettiController,
                          blastDirection: 1.57, // Down
                          maxBlastForce: 20,
                          minBlastForce: 10,
                          emissionFrequency: 0.05,
                          numberOfParticles: 30,
                          gravity: 0.3,
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
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: ConfettiWidget(
                          confettiController: _confettiController,
                          blastDirection: -1.57, // Up
                          maxBlastForce: 20,
                          minBlastForce: 10,
                          emissionFrequency: 0.05,
                          numberOfParticles: 30,
                          gravity: 0.3,
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
                    ],
                  ),
                ),
              ),
            ],
          );
        },
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
                        color: Colors.white,
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
            (index % 5 - 2) * 28.0 + (sin(angle * 0.5) * radiusY));

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
              angle: _sparkleController.value * 2 * pi * 4, // Slower
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
  final int index;
  final String name;
  final int score;
  _PlayerRaceState(
      {required this.index, required this.name, required this.score});
}
