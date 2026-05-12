import 'package:church_quiz/offline/local_db_service.dart';
import 'package:church_quiz/offline/local_db_service_web.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'offline_quiz_page.dart';

class OfflinePlayerSetupPage extends StatefulWidget {
  const OfflinePlayerSetupPage({super.key});

  @override
  State<OfflinePlayerSetupPage> createState() => _OfflinePlayerSetupPageState();
}

class _OfflinePlayerSetupPageState extends State<OfflinePlayerSetupPage> {
  final List<TextEditingController> _controllers = [TextEditingController()];

  @override
  void dispose() {
    for (var c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _addPlayerField() {
    setState(() {
      _controllers.add(TextEditingController());
    });
  }

  void _removePlayerField(int index) {
    setState(() {
      if (_controllers.length > 1) {
        _controllers.removeAt(index);
      }
    });
  }

  Future<void> _startGame() async {
    // Use default names if not provided
    final players = <String>[];
    for (int i = 0; i < _controllers.length; i++) {
      final name = _controllers[i].text.trim();
      players.add(name.isNotEmpty ? name : 'Player ${i + 1}');
    }
    if (players.isEmpty) return;

    // Check for questions first
    int questionCount = 0;
    if (kIsWeb) {
      final questionMaps = await WebDatabaseHelper.getAll('questions');
      questionCount = questionMaps.where((q) => (q['approved'] ?? 0) == 1).length;
    } else {
      final db = await LocalDbService.database;
      final result = await db.rawQuery('SELECT COUNT(*) as count FROM questions WHERE approved = 1');
      questionCount = Sqflite.firstIntValue(result) ?? 0;
    }

    if (questionCount == 0) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('No Questions Found'),
          content: const Text(
            'Cannot start the game because there are no approved questions in your offline database.\n\n'
            'Please go back and click "Sync Cloud" or "Import DB" to load questions first.'
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    final db = await LocalDbService.database;
    final gameId = const Uuid().v4();
    final now = DateTime.now().toIso8601String();
    if (kIsWeb) {
      // Removed destructive clearTable calls to preserve past games/players
      await WebDatabaseHelper.insert('games', gameId, {
        'id': gameId,
        'mode': 'offline_hosted',
        'status': 'active',
        'created_at': now,
        'max_players': players.length,
        'question_count': 0,
      });
      for (int i = 0; i < players.length; i++) {
        final name = players[i];
        final userId = const Uuid().v4();
        // Add millisecond offset to ensure strict ordering by joined_at
        final playerJoinedAt = DateTime.parse(now).add(Duration(milliseconds: i)).toIso8601String();
        await WebDatabaseHelper.insert('users', userId, {
          'id': userId,
          'username': name,
          'created_at': now,
        });
        await WebDatabaseHelper.insert('game_players', const Uuid().v4(), {
          'id': const Uuid().v4(),
          'game_id': gameId,
          'user_id': userId,
          'score': 0,
          'joined_at': playerJoinedAt,
          'display_name': name,
        });
      }
    } else {
      // Removed destructive delete calls to preserve past games/players
      await db.insert('games', {
        'id': gameId,
        'mode': 'offline_hosted',
        'status': 'active',
        'created_at': now,
        'max_players': players.length,
        'question_count': 0,
      });
      for (int i = 0; i < players.length; i++) {
        final name = players[i];
        final userId = const Uuid().v4();
        // Add millisecond offset to ensure strict ordering by joined_at
        final playerJoinedAt = DateTime.parse(now).add(Duration(milliseconds: i)).toIso8601String();
        await db.insert('users', {
          'id': userId,
          'username': name,
          'created_at': now,
        });
        await db.insert('game_players', {
          'id': const Uuid().v4(),
          'game_id': gameId,
          'user_id': userId,
          'score': 0,
          'joined_at': playerJoinedAt,
          'display_name': name,
        });
      }
    }
    // Go directly to the quiz page
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => OfflineQuizPage(gameId: gameId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    
    // Calculate available height for the list
    final appBarHeight = AppBar().preferredSize.height;
    final statusBarHeight = MediaQuery.of(context).padding.top;
    final titleHeight = 24.0 + 16.0; // Text height + SizedBox
    final buttonRowHeight = 48.0 + 16.0; // Add button height + SizedBox
    final startButtonHeight = 48.0 + 16.0; // Start button height + SizedBox
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    
    final availableListHeight = screenHeight - 
        appBarHeight - 
        statusBarHeight - 
        titleHeight - 
        buttonRowHeight - 
        startButtonHeight - 
        bottomPadding - 
        32; // Additional padding
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Players'),
        backgroundColor: const Color.fromARGB(255, 96, 5, 105),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: SingleChildScrollView(
            padding: EdgeInsets.all(screenWidth * 0.04),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
            const Text(
              'Enter Players names or leave as default player numbers:', 
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 16),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _controllers.length,
              itemBuilder: (context, index) {
                return Padding(
                  padding: EdgeInsets.only(bottom: screenHeight * 0.01),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controllers[index],
                          decoration: InputDecoration(
                            labelText: 'Player ${index + 1}',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: screenWidth * 0.03,
                              vertical: 12,
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.remove_circle, color: Colors.red),
                        onPressed: () => _removePlayerField(index),
                      ),
                    ],
                  ),
                );
              },
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ElevatedButton.icon(
                  onPressed: _addPlayerField,
                  icon: const Icon(Icons.add),
                  label: const Text('Add Player'),
                  style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.symmetric(
                      horizontal: screenWidth * 0.04,
                      vertical: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _startGame,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color.fromARGB(255, 96, 5, 105),
                foregroundColor: Colors.white,
                minimumSize: Size(screenWidth, 48),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: const Text('Start Game'),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    ),
  ),
);
}
}