import 'dart:math' as math;

import 'instructions.dart';
import 'online_lobby_page.dart';
import 'quiz_grid_page.dart';
import 'login_page.dart';
import 'add_mcq_page.dart';
import 'add_picture_question.dart';
import 'add_structured_question.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'offline/offline_hosted_page.dart';
import 'services/user_service.dart';
import 'admin_panel.dart';
import 'package:confetti/confetti.dart';

class ModeSelectionPage extends StatefulWidget {
  const ModeSelectionPage({super.key});

  @override
  State<ModeSelectionPage> createState() => _ModeSelectionPageState();
}

class _ModeSelectionPageState extends State<ModeSelectionPage>
    with TickerProviderStateMixin {
  VideoPlayerController? _videoPlayerController;
  late PageController _pageController;
  int _currentImageIndex = 0;
  bool _isAdmin = false;
  late ConfettiController _trophyConfettiController;
  late ConfettiController _megaConfettiController;
  late AnimationController _megaParticleController;

  static const Color primaryPurple = Color(0xFF450E4E);
  static const Color deepPurple = Color.fromARGB(255, 96, 5, 105);
  static const Color pageBg = Color(0xFFEAC7EF);
  static const Color accentGold = Color(0xFFFFD700);
  static const Color accentCyan = Color(0xFF00E5FF);

  final List<String> _imageAssets = [
    'assets/logo2.png',
    'assets/66yrs.png',
    'assets/baba_flags.png',
    'assets/trophy_final_winner.png',
    'assets/image2_3.png',
    'assets/baba100new.jpg',
    'assets/baba_flags.png', // The Finale Slide
  ];

  @override
  void initState() {
    super.initState();

    _pageController = PageController(
      initialPage: _currentImageIndex,
      viewportFraction: 0.82,
    );
    _trophyConfettiController =
        ConfettiController(duration: const Duration(seconds: 1));
    _megaConfettiController =
        ConfettiController(duration: const Duration(seconds: 9));
    _megaParticleController =
        AnimationController(vsync: this, duration: const Duration(seconds: 9));

    Future.delayed(Duration.zero, () {
      _startAutoRotation();
      _checkAdminStatus();
    });
  }

  Future<void> _checkAdminStatus() async {
    final status = await UserService.isAdmin();
    if (mounted) {
      setState(() {
        _isAdmin = status;
      });
    }
  }

  void _startAutoRotation() {
    // Synchronized with the 12s animation (moving slightly before total fade)
    int delaySeconds = (_currentImageIndex == _imageAssets.length - 1) ? 9 : 3;
    Future.delayed(Duration(seconds: delaySeconds), () {
      if (_pageController.hasClients) {
        _currentImageIndex = (_currentImageIndex + 1) % _imageAssets.length;

        _pageController.animateToPage(
          _currentImageIndex,
          duration: const Duration(milliseconds: 850),
          curve: Curves.easeInOutCubic,
        );
      }

      _startAutoRotation();
    });
  }

  @override
  void dispose() {
    _videoPlayerController?.dispose();
    _pageController.dispose();
    _trophyConfettiController.dispose();
    _megaConfettiController.dispose();
    _megaParticleController.dispose();
    super.dispose();
  }

  void _playVideo() {
    _videoPlayerController = VideoPlayerController.asset('assets/babavideo.mp4')
      ..initialize().then((_) {
        if (!mounted) return;

        setState(() {});
        _videoPlayerController!.play();

        showDialog(
          context: context,
          builder: (context) {
            final screenWidth = MediaQuery.of(context).size.width;
            final screenHeight = MediaQuery.of(context).size.height;

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
              ),
              contentPadding: const EdgeInsets.all(14),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: AspectRatio(
                      aspectRatio: _videoPlayerController!.value.aspectRatio,
                      child: VideoPlayer(_videoPlayerController!),
                    ),
                  ),
                  SizedBox(height: screenHeight * 0.01),
                  Image.asset(
                    'assets/Legacy.png',
                    height: screenWidth * 0.18,
                    fit: BoxFit.contain,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    _videoPlayerController?.pause();
                    Navigator.of(context).pop();
                  },
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      });
  }

  bool get _isLoggedIn => Supabase.instance.client.auth.currentSession != null;

  void _requireLoginOrOpen(Widget page) {
    if (!_isLoggedIn) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
      ).then((_) => _checkAdminStatus());
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => page),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEAC7EF),
      appBar: _buildAppBar(context),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final screenHeight = constraints.maxHeight;
          final screenWidth = constraints.maxWidth;

          final bool isExtraShort = screenHeight < 560;
          final bool isShortScreen = screenHeight < 690;

          return Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.all(isExtraShort ? 10 : 14),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1400),
                      child: Column(
                        children: [
                          // Hero and Contribution Section side-by-side
                          IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  flex:
                                      1, // Adjusted flex for better balance on desktop
                                  child: _buildHero(isExtraShort),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  flex: 4, // Adjusted flex
                                  child:
                                      _buildContributionSection(isShortScreen),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 4),

                          // Play Quiz Section Title with decorative line
                          // _sectionTitle('🎮 Play Quiz'),

                          const SizedBox(height: 4),

                          // Responsive Grid for Play Modes
                          LayoutBuilder(
                            builder: (context, gridConstraints) {
                              final double gridWidth = gridConstraints.maxWidth;
                              int crossAxisCount = 1;
                              double aspectRatio = 6.0;

                              if (gridWidth > 1200) {
                                crossAxisCount = 4;
                                aspectRatio =
                                    3.2; // Increased from 2.4 for more compact cards
                              } else if (gridWidth > 900) {
                                crossAxisCount = 3;
                                aspectRatio = 2.8;
                              } else if (gridWidth > 600) {
                                crossAxisCount = 2;
                                aspectRatio = 3.2;
                              }

                              return GridView.count(
                                padding: EdgeInsets.zero,
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                crossAxisCount: crossAxisCount,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 6,
                                childAspectRatio: aspectRatio,
                                children: [
                                  _playModeGridCard(
                                    icon: Icons.wifi_off_outlined,
                                    title: 'Quiz Master (Offline)',
                                    subtitle:
                                        'Host a game on this device (No Internet)',
                                    badge: 'No Login',
                                    badgeColor: Colors.orange,
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              const OfflineHostedPage(),
                                        ),
                                      );
                                    },
                                  ),
                                  _playModeGridCard(
                                    icon: Icons.psychology_outlined,
                                    title: 'Quiz Master (Online)',
                                    subtitle:
                                        'Host a game on this device (Internet)',
                                    badge: 'No Login',
                                    badgeColor: Colors.blue,
                                    onTap: () async {
                                      final int? pCount =
                                          await _showPlayerCountDialog(context);
                                      if (pCount != null) {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => QuizGridPage(
                                              sessionId:
                                                  'session-${DateTime.now().millisecondsSinceEpoch}',
                                              playerCount: pCount,
                                              timerDuration: 60,
                                            ),
                                          ),
                                        );
                                      }
                                    },
                                  ),
                                  _playModeGridCard(
                                    icon: Icons.public_outlined,
                                    title: 'Host A Challenge',
                                    subtitle:
                                        'Create a new room for others to join',
                                    badge: 'Login',
                                    onTap: () {
                                      _requireLoginOrOpen(
                                        const OnlineLobbyPage(
                                          isCreating: true,
                                          isTeamMode: false,
                                        ),
                                      );
                                    },
                                  ),
                                  _playModeGridCard(
                                    icon: Icons.emoji_events_outlined,
                                    title: 'Host Team Game',
                                    subtitle: 'Form teams and compete as teams',
                                    badge: 'Login',
                                    onTap: () {
                                      _requireLoginOrOpen(
                                        const OnlineLobbyPage(
                                          isCreating: true,
                                          isTeamMode: true,
                                        ),
                                      );
                                    },
                                  ),
                                  _playModeGridCard(
                                    icon: Icons.qr_code_scanner_outlined,
                                    title: 'Join A Challenge',
                                    subtitle:
                                        'Enter a game code to join a challenge',
                                    badge: 'Online',
                                    onTap: () {
                                      _requireLoginOrOpen(
                                        const OnlineLobbyPage(
                                          isCreating: false,
                                          isTeamMode:
                                              false, // Will be determined by the game they join
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              );
                            },
                          ),
                          const Align(
                            alignment: Alignment.centerLeft,
                            child: Padding(
                              padding: EdgeInsets.only(left: 4, bottom: 2),
                              child: Text(
                                'Enter Challenge Rooms',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: primaryPurple,
                                ),
                              ),
                            ),
                          ),
                          _buildQuickJoinSection(),

                          //const SizedBox(height: 20),
                          // _sectionTitle('🏆 Legacy Hall of Fame'),
                          // const SizedBox(height: 10),

                          // Legacy Gallery Section
                          // _sectionTitle('📸 Legacy Gallery'),

                          const SizedBox(height: 8),

                          _buildLegacyAwardsCard(
                            isExtraShort
                                ? 65
                                : (isShortScreen
                                    ? 80
                                    : (screenWidth > 1200 ? 160 : 110)),
                            isExtraShort,
                          ),

                          _buildCarouselIndicators(),

                          const SizedBox(height: 6),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              _buildBottomBar(context),
            ],
          );
        },
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    final appBarHeight = (screenHeight * 0.08).clamp(50.0, 66.0);

    return PreferredSize(
      preferredSize: Size.fromHeight(appBarHeight),
      child: AppBar(
        elevation: 0,
        backgroundColor: deepPurple,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.maybePop(context),
        ),
        titleSpacing: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: deepPurple,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Image.asset(
                'assets/logo.png',
                width: (screenWidth * 0.075).clamp(28.0, 38.0),
                height: (appBarHeight * 0.56).clamp(28.0, 38.0),
                errorBuilder: (_, __, ___) =>
                    const Icon(Icons.quiz, color: deepPurple, size: 30),
              ),
            ),
            const SizedBox(width: 8),
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
              ),
            ),
          ],
        ),
        actions: [
          if (_isAdmin)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: deepPurple,
                borderRadius: BorderRadius.circular(20),
              ),
              child: IconButton(
                icon: const Icon(Icons.admin_panel_settings),
                tooltip: 'Admin Panel',
                color: Colors.orange,
                iconSize: appBarHeight * 0.32,
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AdminPanelPage()),
                  );
                },
              ),
            ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: deepPurple,
              borderRadius: BorderRadius.circular(20),
            ),
            child: IconButton(
              icon: const Icon(Icons.info_outline),
              tooltip: 'Instructions',
              color: Colors.white70,
              iconSize: appBarHeight * 0.32,
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const InstructionsPage()),
                );
              },
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: deepPurple,
              borderRadius: BorderRadius.circular(20),
            ),
            child: IconButton(
              icon: const Icon(Icons.exit_to_app),
              tooltip: 'Close App',
              color: Colors.white70,
              iconSize: appBarHeight * 0.32,
              onPressed: () async {
                final shouldQuit = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    title: const Text('Exit App'),
                    content: const Text(
                      'Are you sure you want to exit the application?',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('Cancel'),
                      ),
                      ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryPurple,
                        ),
                        child: const Text('Exit'),
                      ),
                    ],
                  ),
                );

                if (shouldQuit == true) {
                  try {
                    await Supabase.instance.client.auth.signOut();
                  } catch (_) {}

                  if (!mounted) return;

                  if (kIsWeb) {
                    Navigator.of(context).pushReplacementNamed('/login');
                  } else {
                    await SystemNavigator.pop();
                  }
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickJoinSection() {
    final List<int> counts = [2, 3, 4, 5, 8, 10];

    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        itemCount: counts.length,
        separatorBuilder: (_, __) => const SizedBox(width: 11),
        itemBuilder: (context, index) {
          final count = counts[index];
          return InkWell(
            onTap: () {
              _requireLoginOrOpen(
                OnlineLobbyPage(
                  isCreating: false,
                  isTeamMode: false,
                  quickMatchCount: count,
                ),
              );
            },
            borderRadius: BorderRadius.circular(16),
            child: Container(
              width: 85,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [primaryPurple, deepPurple.withOpacity(0.8)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: primaryPurple.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '$count Players',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'Join',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 7,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHero(bool isExtraShort) {
    return GestureDetector(
      onTap: _playVideo,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: isExtraShort ? 8 : 12,
          vertical: isExtraShort ? 2 : 3,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.white.withOpacity(0.5),
              Colors.white.withOpacity(0.2),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: primaryPurple.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/baba100new.jpg',
              height: isExtraShort
                  ? 60
                  : (MediaQuery.of(context).size.width > 1200 ? 54 : 64),
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => Icon(
                Icons.broken_image,
                size: 70,
                color: primaryPurple,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              decoration: BoxDecoration(
                color: primaryPurple.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'Play',
                style: TextStyle(
                  fontSize: 9,
                  color: primaryPurple,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [primaryPurple.withOpacity(0.1), Colors.transparent],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: primaryPurple,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  Widget _playModeGridCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    String? badge,
    Color? badgeColor,
    Gradient? gradient,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 5),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: 14,
            vertical: MediaQuery.of(context).size.width > 900 ? 6 : 8,
          ),
          decoration: BoxDecoration(
            color: primaryPurple,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (badge != null)
                Positioned(
                  right: 0,
                  top: 0,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: (badgeColor ?? accentCyan).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: (badgeColor ?? accentCyan).withOpacity(0.3)),
                    ),
                    child: Text(
                      badge,
                      style: TextStyle(
                        color: badgeColor ?? accentCyan,
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: deepPurple,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withOpacity(0.2)),
                    ),
                    child: Icon(icon, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            letterSpacing: 0.3,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.85),
                            fontSize: 10.5,
                            height: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContributionSection(bool isShortScreen) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.35),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: primaryPurple.withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(Icons.add_box, color: primaryPurple, size: 18),
              const SizedBox(width: 8),
              const Text(
                'Add Questions to Legacy Quiz DB',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: primaryPurple,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Contribution Cards
          Row(
            children: [
              Expanded(
                child: _contributionCard(
                  icon: Icons.quiz,
                  label: 'MCQ',
                  color: Colors.blue,
                  onTap: () => _requireLoginOrOpen(const AddMcqPage()),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _contributionCard(
                  icon: Icons.image,
                  label: 'Picture',
                  color: Colors.green,
                  onTap: () =>
                      _requireLoginOrOpen(const AddPictureQuestionPage()),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _contributionCard(
                  icon: Icons.edit_note,
                  label: 'Structured',
                  color: Colors.orange,
                  onTap: () =>
                      _requireLoginOrOpen(const AddStructuredQuestionPage()),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _contributionCard({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.5),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: deepPurple,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.white, size: 16),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegacyAwardsCard(double carouselHeight, bool isExtraShort) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.white.withOpacity(0.3),
            Colors.white.withOpacity(0.15),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: primaryPurple.withOpacity(0.12)),
      ),
      child: _buildCarousel(carouselHeight),
    );
  }

  Widget _buildCarousel(double carouselHeight) {
    return SizedBox(
      height: carouselHeight,
      child: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: _imageAssets.length,
            onPageChanged: (index) {
              setState(() {
                _currentImageIndex = index;
              });
              if (_imageAssets[index] == 'assets/trophy_final_winner.png') {
                _trophyConfettiController.play();
              } else if (index == _imageAssets.length - 1) {
                _megaConfettiController.play();
                _megaParticleController.forward(from: 0.0);
              }
            },
            itemBuilder: (context, index) {
              return AnimatedBuilder(
                animation: _pageController,
                builder: (context, child) {
                  double value = 0.0;

                  if (_pageController.position.haveDimensions) {
                    value = index - (_pageController.page ?? 0);
                  } else {
                    value = index - _currentImageIndex.toDouble();
                  }

                  value = value.clamp(-1.0, 1.0);

                  final double rotationY = value * math.pi / 3.6;
                  final double scale = 1 - (value.abs() * 0.12);

                  return Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.0015)
                      ..rotateY(rotationY)
                      ..scale(scale),
                    child: Opacity(
                      opacity: (1 - value.abs() * 0.38).clamp(0.45, 1.0),
                      child: Center(
                        child: index == _imageAssets.length - 1
                            ? const SizedBox() // No big picture for the final celebration slide
                            : Image.asset(
                                _imageAssets[index],
                                height: _getImageHeight(
                                    _imageAssets[index], carouselHeight),
                                fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) => const Icon(
                                  Icons.history_edu,
                                  size: 50,
                                  color: primaryPurple,
                                ),
                              ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
          Align(
            alignment: Alignment.center,
            child: ConfettiWidget(
              confettiController: _trophyConfettiController,
              blastDirectionality: BlastDirectionality.explosive,
              shouldLoop: false,
              colors: const [
                Color(0xFFFFD700), // Gold
                Colors.purple,
                Colors.blue,
                Colors.white,
              ],
              minBlastForce: 2,
              maxBlastForce: 5,
              createParticlePath: _drawStarPath,
            ),
          ),
          // Mega PNG Confetti Overlay
          if (_currentImageIndex == _imageAssets.length - 1)
            Positioned.fill(
              child: IgnorePointer(
                child: _buildMegaPngBurst(),
              ),
            ),
          // Mega Paper Confetti
          Align(
            alignment: Alignment.center, // Burst from the center
            child: ConfettiWidget(
              confettiController: _megaConfettiController,
              blastDirectionality: BlastDirectionality.explosive,
              maxBlastForce: 20,
              minBlastForce: 5,
              emissionFrequency: 0.05,
              numberOfParticles: 10,
              gravity: 0.1,
              shouldLoop: false,
              colors: const [
                Color(0xFFFFD700), // Gold
                Colors.purple,
                Colors.blue,
                Colors.white,
              ],
              createParticlePath: _drawStarPath,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMegaPngBurst() {
    return AnimatedBuilder(
      animation: _megaParticleController,
      builder: (context, child) {
        if (!_megaParticleController.isAnimating &&
            _megaParticleController.value == 0) return const SizedBox();

        final List<String> assets = [
          'assets/logo.png',
          'assets/medal.png',
          'assets/medal_2.png',
          'assets/66yrs.png',
          'assets/baba100new.jpg',
          'assets/image2_3.png',
          'assets/trophy_final_winner.png',
          'assets/trophy.png',
          'assets/baba_flags.png',
          'assets/baba_flags2.png',
          'assets/baba_flags3.png',
          'assets/image1.png',
          'assets/image2.png',
          'assets/image3.png',
        ];

        return Stack(
          children: List.generate(14, (index) { // Increased to a balanced 14
            final rand = math.Random(index * 99);
            final progress = _megaParticleController.value;

            // Phase 1: Rapid Convergence (0.0 to 0.15) - MUCH FASTER to avoid blank screen
            // Phase 2: Long Epic Burst (0.15 to 1.0)
            final bool isConverging = progress < 0.15;
            final double convergeSubProgress =
                (progress / 0.15).clamp(0.0, 1.0);
            final double burstSubProgress =
                ((progress - 0.15) / 0.85).clamp(0.0, 1.0);

            final double side = index % 2 == 0 ? 1.0 : -1.0;
            // Start closer to the visible area
            final double startX =
                side * (MediaQuery.of(context).size.width * 0.35);
            final double startY = (rand.nextDouble() - 0.5) * 110.0;

            Offset offset;
            double opacity;
            double scale;
            double rotation;

            if (isConverging) {
              // High-speed rush from sides to center
              final x = startX * (1.0 - convergeSubProgress);
              final y = startY;
              offset = Offset(x, y);
              opacity = (0.2 + convergeSubProgress * 0.8).clamp(0.0, 1.0);
              scale = 0.5 + (convergeSubProgress * 0.3);
              rotation = convergeSubProgress * 2 * math.pi;
            } else {
              // Parabolic Burst: Bank up then fall
              final double count = 24.0;
              // Launch in an upward arc (-0.1pi to -0.9pi) for wider spread
              final angle =
                  -math.pi * 0.1 - (rand.nextDouble() * math.pi * 0.8);
              final speedX = 200.0 +
                  rand.nextDouble() * 350.0; // Slower horizontal
              final speedY = 450.0 +
                  rand.nextDouble() *
                      400.0; // Slower launch for more hang time

              final x = math.cos(angle) * speedX * burstSubProgress;
              // y = v0*t + 1/2 * g * t^2. Reduced gravity (900) for more hang time
              final y = startY +
                  (math.sin(angle) * speedY * burstSubProgress) +
                  (burstSubProgress * burstSubProgress * 800); // Softer gravity (800) for longer float time

              offset = Offset(x, y);
              // Fade out slower at the start, faster at the end
              opacity = (1.0 - math.pow(burstSubProgress, 5)).clamp(0.0, 1.0);
              scale = 0.6 + (rand.nextDouble() * 0.8); // More varied sizes
              rotation = (burstSubProgress * 6 * math.pi); // Tumbling rotation
            }

            return Center(
              child: Transform.translate(
                offset: offset,
                child: Transform.rotate(
                  angle: rotation,
                  child: Transform.scale(
                    scale: scale,
                    child: Opacity(
                      opacity: opacity,
                      child: Image.asset(
                        assets[index % assets.length],
                        width: 45 +
                            (rand.nextDouble() *
                                20), // Balanced size (45-65)
                        height: 45 + (rand.nextDouble() * 20),
                        errorBuilder: (_, __, ___) =>
                            const Icon(Icons.star, color: Colors.yellow),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }

  Path _drawStarPath(Size size) {
    // Vary the size randomly for each particle
    final rand = math.Random();
    final double scaleFactor = 0.4 + rand.nextDouble() * 0.8; // Random size between 40% and 120%
    final double finalWidth = size.width * scaleFactor;
    
    double degToRad(double deg) => deg * (math.pi / 180.0);
    const numberOfPoints = 5;
    final halfWidth = finalWidth / 2;
    final externalRadius = halfWidth;
    final internalRadius = halfWidth / 2.5;
    final degreesPerStep = degToRad(360 / numberOfPoints);
    final halfDegreesPerStep = degreesPerStep / 2;
    final path = Path();
    final fullAngle = degToRad(-90);
    path.moveTo(halfWidth, 0);

    for (double step = 0; step < 360 / numberOfPoints; step++) {
      path.lineTo(
          halfWidth + externalRadius * math.cos(step * degreesPerStep + fullAngle),
          halfWidth + externalRadius * math.sin(step * degreesPerStep + fullAngle));
      path.lineTo(
          halfWidth +
              internalRadius *
                  math.cos(step * degreesPerStep + halfDegreesPerStep + fullAngle),
          halfWidth +
              internalRadius *
                  math.sin(step * degreesPerStep + halfDegreesPerStep + fullAngle));
    }
    path.close();
    return path;
  }

  Widget _buildCarouselIndicators() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_imageAssets.length, (index) {
        final bool active = _currentImageIndex == index;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          width: active ? 20 : 6,
          height: 6,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(3),
            gradient: active
                ? const LinearGradient(
                    colors: [primaryPurple, Color(0xFF673AB7)],
                  )
                : null,
            color: active ? null : Colors.grey.withOpacity(0.4),
          ),
        );
      }),
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final bottomBarHeight = (screenHeight * 0.05).clamp(38.0, 48.0);

    return Container(
      width: double.infinity,
      height: bottomBarHeight,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [primaryPurple, deepPurple],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Text(
        'Developed by FIFMI Middle East (EGEA and Media)',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white70,
          fontSize: (bottomBarHeight * 0.3).clamp(9.0, 10.5),
          fontStyle: FontStyle.italic,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  double _getImageHeight(String asset, double baseHeight) {
    switch (asset) {
      case 'assets/trophy_final_winner.png':
        return baseHeight * 1.05;
      case 'assets/logo2.png':
        return baseHeight * 0.92;
      case 'assets/image2_3.png':
        return baseHeight * 1.05;
      case 'assets/baba100new.jpg':
        return baseHeight * 1.35;
      case 'assets/baba_flags.png':
        return baseHeight * 1.20;
      case 'assets/66yrs.png':
        return baseHeight * 1.25;
      default:
        return baseHeight * 0.8;
    }
  }

  Future<int?> _showPlayerCountDialog(BuildContext context) {
    int selected = 1;
    return showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Number of Players'),
        content: StatefulBuilder(
          builder: (context, setDialogState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('How many players are competing on this device?'),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: selected > 1
                        ? () => setDialogState(() => selected--)
                        : null,
                  ),
                  Text('$selected',
                      style: const TextStyle(
                          fontSize: 24, fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: selected < 10
                        ? () => setDialogState(() => selected++)
                        : null,
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, selected),
              child: const Text('Start Quiz')),
        ],
      ),
    );
  }
}
