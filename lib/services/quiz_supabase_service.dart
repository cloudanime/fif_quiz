import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/supabase_models.dart';

class SupabaseQuizService {
    Future<void> updateGameStatus(String gameId, String status) async {
      await supabase.from('games').update({'status': status}).eq('id', gameId);
    }

    // Create a new game
    Future<String?> createGame({
      required String mode,
      String? adminId,
      required String status,
      String? joinCode,
      int? maxPlayers,
      int questionCount = 10,
      int timerDuration = 30,
      bool isAutoStart = false,
      bool isTeamMode = false,
    }) async {
      final response = await supabase.from('games').insert({
        'mode': mode,
        'admin_id': adminId,
        'status': status,
        'join_code': joinCode,
        'max_players': maxPlayers,
        'question_count': questionCount,
        'is_auto_start': isAutoStart,
        'is_team_mode': isTeamMode,
      }).select();
      final list = response as List<dynamic>;
      if (list.isNotEmpty) {
        return list.first['id'] as String?;
      }
      return null;
    }

    // Join a game by ID
    Future<void> joinGame({
      required String gameId,
      required String userId,
    }) async {
      // Check if already in game to prevent duplicates
      final existing = await supabase
          .from('game_players')
          .select('id')
          .eq('game_id', gameId)
          .eq('user_id', userId)
          .maybeSingle();

      if (existing == null) {
        await supabase.from('game_players').insert({
          'game_id': gameId,
          'user_id': userId,
        });
      }
    }

    // Join a game by 6-digit code
    Future<String?> joinGameByCode({
      required String joinCode,
      required String userId,
    }) async {
      final response = await supabase
          .from('games')
          .select('id, max_players, status')
          .eq('join_code', joinCode)
          .eq('status', 'waiting')
          .single();
      
      final gameId = response['id'] as String;
      
      // Check if room is full if it has a max_players limit
      if (response['max_players'] != null) {
        final playersResponse = await supabase
            .from('game_players')
            .select('id')
            .eq('game_id', gameId);
        
        if ((playersResponse as List).length >= (response['max_players'] as int)) {
          throw Exception('This room is full');
        }
      }

      await joinGame(gameId: gameId, userId: userId);
      return gameId;
    }

    // Set player ready status
    Future<void> setPlayerReady(String gameId, String userId, bool isReady) async {
      await supabase
          .from('game_players')
          .update({'is_ready': isReady})
          .eq('game_id', gameId)
          .eq('user_id', userId);
    }

    // Submit an answer
    Future<void> submitAnswer({
      required String gameId,
      required String questionId,
      required String userId,
      required String answer,
      required bool isCorrect,
    }) async {
      await supabase.from('answers').insert({
        'game_id': gameId,
        'question_id': questionId,
        'user_id': userId,
        'answer': answer,
        'is_correct': isCorrect,
      });
    }

    // Update answer correctness (Host marking)
    Future<void> updateAnswerCorrectness({
      required String gameId,
      required String questionId,
      required String userId,
      required bool isCorrect,
    }) async {
      await supabase
          .from('answers')
          .update({'is_correct': isCorrect})
          .eq('game_id', gameId)
          .eq('question_id', questionId)
          .eq('user_id', userId);
    }

    // Fetch all answers for a specific game to reconstruct history
    Future<List<AnswerModel>> fetchGameAnswers(String gameId) async {
      final response = await supabase
          .from('answers')
          .select()
          .eq('game_id', gameId);
      
      final List<dynamic> data = response as List<dynamic>;
      return data.map((json) => AnswerModel.fromJson(json)).toList();
    }
  final supabase = Supabase.instance.client;

  // Fetch all games
  Future<List<GameModel>> fetchGames() async {
    final data = await supabase.from('games').select();
    final list = data as List<dynamic>;
    return list.map((e) => GameModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  // Fetch questions for a game
  Future<List<QuestionModel>> fetchQuestions(String gameId) async {
    final data = await supabase.from('questions').select().eq('game_id', gameId);
    final list = data as List<dynamic>;
    return list.map((e) => QuestionModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  // Fetch random questions for an online session respecting the grid structure:
  // 1-70: MCQ (70)
  // 71-85: Structured (15)
  // 86-100: Picture (15)
  Future<List<QuestionModel?>> fetchOnlineQuestions(int totalCount) async {
    try {
      // Strictly defined slots for a 100-question grid
      final List<String?> slots = List<String?>.filled(100, null);
      
      // 1-70: MCQ (70 slots)
      final mcqIds = await _getRandomIdsByType('multiple_choice', 70);
      for (int i = 0; i < mcqIds.length && i < 70; i++) {
        slots[i] = mcqIds[i];
      }
      
      // 71-80: Picture (10 slots)
      final pictureIds = await _getRandomIdsByType('picture', 10);
      for (int i = 0; i < pictureIds.length && i < 10; i++) {
        slots[70 + i] = pictureIds[i];
      }
      
      // 81-100: Structured (20 slots)
      final structuredIds = await _getRandomIdsByType('structured', 20);
      for (int i = 0; i < structuredIds.length && i < 20; i++) {
        slots[80 + i] = structuredIds[i];
      }

      // Filter out nulls for the actual DB storage (which expects non-null strings), 
      // but the order of non-nulls now respects their category boundaries.
      // Wait, if I filter out nulls, the indices will still shift if some are empty.
      // To keep them strictly at 70, 80 etc., we need to store them as a 100-item list.
      // If the DB supports nulls or empty strings, we use those.
      final List<String> finalIds = slots.map((id) => id ?? "EMPTY").toList();
      
      return await fetchQuestionsByIds(finalIds);
    } catch (e) {
      print("Error fetching structured random questions: $e");
      final data = await supabase.from('questions').select().limit(totalCount);
      return (data as List).map((e) => QuestionModel.fromJson(e)).toList();
    }
  }

  Future<List<String>> _getRandomIdsByType(String type, int count) async {
    var query = supabase.from('questions').select('id, options, answer');
    
    if (type == 'multiple_choice' || type == 'mcq') {
      query = query.or('question_type.eq.mcq,question_type.eq.multiple_choice');
    } else {
      query = query.eq('question_type', type);
    }
    
    final response = await query.eq('approved', 1);
    
    final List<dynamic> data = response as List<dynamic>;
    if (data.isEmpty) return [];

    final List<String> validIds = [];
    for (final item in data) {
      final String? answer = item['answer']?.toString().trim();
      if (answer == null || answer.isEmpty) continue;

      if (type == 'multiple_choice' || type == 'mcq') {
        final dynamic options = item['options'];
        bool hasOptions = false;
        if (options != null) {
          if (options is Map) {
            hasOptions = options.values.any((v) => v != null && v.toString().trim().isNotEmpty);
          } else if (options is List) {
            hasOptions = options.isNotEmpty;
          } else if (options is String) {
            final trimmed = options.trim();
            if (trimmed.isNotEmpty && trimmed != '{}' && trimmed != '[]') {
              try {
                final decoded = jsonDecode(trimmed);
                if (decoded is Map) {
                  hasOptions = decoded.values.any((v) => v != null && v.toString().trim().isNotEmpty);
                } else if (decoded is List) {
                  hasOptions = decoded.isNotEmpty;
                }
              } catch (_) {}
            }
          }
        }
        if (!hasOptions) continue;
      }
      
      validIds.add(item['id'].toString());
    }

    validIds.shuffle();
    return validIds.take(count).toList();
  }

  // Update current question index for synchronization
  Future<void> nextQuestion(String gameId, int nextIndex) async {
    await supabase
        .from('games')
        .update({'current_question_index': nextIndex})
        .eq('id', gameId);
  }

  // Submit score update
  Future<void> updatePlayerScore(String gameId, String userId, int points) async {
    try {
      // Fetch current score first
      final response = await supabase
          .from('game_players')
          .select('score')
          .eq('game_id', gameId)
          .eq('user_id', userId)
          .maybeSingle();
      
      if (response == null) {
        print("Scoring Error: No game_player record found for user $userId in game $gameId");
        return;
      }

      final currentScore = (response['score'] ?? 0) as int;
      final newScore = currentScore + points;
      
      await supabase
          .from('game_players')
          .update({'score': newScore})
          .eq('game_id', gameId)
          .eq('user_id', userId)
          .eq('score', currentScore); // Only update if no one else has!
          
      print("Scoring Success: Updated user $userId score to $newScore");
    } catch (e) {
      print("Scoring Exception for user $userId: $e");
    }
  }
  // Lock in a set of questions for all players in a game
  Future<void> initializeGameQuestions(String gameId, int count) async {
    final questions = await fetchOnlineQuestions(count);
    final ids = questions.map((q) => q?.id ?? "EMPTY").toList();
    
    await supabase
        .from('games')
        .update({'question_ids': ids})
        .eq('id', gameId);
  }

  // Fetch specific questions by their IDs and preserve the list order (including empty slots)
  Future<List<QuestionModel?>> fetchQuestionsByIds(List<dynamic> ids) async {
    if (ids.isEmpty) return [];
    
    final response = await supabase
        .from('questions')
        .select()
        .filter('id', 'in', ids.where((id) => id != "EMPTY").toList());
    
    final List<dynamic> data = response as List<dynamic>;
    final fetchedQuestions = data.map((e) => QuestionModel.fromJson(e as Map<String, dynamic>)).toList();

    // Sort to match the order of the original IDs list
    final Map<String, QuestionModel> lookup = {for (var q in fetchedQuestions) q.id: q};
    return ids.map((id) => lookup[id.toString()]).toList();
  }
}
