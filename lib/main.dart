import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';
import 'services/user_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'instructions.dart';
import 'quiz_grid_page.dart';
import 'add_mcq_page.dart';
import 'add_picture_question.dart';
import 'add_structured_question.dart';
import 'admin_panel.dart';
import 'login_page.dart';

import 'services/supabase_service.dart';
import 'mode_selection_page.dart';
import 'fetch_Mixed_Questions.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // TODO: Replace with your actual Supabase URL and anon key
  await initializeSupabase();
  // Ensure we start with a fresh session (log out on start)
  await Supabase.instance.client.auth.signOut();

  runApp(const QuizApp());
}

class QuizApp extends StatefulWidget {
  const QuizApp({super.key});

  @override
  State<QuizApp> createState() => _QuizAppState();
}

class _QuizAppState extends State<QuizApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Start periodic session check
    _startSessionCheck();
  }

  void _startSessionCheck() {
    Future.delayed(const Duration(minutes: 2), () async {
      if (!mounted) return;
      await _validateCurrentSession();
      _startSessionCheck(); // Schedule next check
    });
  }

  Future<void> _validateCurrentSession() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final localId = prefs.getString('local_session_id');
      if (localId == null) return;

      final isValid = await UserService.isSessionValid(localId);
      if (!isValid) {
        // Session mismatch - another device logged in
        await Supabase.instance.client.auth.signOut();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content:
                  Text('Your account has been logged in on another device.'),
              backgroundColor: Colors.red,
            ),
          );
          // Redirect to home/login
          Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
        }
      }
    } catch (e) {
      debugPrint('Session validation error: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Log out when the app is closed/detached
    if (state == AppLifecycleState.detached) {
      Supabase.instance.client.auth.signOut();
    } else if (state == AppLifecycleState.resumed) {
      // Re-validate session when user returns to app
      _validateCurrentSession();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Legacy Quiz',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.purple,
        scaffoldBackgroundColor: Colors.white,
        visualDensity: VisualDensity.compact,
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF450E4E),
          elevation: 0,
          iconTheme: IconThemeData(color: Colors.yellow),
          titleTextStyle: TextStyle(
            color: Colors.yellow,
            fontWeight: FontWeight.bold,
            fontSize: 22,
          ),
        ),
        iconButtonTheme: IconButtonThemeData(
          style: IconButton.styleFrom(
            padding:
                const EdgeInsets.all(4), // Reduce default padding from 8 to 4
            minimumSize: const Size(32, 32),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF450E4E),
            foregroundColor: Colors.white,
            textStyle: const TextStyle(fontWeight: FontWeight.bold),
            shape: const StadiumBorder(),
          ),
        ),
      ),
      home: const AuthGate(),
      routes: {
        '/session': (context) => const SessionPage(),
        '/login': (context) => const LoginPage(),
      },
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    // ModeSelectionPage is now the entry point.
    // Login will be handled inside ModeSelectionPage for specific features.
    return const ModeSelectionPage();
  }
}

class SessionPage extends StatefulWidget {
  const SessionPage({super.key});

  @override
  _SessionPageState createState() => _SessionPageState();
}

class _SessionPageState extends State<SessionPage> {
  String? sessionId;
  bool isLoading = false;
  bool isCheckingAdmin = false;
  String error = '';
  int playerCount = 1;
  int timerDuration = 60;
  bool isAdmin = false;
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  VideoPlayerController? _videoPlayerController;
  late PageController _pageController;
  int _currentImageIndex = 0;

  final List<String> _imageAssets = [
    'assets/logo2.png',
    'assets/66yrs.png',
    'assets/trophy_final_winner.png',
    'assets/image2_3.png',
    'assets/baba100new.jpg',
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController(
      initialPage: _currentImageIndex,
      viewportFraction: 0.85,
    );
    Future.delayed(Duration.zero, _startAutoRotation);
    checkAdmin();
  }

  Future<void> checkAdmin() async {
    setState(() {
      isCheckingAdmin = true;
      error = '';
    });

    try {
      final isUserAdmin = await UserService.isAdmin();
      setState(() {
        isAdmin = isUserAdmin;
        error = '';
      });
    } catch (e) {
      setState(() {
        error = 'Error checking admin status: $e';
      });
    } finally {
      setState(() {
        isCheckingAdmin = false;
      });
    }
  }

  void createSession() async {
    setState(() {
      isLoading = true;
      error = '';
    });

    try {
      sessionId = await QuizService.createSession();
      navigateToPage(
        QuizGridPage(
          sessionId: sessionId!,
          playerCount: playerCount,
          timerDuration: timerDuration,
        ),
      );
    } catch (e) {
      setState(() {
        error = 'Error creating session: $e';
      });
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  void navigateToPage(Widget page) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => page),
    );
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    _videoPlayerController?.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _startAutoRotation() {
    Future.delayed(const Duration(seconds: 3), () {
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

  double _getImageHeight(String asset, double baseHeight) {
    switch (asset) {
      case 'assets/trophy_final_winner.png':
        return baseHeight * 1.8;
      case 'assets/logo2.png':
        return baseHeight * 0.9;
      case 'assets/image2_3.png':
        return baseHeight * 1.8;
      case 'assets/baba100new.jpg':
        return baseHeight * 3.5;
      case 'assets/66yrs.png':
        return baseHeight * 2.8;
      default:
        return baseHeight * 0.8;
    }
  }

  @override
  Widget build(BuildContext context) {
    double screenHeight = MediaQuery.of(context).size.height;
    double screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: const Color(0xFFEAC7EF),
      appBar: AppBar(
        backgroundColor: const Color.fromARGB(255, 96, 5, 105),
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            Image.asset(
              'assets/baba100new.jpg',
              width: screenWidth * 0.12,
              height: screenHeight * 0.05,
            ),
            SizedBox(width: screenWidth * 0.02),
            Expanded(
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
            icon: const Icon(Icons.info_outline),
            color: Colors.yellow,
            onPressed: () {
              navigateToPage(const InstructionsPage());
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.yellow),
            onSelected: (value) {
              if (value == 'MCQ') {
                navigateToPage(const AddMcqPage());
              } else if (value == 'Picture') {
                navigateToPage(const AddPictureQuestionPage());
              } else if (value == 'Structured') {
                navigateToPage(const AddStructuredQuestionPage());
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem<String>(
                value: 'Header',
                enabled: false,
                child: Text(
                  'Add Questions',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16.0),
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem<String>(
                value: 'MCQ',
                child: Text('+ MCQ'),
              ),
              const PopupMenuItem<String>(
                value: 'Picture',
                child: Text('+ Picture Based'),
              ),
              const PopupMenuItem<String>(
                value: 'Structured',
                child: Text('+ Structured'),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.yellow),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: isCheckingAdmin || isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: buildMainContent(screenHeight, screenWidth),
                ),
                buildFooterImage(screenHeight, screenWidth),
                buildFooter(screenHeight),
              ],
            ),
    );
  }

  Widget buildMainContent(double screenHeight, double screenWidth) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 650),
        child: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.symmetric(
                vertical: screenHeight * 0.02, horizontal: 20),
            child: Column(
              children: [
                buildLogoImage(screenHeight, screenWidth),
                SizedBox(height: screenHeight * 0.015),
                buildPlayerCountSlider(screenHeight),
                SizedBox(height: screenHeight * 0.015),
                buildTimerDurationSlider(screenHeight),
                SizedBox(height: screenHeight * 0.015),
                buildCreateSessionButton(screenHeight),
                if (error.isNotEmpty)
                  Padding(
                    padding:
                        EdgeInsets.symmetric(vertical: screenHeight * 0.01),
                    child: Text(
                      error,
                      style: TextStyle(
                        color: Colors.red,
                        fontSize: screenHeight * 0.02,
                      ),
                    ),
                  ),
                if (isAdmin)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: ElevatedButton.icon(
                      onPressed: () => navigateToPage(const AdminPanelPage()),
                      icon: const Icon(Icons.admin_panel_settings, size: 16),
                      label: const Text('Go to Admin Panel',
                          style: TextStyle(fontSize: 12)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget buildFooter(double screenHeight) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 20),
      decoration: BoxDecoration(
        color: const Color(0xFF450E4E),
        borderRadius: BorderRadius.zero,
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

  Widget buildLogoImage(double screenHeight, double screenWidth) {
    return Center(
      child: GestureDetector(
        onTap: () {
          _playVideo();
        },
        child: Image.asset(
          'assets/baba100new.jpg',
          width: screenWidth * 0.35,
          height: screenHeight * 0.18,
          fit: BoxFit.contain,
        ),
      ),
    );
  }

  void _playVideo() {
    _videoPlayerController = VideoPlayerController.asset('assets/babavideo.mp4')
      ..initialize().then((_) {
        setState(() {});
        _videoPlayerController!.play();
        showDialog(
          context: context,
          builder: (context) {
            final screenWidth = MediaQuery.of(context).size.width;
            final screenHeight = MediaQuery.of(context).size.height;

            final double videoWidth = screenWidth * 0.8;
            final double videoHeight = screenHeight * 0.4;
            final double imageSize = screenWidth * 0.15;
            final double textFontSize = screenHeight * 0.016;

            return AlertDialog(
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20.0),
                    child: AspectRatio(
                      aspectRatio: _videoPlayerController!.value.aspectRatio,
                      child: SizedBox(
                        width: videoWidth,
                        height: videoHeight,
                        child: VideoPlayer(_videoPlayerController!),
                      ),
                    ),
                  ),
                  SizedBox(height: screenHeight * 0.005),
                  Image.asset(
                    'assets/baba100new.jpg',
                    height: imageSize * 1.5,
                    fit: BoxFit.contain,
                  ),
                ],
              ),
              actionsPadding:
                  EdgeInsets.symmetric(vertical: screenHeight * 0.005),
              actions: [
                TextButton(
                  onPressed: () {
                    _videoPlayerController!.pause();
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

  Widget buildPlayerCountSlider(double screenHeight) {
    return Column(
      children: [
        Text(
          'Number of Players (Max 12):',
          style: TextStyle(fontSize: screenHeight * 0.017),
        ),
        Slider(
          value: playerCount.toDouble(),
          min: 1,
          max: 12,
          divisions: 11,
          label: playerCount.toString(),
          onChanged: (value) {
            setState(() {
              playerCount = value.toInt();
            });
          },
        ),
      ],
    );
  }

  Widget buildTimerDurationSlider(double screenHeight) {
    return Column(
      children: [
        Text(
          'Timer (Optional| Max 5mins/300secs):',
          style: TextStyle(fontSize: screenHeight * 0.017),
        ),
        Slider(
          value: timerDuration.toDouble(),
          min: 30,
          max: 300,
          divisions: 30,
          label: timerDuration.toString(),
          onChanged: (value) {
            setState(() {
              timerDuration = value.toInt();
            });
          },
        ),
      ],
    );
  }

  Widget buildCreateSessionButton(double screenHeight) {
    return Padding(
      padding: EdgeInsets.only(bottom: screenHeight * 0.01),
      child: ElevatedButton(
        onPressed: createSession,
        style: ElevatedButton.styleFrom(
          foregroundColor: Colors.white,
          backgroundColor: const Color.fromARGB(255, 96, 5, 105),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15.0),
          ),
          padding: EdgeInsets.symmetric(
            vertical: screenHeight * 0.015,
            horizontal: screenHeight * 0.05,
          ),
        ),
        child: Text(
          'Create Session',
          style: TextStyle(fontSize: screenHeight * 0.018),
        ),
      ),
    );
  }

  Widget buildFooterImage(double screenHeight, double screenWidth) {
    final double carouselHeight = screenHeight * 0.15;
    return Column(
      children: [
        SizedBox(
          height: carouselHeight,
          child: PageView.builder(
            controller: _pageController,
            itemCount: _imageAssets.length,
            onPageChanged: (index) {
              setState(() {
                _currentImageIndex = index;
              });
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

                  final double rotationX = value * math.pi / 2.8;
                  final double scale = 1 - (value.abs() * 0.15);

                  return Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.0015)
                      ..rotateX(rotationX)
                      ..scale(scale),
                    child: Opacity(
                      opacity: (1 - value.abs() * 0.45).clamp(0.4, 1.0),
                      child: Center(
                        child: Image.asset(
                          _imageAssets[index],
                          height: _getImageHeight(
                              _imageAssets[index], carouselHeight),
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) =>
                              const Icon(Icons.history_edu,
                                  size: 60, color: Colors.purple),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(_imageAssets.length, (index) {
            return AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              width: _currentImageIndex == index ? 12 : 6,
              height: 6,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                color: _currentImageIndex == index
                    ? const Color(0xFF450E4E)
                    : Colors.grey.withOpacity(0.5),
              ),
            );
          }),
        ),
      ],
    );
  }
}
