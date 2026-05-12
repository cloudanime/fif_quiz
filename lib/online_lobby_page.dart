import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'services/quiz_supabase_service.dart';
import 'online_quiz_page.dart' hide Text;
import 'models/supabase_models.dart';
import 'mode_selection_page.dart';

enum LobbyState {
  initial,
  hosting,
  joining,
  teamSelection,
  waiting,
  preparatory
}

class OnlineLobbyPage extends StatefulWidget {
  final bool isCreating;
  final bool isTeamMode;
  final int? quickMatchCount;
  const OnlineLobbyPage({
    super.key,
    this.isCreating = false,
    this.isTeamMode = false,
    this.quickMatchCount,
  });

  @override
  State<OnlineLobbyPage> createState() => _OnlineLobbyPageState();
}

class _OnlineLobbyPageState extends State<OnlineLobbyPage>
    with WidgetsBindingObserver {
  final SupabaseQuizService _quizService = SupabaseQuizService();
  final supabase = Supabase.instance.client;

  static const Color primaryPurple = Color(0xFF450E4E);
  static const Color deepPurple = Color.fromARGB(255, 96, 5, 105);

  LobbyState _state = LobbyState.initial;
  String? _gameId;
  String? _adminId;
  String? _joinCode;
  bool _isAutoStart = false;
  int _selectedQuestionCount = 10;

  int _selectedTimerDuration = 60; // Default 60s
  int? _maxPlayers;
  List<GamePlayerModel> _participants = [];
  final Map<String, String> _usernames = {};
  bool _isLoading = false;
  String? _error;
  String? _playerName;
  bool _nameConfirmed = false;
  RealtimeChannel? _gameChannel;
  late TextEditingController _questionCountController;
  Timer? _heartbeatTimer;
  Timer? _inactivityTimer;
  DateTime _lastRoomActivity = DateTime.now();
  late bool _isTeamMode;
  bool _isExiting = false;

  @override
  void initState() {
    super.initState();
    _isTeamMode = widget.isTeamMode;
    WidgetsBinding.instance.addObserver(this);
    _questionCountController =
        TextEditingController(text: _selectedQuestionCount.toString());

    if (widget.isCreating) {
      _state = LobbyState.hosting;
    } else {
      _state = LobbyState.joining;
    }

    _loadDefaultName().then((_) {
      if (_playerName != null && _playerName!.isNotEmpty) {
        // If we came from a quick match button, trigger it immediately
        if (widget.quickMatchCount != null) {
          _joinQuickMatch(widget.quickMatchCount!);
        }
      }
    });

    _startHeartbeat();
    _startInactivityTimer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // App is minimized - disconnect to save Supabase charges
      _gameChannel?.unsubscribe();
    } else if (state == AppLifecycleState.resumed) {
      // App is back - reconnect if we are in a game/lobby
      if (_gameId != null) {
        _listenToGame();
      }
    }
  }

  void _startInactivityTimer() {
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(const Duration(minutes: 5), () {
      if (mounted) {
        _exitLobby();
      }
    });
  }

  void _resetInactivityTimer() {
    _lastRoomActivity = DateTime
        .now(); // Interaction counts as room activity for the local user
    if (_inactivityTimer != null) {
      _startInactivityTimer();
    }
  }

  Future<void> _exitLobby() async {
    if (_isExiting) return;
    _isExiting = true;
    _heartbeatTimer?.cancel();
    _inactivityTimer?.cancel();

    try {
      if (_gameId != null) {
        final isHost = (supabase.auth.currentUser?.id == _adminId) ||
            (_adminId == null &&
                _participants.isNotEmpty &&
                _participants[0].userId == supabase.auth.currentUser?.id);

        if (isHost) {
          // Update game status to aborted to notify others
          await _quizService.updateGameStatus(_gameId!, 'aborted').timeout(
                const Duration(seconds: 2),
                onTimeout: () => debugPrint("Exit: Status update timed out"),
              );
        }

        // Remove player record
        await supabase
            .from('game_players')
            .delete()
            .eq('game_id', _gameId!)
            .eq('user_id', supabase.auth.currentUser!.id)
            .timeout(
              const Duration(seconds: 2),
              onTimeout: () => debugPrint("Exit: Player delete timed out"),
            );
      }
    } catch (e) {
      debugPrint("Error during lobby exit: $e");
    } finally {
      if (mounted) {
        ScaffoldMessenger.of(context).removeCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("You were removed from the lobby due to inactivity."),
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

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (mounted &&
          (_state == LobbyState.waiting || _state == LobbyState.preparatory)) {
        // Check for room-wide inactivity (no updates/interaction for 5 minutes)
        if (DateTime.now().difference(_lastRoomActivity).inMinutes >= 5) {
          debugPrint("Lobby: Room inactivity detected. Exiting.");
          _exitLobby();
          return;
        }
        _fetchParticipants();
      }
    });
  }

  Future<void> _loadDefaultName() async {
    try {
      final user = supabase.auth.currentUser;
      if (user != null) {
        final userData = await supabase
            .from('users')
            .select('username')
            .eq('id', user.id)
            .maybeSingle();

        if (userData != null && userData['username'] != null) {
          setState(() {
            _playerName = userData['username'];
          });
        }
      }
    } catch (e) {
      debugPrint("Error loading default name: $e");
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _questionCountController.dispose();
    _gameChannel?.unsubscribe();
    _heartbeatTimer?.cancel();
    _inactivityTimer?.cancel();
    super.dispose();
  }

  // --- LOGIC ---

  String _generateJoinCode() {
    return (Random().nextInt(900000) + 100000).toString();
  }

  Future<bool> _ensureNameSet() async {
    if (_nameConfirmed && _playerName != null && _playerName!.isNotEmpty)
      return true;

    final controller = TextEditingController(text: _playerName ?? "");
    final name = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text(
            "Confirm or Change Name",
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0B3384)), // Reduced font size
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                  "This name will be visible to other players in this session."),
              const SizedBox(height: 15),
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: "Game Name",
                  hintText: "e.g. Ezekiel",
                  border: OutlineInputBorder(),
                ),
                autofocus: true,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text("Confirm & Join"),
            ),
          ],
        );
      },
    );
    if (name != null && name.isNotEmpty) {
      setState(() {
        _playerName = name;
        _nameConfirmed = true;
      });
      return true;
    }
    return false;
  }

  Future<void> _hostPrivateGame() async {
    if (!await _ensureNameSet()) return;
    setState(() {
      _isLoading = true;
      _maxPlayers = null; // Clear any previous quick match limits
    });
    try {
      _error = null;
      final user = supabase.auth.currentUser;
      final code = _generateJoinCode();
      final gameId = await _quizService.createGame(
        mode: 'private',
        adminId: user?.id,
        status: 'waiting',
        joinCode: code,
        questionCount: _selectedQuestionCount,
        timerDuration: _selectedTimerDuration,
        isAutoStart: false,
        isTeamMode: widget.isTeamMode,
      );

      if (gameId == null)
        throw Exception(
            "Failed to create game session. Please check your connection.");

      _gameId = gameId;
      _joinCode = code;
      // Include display_name when joining
      await supabase.from('game_players').insert({
        'game_id': gameId,
        'user_id': user!.id,
        'display_name': _playerName
      });
      _listenToGame();
      _fetchParticipants();
      if (widget.isTeamMode) {
        setState(() => _state = LobbyState.teamSelection);
      } else {
        _enterWaitingRoom();
      }
    } catch (e) {
      debugPrint("Host Private Game Error: $e");
      setState(() => _error = "Host Error: ${e.toString()}");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _joinWithCode(String code) async {
    if (!await _ensureNameSet()) return;
    setState(() => _isLoading = true);
    try {
      final user = supabase.auth.currentUser;
      final gameId =
          await _quizService.joinGameByCode(joinCode: code, userId: user!.id);
      if (gameId != null) {
        _gameId = gameId;
        _joinCode = code;

        // Update display_name since joinGameByCode already does an insert
        await supabase
            .from('game_players')
            .update({'display_name': _playerName})
            .eq('game_id', gameId)
            .eq('user_id', user.id);

        // Fetch game settings (question count and team mode) for the room
        final gameData = await supabase
            .from('games')
            .select('question_count, is_team_mode')
            .eq('id', gameId)
            .single();
        _selectedQuestionCount = gameData['question_count'] as int;
        _isTeamMode = gameData['is_team_mode'] == true;

        _listenToGame();
        _fetchParticipants();

        if (_isTeamMode) {
          setState(() => _state = LobbyState.teamSelection);
        } else {
          _enterWaitingRoom();
        }
      }
    } catch (e) {
      setState(() => _error = "Invalid code or room is full");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _joinQuickMatch(int count) async {
    if (!await _ensureNameSet()) return;
    setState(() => _isLoading = true);
    try {
      _error = null;
      final user = supabase.auth.currentUser;
      String? gameId;
      // Matchmaking with retry to prevent race conditions
      int retries = 2;
      while (retries > 0) {
        final response = await supabase
            .from('games')
            .select()
            .eq('mode', 'public')
            .eq('status', 'waiting')
            .eq('max_players', count)
            .order('created_at', ascending: true);

        final List<dynamic> candidates = response as List<dynamic>;

        if (candidates.isNotEmpty) {
          final oldestRoom = candidates.first;
          final roomId = oldestRoom['id'];

          // A. Check if I am already in this room
          final existing = await supabase
              .from('game_players')
              .select()
              .eq('game_id', roomId)
              .eq('user_id', user!.id)
              .maybeSingle();

          if (existing != null) {
            gameId = roomId;
            _selectedQuestionCount = oldestRoom['question_count'] as int? ?? 12;
            _selectedTimerDuration =
                (oldestRoom as Map).containsKey('timer_duration')
                    ? oldestRoom['timer_duration'] as int? ?? 90
                    : 90;
            break;
          }

          // B. Check if room is full
          final countRes = await supabase
              .from('game_players')
              .select('id')
              .eq('game_id', roomId);

          final currentCount = (countRes as List).length;

          if (currentCount < count) {
            gameId = roomId;
            _selectedQuestionCount = oldestRoom['question_count'] as int? ?? 12;
            _selectedTimerDuration =
                (oldestRoom as Map).containsKey('timer_duration')
                    ? oldestRoom['timer_duration'] as int? ?? 90
                    : 90;

            try {
              await supabase.from('game_players').insert({
                'game_id': gameId,
                'user_id': user.id,
                'display_name': _playerName
              });
              break;
            } catch (e) {
              debugPrint("Join room error: $e");
              gameId = null; // Join failed, retry
            }
          }
        }

        if (gameId == null) {
          retries--;
          if (retries > 0) {
            await Future.delayed(
                Duration(milliseconds: 500 + Random().nextInt(500)));
          }
        } else {
          break;
        }
      }

      if (gameId == null) {
        // Create new public room
        _selectedQuestionCount = 12;
        _selectedTimerDuration = 90;
        gameId = await _quizService.createGame(
          mode: 'public',
          adminId: user!.id,
          status: 'waiting',
          maxPlayers: count,
          questionCount: _selectedQuestionCount,
          timerDuration: _selectedTimerDuration,
          isAutoStart: false,
        );
        if (gameId != null) {
          await supabase.from('game_players').insert({
            'game_id': gameId,
            'user_id': user.id,
            'display_name': _playerName
          });
        }
      }

      if (gameId != null) {
        _gameId = gameId;
        _maxPlayers = count;
        _listenToGame();
        _fetchParticipants();
        _enterWaitingRoom();
      } else {
        throw "Could not join or create an auto room. Please try again.";
      }
    } catch (e) {
      debugPrint("Quick Match Error: $e");
      setState(() => _error = "Matchmaking Failed: ${e.toString()}");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _enterWaitingRoom() {
    setState(() {
      _state = LobbyState.waiting;
      _error = null;
    });
  }

  void _listenToGame() {
    if (_gameId == null) return;

    _gameChannel = supabase.channel('game_room:$_gameId')
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'game_players',
        filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'game_id',
            value: _gameId),
        callback: (payload) {
          _lastRoomActivity = DateTime.now();
          _fetchParticipants();
        },
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'games',
        filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq, column: 'id', value: _gameId),
        callback: (payload) {
          _lastRoomActivity = DateTime.now();
          final status = (payload.newRecord['status'] ?? "").toString();
          if (status == 'preparatory') {
            setState(() => _state = LobbyState.preparatory);
          } else if (status == 'aborted') {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text("Host has left. Game aborted.")));
              Navigator.of(context).pop();
            }
          } else if (status.startsWith('started')) {
            if (status.contains(':')) {
              try {
                _selectedTimerDuration = int.parse(status.split(':')[1]);
              } catch (_) {}
            }
            _navigateToQuiz();
          }
        },
      )
      ..subscribe();
  }

  Future<void> _fetchParticipants() async {
    if (_gameId == null) return;

    // 1. Fetch game details to get official admin_id and current status
    final gameResponse = await supabase
        .from('games')
        .select('admin_id, status, is_auto_start, is_team_mode')
        .eq('id', _gameId!)
        .single();

    _isTeamMode = gameResponse['is_team_mode'] == true;

    final status = gameResponse['status']?.toString() ?? "";
    _isAutoStart = gameResponse['is_auto_start'] as bool? ?? false;
    if (status == 'preparatory' && _state != LobbyState.preparatory) {
      setState(() => _state = LobbyState.preparatory);
    } else if (status.startsWith('started') && mounted) {
      // If we missed the transition, catch it here
      _navigateToQuiz();
      return; // Stop further processing as we are leaving
    }

    // 2. Fetch players
    final response = await supabase
        .from('game_players')
        .select('*, users(username)')
        .eq('game_id', _gameId!)
        .order('joined_at');

    final List<dynamic> data = response as List<dynamic>;
    setState(() {
      _adminId = gameResponse['admin_id'];
      _participants =
          data.map((json) => GamePlayerModel.fromJson(json)).toList();

      for (var item in data) {
        final userId = item['user_id'];
        // Show the Game Name (display_name) if set, otherwise fallback to Login Username
        final displayName =
            item['display_name'] ?? item['users']?['username'] ?? 'Anonymous';
        _usernames[userId] = displayName;
      }
    });

    // Auto-start disabled as requested

    // Failsafe: If stuck in preparatory phase, acting admin should push to start
    if (status == 'preparatory') {
      final isActingAdmin = (supabase.auth.currentUser?.id == _adminId) ||
          (_adminId == null &&
              _participants.isNotEmpty &&
              _participants[0].userId == supabase.auth.currentUser?.id);
      if (isActingAdmin && !_isLoading) {
        // If we've been here a while (handled by heartbeat logic), try starting
        _startGame();
      }
    }
  }

  Future<void> _startPreparatoryPhase() async {
    try {
      await _quizService.updateGameStatus(_gameId!, 'preparatory');
      // Set local state immediately for host so timer check passes
      if (mounted) {
        setState(() => _state = LobbyState.preparatory);
      }

      // After 5 seconds of "Welcome", start the game
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted && _state == LobbyState.preparatory) {
          _startGame();
        }
      });
    } catch (e) {
      debugPrint("Error starting preparatory phase: $e");
    }
  }

  Future<void> _startGame() async {
    if (_isLoading) return; // Prevent double trigger

    setState(() => _isLoading = true);
    debugPrint("LOBBY: Starting game for ID: $_gameId");
    try {
      // 1. Lock in 100 questions for the grid pool
      // Add a timeout to prevent indefinite hang
      await _quizService.initializeGameQuestions(_gameId!, 100).timeout(
            const Duration(seconds: 15),
            onTimeout: () =>
                throw TimeoutException("Fetching questions took too long"),
          );

      // 2. Start the game with encoded timer duration
      await _quizService.updateGameStatus(
          _gameId!, 'started:$_selectedTimerDuration');
      debugPrint("LOBBY: Game status updated to started");
    } catch (e) {
      debugPrint("LOBBY ERROR in _startGame: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error starting game: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _navigateToQuiz() {
    if (!mounted) return;
    final isHost = (supabase.auth.currentUser?.id == _adminId) ||
        (_adminId == null &&
            _participants.isNotEmpty &&
            _participants[0].userId == supabase.auth.currentUser?.id);

    // Use PostFrameCallback to avoid "Navigator.push() during build" errors
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      // Check if we are already on the Quiz page to avoid multiple pushes
      final route = ModalRoute.of(context);
      if (route != null && route.settings.name == '/quiz') return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          settings: const RouteSettings(name: '/quiz'),
          builder: (context) => OnlineQuizPage(
            gameId: _gameId!,
            questionCount: _selectedQuestionCount,
            timerDuration: _selectedTimerDuration,
            isHost: isHost,
            isTeamMode: _isTeamMode,
          ),
        ),
      );
    });
  }

  // --- UI ---

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _resetInactivityTimer(),
      onPointerMove: (_) => _resetInactivityTimer(),
      child: Scaffold(
        backgroundColor: (_state == LobbyState.initial ||
                _state == LobbyState.hosting ||
                _state == LobbyState.joining ||
                _state == LobbyState.teamSelection)
            ? const Color(0xFFEAC7EF)
            : Colors.white,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Row(
            children: [
              Image.asset(
                'assets/logo.png',
                width: MediaQuery.of(context).size.width * 0.12,
                height: MediaQuery.of(context).size.height * 0.05,
              ),
              const SizedBox(width: 8),
              Expanded(
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
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () async {
                if (_state == LobbyState.initial) {
                  Navigator.pop(context);
                } else {
                  final isHost = supabase.auth.currentUser?.id == _adminId;
                  if (isHost && _gameId != null) {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text("Abort Game?"),
                        content: const Text(
                            "As host, exiting will abort the game for everyone. Continue?"),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text("Cancel")),
                          TextButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text("Abort")),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      await _quizService.updateGameStatus(_gameId!, 'aborted');
                      if (mounted) Navigator.pop(context);
                    }
                  } else {
                    Navigator.pop(context);
                  }
                }
              },
            ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24.0),
                    child: _buildBody(),
                  ),
                ),
              ),
        bottomNavigationBar: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          decoration: BoxDecoration(
            color: const Color(0xFF450E4E),
            borderRadius: BorderRadius.circular(0),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 8,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: const SafeArea(
            top: false,
            child: Text(
              'Developed by FIFMI Middle East (EGEA and Media)',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.normal,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 20),
            ElevatedButton(
                onPressed: () => setState(() => _error = null),
                child: const Text('Back')),
          ],
        ),
      );
    }

    switch (_state) {
      case LobbyState.initial:
        return _buildInitialView();
      case LobbyState.hosting:
        return _buildHostingView();
      case LobbyState.joining:
        return _buildJoiningView();
      case LobbyState.teamSelection:
        return _buildTeamSelectionView();
      case LobbyState.waiting:
        return _buildWaitingView();
      case LobbyState.preparatory:
        return _buildPreparatoryView();
    }
  }

  Widget _buildInitialView() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Image.asset('assets/baba100new.jpg', height: 80, fit: BoxFit.contain),
        const SizedBox(height: 15),
        // Display current session name with a change option
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.5),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: primaryPurple.withOpacity(0.2)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.person_outline, size: 16, color: primaryPurple),
              const SizedBox(width: 8),
              Text(
                'Playing as: ',
                style: TextStyle(
                    fontSize: 13, color: primaryPurple.withOpacity(0.7)),
              ),
              Text(
                _playerName ?? '...',
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: primaryPurple),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: () {
                  setState(() => _nameConfirmed = false);
                  _ensureNameSet();
                },
                child: const Text(
                  'Change',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.blue,
                    fontWeight: FontWeight.bold,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _menuButton('Host Private Challenge', Icons.add_box, () {
          setState(() => _state = LobbyState.hosting);
        }),
        const Text(
          'Start a custom room with your own Join Code and question count.',
          style: TextStyle(fontSize: 11, color: Colors.black54),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        _menuButton('Join Private Challenge', Icons.vpn_key, () {
          setState(() => _state = LobbyState.joining);
        }),
        const Text(
          'Enter a 6-digit code provided by a host to join their session.',
          style: TextStyle(fontSize: 11, color: Colors.black54),
          textAlign: TextAlign.center,
        ),
        if (!widget.isTeamMode) ...[
          const Divider(height: 50),
          const Text('Quick Match (Auto-Start)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 4.0),
            child: Text(
              'Jump into a challenge with online participants! Playing starts automatically when the game\'s lobby is full.',
              style: TextStyle(fontSize: 11, color: Colors.black54),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 15),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: [2, 3, 4, 5, 6, 8, 10]
                .map((count) => ActionChip(
                      label: Text('$count Players'),
                      onPressed: () => _joinQuickMatch(count),
                    ))
                .toList(),
          ),
        ],
      ],
    );
  }

  Widget _buildTeamSelectionView() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Image.asset('assets/baba100new.jpg', height: 80, fit: BoxFit.contain),
        const SizedBox(height: 30),
        const Text('Team Selection',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        const Text('Join or Create a team for this challenge (Max 5 members)',
            textAlign: TextAlign.center),
        const SizedBox(height: 30),
        _menuButton('Create New Team', Icons.group_add, _createTeam),
        const SizedBox(height: 15),
        _menuButton('Join Existing Team', Icons.group, _joinTeam),
      ],
    );
  }

  Future<void> _createTeam() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create Team'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
              labelText: 'Team Name', hintText: 'e.g. The Conquerors'),
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Create')),
        ],
      ),
    );

    if (name != null && name.isNotEmpty) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
      try {
        if (_gameId == null) throw "Game ID is missing. Please re-host.";

        final code =
            (Random().nextInt(90000) + 10000).toString(); // 5 digit code
        await supabase
            .from('game_players')
            .update({
              'team_name': name,
              'team_code': code,
            })
            .eq('game_id', _gameId!)
            .eq('user_id', supabase.auth.currentUser!.id);

        if (mounted) {
          await showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green),
                  SizedBox(width: 10),
                  Text('Team Created!'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Your team "$name" is ready.',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 15),
                  const Text(
                      'Share this TEAM CODE with your friends so they can join you:'),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.purple.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.purple.shade200),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(code,
                            style: const TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 4,
                                color: Color(0xFF450E4E))),
                        const SizedBox(width: 10),
                        IconButton(
                          icon:
                              const Icon(Icons.copy, color: Color(0xFF450E4E)),
                          onPressed: () {
                            final senderName =
                                (_usernames[supabase.auth.currentUser?.id] ??
                                        'Someone')
                                    .toUpperCase();
                            final inviteText =
                                '$senderName has invited you to participate in the FIFMI Legacy Quiz Challenge.\n\nSession Join Code: $_joinCode\nTeam Code: $code (Team "$name")';
                            Clipboard.setData(ClipboardData(text: inviteText));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('Invitation text copied!')),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Got it!'),
                ),
              ],
            ),
          );
        }

        _enterWaitingRoom();
      } catch (e) {
        debugPrint("Create Team Error: $e");
        setState(() => _error = "Team Creation Failed: ${e.toString()}");
      } finally {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _joinTeam() async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Join Team'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
              labelText: 'Team Code', hintText: 'Enter 5-digit code'),
          keyboardType: TextInputType.number,
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Join')),
        ],
      ),
    );

    if (code != null && code.isNotEmpty) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
      try {
        if (_gameId == null) throw "Session lost. Please re-join the lobby.";

        // 1. Fetch fresh list of players for this game to avoid stale state
        final res = await supabase
            .from('game_players')
            .select()
            .eq('game_id', _gameId!);

        final List<dynamic> playersJson = res as List<dynamic>;
        if (playersJson.isEmpty)
          throw "No players found in this session. Re-joining...";

        final allParticipants =
            playersJson.map((j) => GamePlayerModel.fromJson(j)).toList();

        // 2. Find if team exists in this game and count members
        // Comparison should be robust (trim and compare as strings)
        final searchCode = code.trim();
        final teamMembers = allParticipants
            .where((p) => p.teamCode?.toString().trim() == searchCode)
            .toList();

        if (teamMembers.isEmpty) {
          final existingCodes = allParticipants
              .map((p) => p.teamCode)
              .where((c) => c != null)
              .toSet()
              .join(', ');
          throw "Team code '$searchCode' not found in session '${_gameId?.substring(0, 8)}...'. Found ${allParticipants.length} players. Available teams: ${existingCodes.isEmpty ? 'None' : existingCodes}";
        }
        if (teamMembers.length >= 5) {
          throw "Team '$code' is full (Maximum 5 members allowed).";
        }

        final teamName = teamMembers.first.teamName;

        await supabase
            .from('game_players')
            .update({
              'team_name': teamName,
              'team_code': code,
            })
            .eq('game_id', _gameId!)
            .eq('user_id', supabase.auth.currentUser!.id);
        _enterWaitingRoom();
      } catch (e) {
        setState(() => _error = e.toString());
      } finally {
        setState(() => _isLoading = false);
      }
    }
  }

  Widget _buildHostingView() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Image.asset('assets/baba100new.jpg', height: 80, fit: BoxFit.contain),
        const SizedBox(height: 30),
        const Text('Host Setup',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 30),
        const Text('Number of Questions:'),
        Slider(
          value: _selectedQuestionCount.toDouble().clamp(5.0, 100.0),
          min: 5,
          max: 100,
          divisions: 95,
          label: _selectedQuestionCount.toString(),
          onChanged: (v) {
            setState(() {
              _selectedQuestionCount = v.toInt();
              _questionCountController.text = _selectedQuestionCount.toString();
            });
          },
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 80,
              child: TextField(
                controller: _questionCountController,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF450E4E)),
                decoration: InputDecoration(
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Colors.purple)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide:
                          const BorderSide(color: Color(0xFF450E4E), width: 2)),
                ),
                onChanged: (v) {
                  final val = int.tryParse(v);
                  if (val != null) {
                    setState(() {
                      _selectedQuestionCount = val;
                    });
                  }
                },
              ),
            ),
            const SizedBox(width: 10),
            const Text('questions',
                style: TextStyle(fontSize: 18, color: Colors.purple)),
          ],
        ),
        const SizedBox(height: 30),
        const Text('Timer per Question (seconds):'),
        Slider(
          value: _selectedTimerDuration.toDouble(),
          min: 10,
          max: 120,
          divisions: 11, // 10s steps: (120-10)/10 = 11
          label: "$_selectedTimerDuration sec",
          onChanged: (v) => setState(() => _selectedTimerDuration = v.toInt()),
        ),
        Text('$_selectedTimerDuration seconds',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 40),
        ElevatedButton(
          onPressed: _hostPrivateGame,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF450E4E),
            foregroundColor: Colors.yellow,
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          ),
          child: const Text('Create Private Challenge Room',
              style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Widget _buildJoiningView() {
    final controller = TextEditingController();
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Image.asset('assets/baba100new.jpg', height: 80, fit: BoxFit.contain),
        const SizedBox(height: 30),
        const Text('Enter Join Code',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 20),
        TextField(
          controller: controller,
          decoration: const InputDecoration(
              border: OutlineInputBorder(), hintText: '6-digit code'),
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 32, letterSpacing: 8),
          maxLength: 6,
        ),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: () => _joinWithCode(controller.text),
          child: const Text('Join Challenge'),
        ),
      ],
    );
  }

  Widget _buildWaitingView() {
    // ... (rest of the method kept the same for brevity in thought, but I'll provide full content)
    final currentUser = supabase.auth.currentUser;
    final isHost = _adminId != null && currentUser?.id == _adminId;

    return Column(
      children: [
        if (_joinCode != null) ...[
          const Text('JOIN CODE:', style: TextStyle(fontSize: 14)),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(width: 48), // Spacer to center the text better
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(_joinCode!,
                    style: const TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 4,
                        color: Color(0xFF450E4E))),
              ),
              IconButton(
                icon: const Icon(Icons.copy, color: Color(0xFF450E4E)),
                onPressed: () {
                  final senderName =
                      (_usernames[supabase.auth.currentUser?.id] ?? 'Someone')
                          .toUpperCase();
                  final inviteText =
                      '$senderName has invited you to participate in the FIFMI Legacy Quiz Challenge.\n\n'
                      'Session Join Code: $_joinCode';
                  Clipboard.setData(ClipboardData(text: inviteText));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Invitation copied to clipboard!'),
                        duration: Duration(seconds: 2)),
                  );
                },
                tooltip: 'Copy Code',
              ),
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Share this code with your intended participants to join the challenge.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.grey.shade600, fontSize: 13, height: 1.4),
            ),
          ),
          const SizedBox(height: 20),
        ],

        // --- ADDED: Prominent Team Code display for members ---
        if (widget.isTeamMode)
          (() {
            final myPlayer = _participants.cast<GamePlayerModel?>().firstWhere(
                (p) => p?.userId == supabase.auth.currentUser?.id,
                orElse: () => null);
            if (myPlayer != null && myPlayer.teamCode != null) {
              final myTeamMembers = _participants
                  .where((p) => p.teamCode == myPlayer.teamCode)
                  .toList();

              return Container(
                margin: const EdgeInsets.only(bottom: 20, left: 20, right: 20),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(
                      color: const Color(0xFF450E4E).withOpacity(0.3)),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 5,
                        offset: const Offset(0, 2)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Column(
                        children: [
                          const Text('YOUR TEAM:',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey)),
                          const SizedBox(height: 4),
                          Text(myPlayer.teamName?.toUpperCase() ?? 'MY TEAM',
                              style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF450E4E))),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text('TEAM CODE: ',
                                  style: TextStyle(fontSize: 12)),
                              Text(myPlayer.teamCode!,
                                  style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF450E4E))),
                              IconButton(
                                icon: const Icon(Icons.copy,
                                    size: 20, color: Color(0xFF450E4E)),
                                onPressed: () {
                                  final senderName = (_usernames[
                                              supabase.auth.currentUser?.id] ??
                                          'Someone')
                                      .toUpperCase();
                                  final teamName =
                                      (myPlayer.teamName ?? 'My Team')
                                          .toUpperCase();
                                  final inviteText =
                                      '$senderName has invited you to join team "$teamName" for the FIFMI Legacy Quiz.\n\nSession Code: $_joinCode\nTeam Code: ${myPlayer.teamCode}';
                                  Clipboard.setData(
                                      ClipboardData(text: inviteText));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content:
                                            Text('Full invitation copied!')),
                                  );
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const Divider(),
                    const Text('TEAM MEMBERS:',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: myTeamMembers
                          .map((m) => Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color:
                                      const Color(0xFF450E4E).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.person,
                                        size: 14, color: Color(0xFF450E4E)),
                                    const SizedBox(width: 4),
                                    Text(
                                      _usernames[m.userId] ?? 'Anonymous',
                                      style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF450E4E)),
                                    ),
                                  ],
                                ),
                              ))
                          .toList(),
                    ),
                  ],
                ),
              );
            }
            return const SizedBox.shrink();
          })(),
        // -----------------------------------------------------
        Text(
          _maxPlayers != null
              ? 'Waiting for players (${_participants.length}/$_maxPlayers)...'
              : 'Waiting for host to start...',
          style: const TextStyle(fontStyle: FontStyle.italic),
        ),
        const Divider(height: 40),
        const Text('Players in Lobby:',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        _isTeamMode
            ? _buildTeamGroupedList()
            : ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _participants.length,
                itemBuilder: (context, i) {
                  final p = _participants[i];
                  final isMe = p.userId == supabase.auth.currentUser?.id;
                  final joinTime = p.joinedAt.toLocal();
                  final waitDuration = DateTime.now().difference(p.joinedAt);
                  final needsRefresh = waitDuration.inMinutes >= 2;

                  return ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.person)),
                    title: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(_usernames[p.userId] ?? 'Anonymous',
                                style: TextStyle(
                                    fontWeight: isMe
                                        ? FontWeight.bold
                                        : FontWeight.normal)),
                            const SizedBox(width: 8),
                            if (p.userId == _adminId ||
                                (_adminId == null && i == 0))
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                    color: Colors.amber.shade100,
                                    borderRadius: BorderRadius.circular(4)),
                                child: const Text("HOST",
                                    style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.amber)),
                              )
                            else
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                    color: Colors.blue.shade100,
                                    borderRadius: BorderRadius.circular(4)),
                                child: const Text("PLAYER",
                                    style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.blue)),
                              ),
                          ],
                        ),
                        Text(
                          'Entered: ${TimeOfDay.fromDateTime(joinTime).format(context)} (${waitDuration.inMinutes}m ago)',
                          style: TextStyle(
                            fontSize: 10,
                            color: needsRefresh ? Colors.red : Colors.grey,
                            fontWeight: needsRefresh
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                        if (isMe && needsRefresh)
                          const Padding(
                            padding: EdgeInsets.only(top: 4),
                            child: Text(
                              "Waiting too long? Try exiting and coming back.",
                              style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.red,
                                  fontStyle: FontStyle.italic),
                            ),
                          ),
                      ],
                    ),
                    trailing: p.isReady
                        ? const Icon(Icons.check_circle, color: Colors.green)
                        : null,
                  );
                },
              ),

        if (isHost)
          Padding(
            padding: const EdgeInsets.all(20),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: (_maxPlayers == null && _participants.length > 1) ||
                        (_maxPlayers != null &&
                            _participants.length >= _maxPlayers!)
                    ? _startPreparatoryPhase
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF450E4E),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.all(16),
                ),
                child: Text(
                    (_maxPlayers != null && _participants.length < _maxPlayers!)
                        ? 'Waiting for players...'
                        : 'Start Challenge'),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPreparatoryView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            "WELCOME PARTICIPANTS!",
            style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Color(0xFF450E4E)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          const Text(
            "Quick Match is about to start...",
            style: TextStyle(fontSize: 18, color: Colors.purple),
          ),
          const SizedBox(height: 40),
          _isTeamMode
              ? Wrap(
                  spacing: 30,
                  runSpacing: 30,
                  alignment: WrapAlignment.center,
                  children: (() {
                    final Map<String, List<GamePlayerModel>> teams = {};
                    for (var p in _participants) {
                      final tName = p.teamName ?? 'No Team';
                      if (!teams.containsKey(tName)) teams[tName] = [];
                      teams[tName]!.add(p);
                    }

                    return teams.entries.map((entry) {
                      final tName = entry.key;
                      final members = entry.value;
                      return Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF450E4E),
                              borderRadius: BorderRadius.circular(15),
                              boxShadow: [
                                BoxShadow(
                                    color: Colors.black.withOpacity(0.2),
                                    blurRadius: 8,
                                    offset: const Offset(0, 4)),
                              ],
                            ),
                            child: Column(
                              children: [
                                Text(
                                  tName.toUpperCase(),
                                  style: const TextStyle(
                                      color: Colors.yellow,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16),
                                ),
                                Text(
                                  "${members.length} MEMBERS",
                                  style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            children: members
                                .map((m) => Column(
                                      children: [
                                        const CircleAvatar(
                                            radius: 15,
                                            child:
                                                Icon(Icons.person, size: 18)),
                                        const SizedBox(height: 4),
                                        Text(
                                          _usernames[m.userId] ?? 'Anonymous',
                                          style: const TextStyle(
                                              fontSize: 9,
                                              fontWeight: FontWeight.w600),
                                        ),
                                      ],
                                    ))
                                .toList(),
                          ),
                        ],
                      );
                    }).toList();
                  })(),
                )
              : Wrap(
                  spacing: 20,
                  runSpacing: 20,
                  alignment: WrapAlignment.center,
                  children: _participants
                      .map((p) => Column(
                            children: [
                              const CircleAvatar(
                                  radius: 30,
                                  child: Icon(Icons.person, size: 40)),
                              const SizedBox(height: 8),
                              Text(_usernames[p.userId] ?? 'Anonymous',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                            ],
                          ))
                      .toList(),
                ),
          const SizedBox(height: 60),
          const CircularProgressIndicator(),
          const SizedBox(height: 20),
          const Text("GET READY!",
              style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.orange)),
        ],
      ),
    );
  }

  Widget _buildTeamGroupedList() {
    final Map<String, List<GamePlayerModel>> teams = {};
    for (var p in _participants) {
      final tName = p.teamName ?? 'No Team';
      if (!teams.containsKey(tName)) teams[tName] = [];
      teams[tName]!.add(p);
    }

    final teamNames = teams.keys.toList();

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: teamNames.length,
      itemBuilder: (context, i) {
        final tName = teamNames[i];
        final members = teams[tName]!;
        final tCode = members.first.teamCode;

        return ExpansionTile(
          initiallyExpanded: true,
          title: Text(tName,
              style: const TextStyle(
                  fontWeight: FontWeight.bold, color: Color(0xFF450E4E))),
          subtitle: tCode != null
              ? Row(
                  children: [
                    Text('Team Code: $tCode (${members.length}/5 members)'),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.copy,
                          size: 18, color: Color(0xFF450E4E)),
                      onPressed: () {
                        final senderName =
                            (_usernames[supabase.auth.currentUser?.id] ??
                                    'Someone')
                                .toUpperCase();
                        final teamNameCaps = tName.toUpperCase();
                        final inviteText =
                            '$senderName has invited you to participate in the FIFMI Legacy Quiz Challenge.\n\n'
                            '1. Join the Session using Code: $_joinCode\n'
                            '2. Join Team "$teamNameCaps" using Team Code: $tCode';

                        Clipboard.setData(ClipboardData(text: inviteText));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Full invitation copied!'),
                              duration: Duration(seconds: 2)),
                        );
                      },
                    ),
                  ],
                )
              : null,
          children: members
              .map((m) => ListTile(
                    dense: true,
                    leading: const Icon(Icons.person_outline, size: 20),
                    title: Text(_usernames[m.userId] ?? 'Anonymous'),
                  ))
              .toList(),
        );
      },
    );
  }

  Widget _menuButton(String label, IconData icon, VoidCallback onPressed) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        icon: Icon(icon),
        label: Text(label),
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 15),
          backgroundColor: const Color(0xFF450E4E),
          foregroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }
}
