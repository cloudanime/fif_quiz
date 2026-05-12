import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'services/user_service.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _isSignUp = false;
  bool _obscurePassword = true;
  String? _error;
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
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _pageController.dispose();
    _videoPlayerController?.dispose();
    super.dispose();
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

  void _startAutoRotation() {
    Future.delayed(const Duration(seconds: 3), () {
      if (!mounted) return;

      setState(() {
        _currentImageIndex = (_currentImageIndex + 1) % _imageAssets.length;
      });

      if (_pageController.hasClients) {
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
        return baseHeight * 0.8;
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

  Future<void> _loginWithProvider(OAuthProvider provider) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.auth.signInWithOAuth(provider);
    } catch (e) {
      String errorMessage = 'An unexpected error occurred.';
      if (e is AuthException) {
        if (e.message.contains('provider is not enabled')) {
          errorMessage =
              'This login method is not yet configured. Please contact the administrator.';
        } else {
          errorMessage = e.message;
        }
      }
      setState(() {
        _error = errorMessage;
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _handleAuth() async {
    if (_isSignUp) {
      await _signUp();
    } else {
      await _login();
    }
  }

  Future<void> _signUp() async {
    final username = _usernameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (username.isEmpty) {
      setState(() => _error = 'Username is required.');
      return;
    }
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'A valid email is required.');
      return;
    }
    if (password.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters.');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final existingEmailByUsername =
          await UserService.getEmailByUsername(username);
      if (existingEmailByUsername != null) {
        setState(() {
          _error =
              'Username "$username" is already taken. Please choose another one.';
          _isLoading = false;
        });
        return;
      }

      final emailExists = await UserService.checkEmailExists(email);
      if (emailExists) {
        setState(() {
          _error = 'This email is already registered. Please Login instead.';
          _isLoading = false;
        });
        return;
      }

      final response = await Supabase.instance.client.auth.signUp(
        email: email,
        password: password,
        data: {'username': username},
      );

      if (response.user == null) {
        setState(() {
          _error = 'Sign up failed.';
        });
      } else {
        try {
          await Supabase.instance.client.from('users').upsert({
            'id': response.user!.id,
            'username': username,
          });
          await Supabase.instance.client.from('profiles').upsert({
            'id': response.user!.id,
            'email': email,
          });
        } catch (dbError) {
          print("Database insertion error: $dbError");
        }

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Sign up successful! Please check your email (and spam folder) to verify your account, then log in.')),
        );
        setState(() {
          _isSignUp = false;
        });
      }
    } catch (e) {
      String errorMessage = 'An error occurred during sign up.';
      if (e is AuthException) {
        errorMessage = e.message;
        if (errorMessage.contains('Database error saving new user')) {
          errorMessage =
              'The username or email might already be in use. Please try a different username or Login.';
        } else if (errorMessage.contains('already registered')) {
          errorMessage = 'This email is already registered. Please Login.';
        }
      }
      setState(() {
        _error = errorMessage;
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _login() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      String identifier = _emailController.text.trim();
      String email = identifier;

      if (!identifier.contains('@')) {
        final resolvedEmail = await UserService.getEmailByUsername(identifier);
        if (resolvedEmail == null) {
          setState(() {
            _error =
                'Username not found. Please check your username or use your email.';
            _isLoading = false;
          });
          return;
        }
        email = resolvedEmail;
      }

      final response = await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: _passwordController.text.trim(),
      );
      if (response.user == null) {
        setState(() {
          _error = 'Login failed. Please check your credentials.';
        });
      } else {
        try {
          final userDoc = await Supabase.instance.client
              .from('users')
              .select('username')
              .eq('id', response.user!.id)
              .maybeSingle();

          if (userDoc == null || userDoc['username'] == null) {
            if (mounted) {
              await _showSetUsernameDialog(response.user!.id, email);
            }
          }
        } catch (e) {
          print("Error checking for username: $e");
        }

        if (mounted) {
          // Generate and register a unique session ID
          final sessionId = const Uuid().v4();
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('local_session_id', sessionId);
          await UserService.registerSession(sessionId);

          Navigator.of(context).pushReplacementNamed('/');
        }
      }
    } catch (e) {
      String errorMessage = 'An error occurred during login.';
      if (e is AuthException) {
        errorMessage = e.message;
      }
      setState(() {
        _error = errorMessage;
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _showSetUsernameDialog(String userId, String email) async {
    final TextEditingController usernameController = TextEditingController();
    String? dialogError;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text("Set Your Login Username"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                  "You don't have a login username yet. Set one now to use it for future logins."),
              const SizedBox(height: 10),
              TextField(
                controller: usernameController,
                decoration: InputDecoration(
                  labelText: "Username",
                  errorText: dialogError,
                ),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () async {
                final username = usernameController.text.trim();
                if (username.isEmpty) {
                  setDialogState(
                      () => dialogError = "Username cannot be empty");
                  return;
                }
                try {
                  await Supabase.instance.client.from('users').upsert({
                    'id': userId,
                    'username': username,
                  });
                  await Supabase.instance.client.from('profiles').upsert({
                    'id': userId,
                    'email': email,
                  });
                  Navigator.pop(context);
                } catch (e) {
                  setDialogState(() =>
                      dialogError = "Username already taken or error occurred");
                }
              },
              child: const Text("Save Username"),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showForgotPasswordDialog() async {
    final TextEditingController resetEmailController =
        TextEditingController(text: _emailController.text);
    bool isResetting = false;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Reset Password'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                    'Enter your email to receive a password reset link.'),
                const SizedBox(height: 5),
                const Text(
                  '(Don\'t forget to check your spam folder!)',
                  style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                      fontStyle: FontStyle.italic),
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: resetEmailController,
                  decoration: const InputDecoration(labelText: 'Email Address'),
                  keyboardType: TextInputType.emailAddress,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: isResetting ? null : () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: isResetting
                    ? null
                    : () async {
                        final email = resetEmailController.text.trim();
                        if (email.isEmpty || !email.contains('@')) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Please enter a valid email.')),
                          );
                          return;
                        }

                        setDialogState(() => isResetting = true);

                        try {
                          await Supabase.instance.client.auth
                              .resetPasswordForEmail(email);
                          if (context.mounted) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text(
                                      'Password reset email sent! Check your inbox and spam folder.'),
                                  backgroundColor: Colors.green),
                            );
                          }
                        } catch (e) {
                          setDialogState(() => isResetting = false);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text('Error: $e'),
                                  backgroundColor: Colors.red),
                            );
                          }
                        }
                      },
                child: isResetting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Send Reset Link'),
              ),
            ],
          );
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final double screenHeight = MediaQuery.of(context).size.height;
    final double screenWidth = MediaQuery.of(context).size.width;
    final double carouselHeight = screenHeight * 0.15;

    return Scaffold(
      backgroundColor: const Color(0xFFEAC7EF),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF450E4E)),
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 550),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Center(
                        child: GestureDetector(
                          onTap: _playVideo,
                          child: Image.asset(
                            'assets/baba100new.jpg',
                            width: (screenWidth * 0.35)
                                .clamp(100.0, 240.0), // Clamped width
                            height: screenHeight * 0.18,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Please login to join or host an Online Multiplayer Challenge.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Colors.red,
                            fontSize: 14,
                            fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'You do not need to log in to access Solo Player or the Hosted Multiplayer Modes.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 30),
                      if (_isSignUp) ...[
                        TextField(
                          controller: _usernameController,
                          decoration:
                              const InputDecoration(labelText: 'Username'),
                          keyboardType: TextInputType.text,
                        ),
                        const SizedBox(height: 10),
                      ],
                      TextField(
                        controller: _emailController,
                        decoration: InputDecoration(
                            labelText:
                                _isSignUp ? 'Email' : 'Username or Email'),
                        keyboardType: _isSignUp
                            ? TextInputType.emailAddress
                            : TextInputType.text,
                      ),
                      const SizedBox(height: 15),
                      TextField(
                        controller: _passwordController,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          suffixIcon: IconButton(
                            icon: Icon(_obscurePassword
                                ? Icons.visibility
                                : Icons.visibility_off),
                            onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword),
                          ),
                        ),
                        obscureText: _obscurePassword,
                      ),
                      const SizedBox(height: 25),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Text(_error!,
                              style: const TextStyle(color: Colors.red),
                              textAlign: TextAlign.center),
                        ),
                      SizedBox(
                        width: 120,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _handleAuth,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF450E4E),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20)),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2))
                              : Text(_isSignUp ? 'Sign Up' : 'Login'),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _isSignUp = !_isSignUp;
                            _error = null;
                          });
                        },
                        child: Text(
                          _isSignUp
                              ? 'Already have an account? Login'
                              : 'Don\'t have an account? Sign Up',
                          style: const TextStyle(color: Color(0xFF450E4E)),
                        ),
                      ),
                      if (!_isSignUp)
                        TextButton(
                          onPressed: _showForgotPasswordDialog,
                          child: const Text('Forgot Password?',
                              style: TextStyle(color: Colors.grey)),
                        ),
                      const SizedBox(height: 20),
                      const Divider(),
                      const SizedBox(height: 10),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Carousel Section before Footer
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
      ),
      bottomNavigationBar: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
        decoration: const BoxDecoration(
          color: Color(0xFF450E4E),
          borderRadius: BorderRadius.zero,
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
      ),
    );
  }
}
