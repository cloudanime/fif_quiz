import 'dart:convert';
import 'package:flutter/foundation.dart';

class User {
  final String id;
  final String username;
  final String createdAt;

  User({required this.id, required this.username, required this.createdAt});

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'username': username,
      'created_at': createdAt,
    };
  }

  factory User.fromMap(Map<String, dynamic> map) {
    return User(
      id: map['id'],
      username: map['username'],
      createdAt: map['created_at'],
    );
  }
}

class Game {
  final String id;
  final String mode;
  final String status;
  final String createdAt;
  final int maxPlayers;
  final int questionCount;

  Game({
    required this.id,
    required this.mode,
    required this.status,
    required this.createdAt,
    required this.maxPlayers,
    required this.questionCount,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'mode': mode,
      'status': status,
      'created_at': createdAt,
      'max_players': maxPlayers,
      'question_count': questionCount,
    };
  }

  factory Game.fromMap(Map<String, dynamic> map) {
    return Game(
      id: map['id'],
      mode: map['mode'],
      status: map['status'],
      createdAt: map['created_at'],
      maxPlayers: map['max_players'],
      questionCount: map['question_count'],
    );
  }
}

class GamePlayer {
  final String id;
  final String gameId;
  final String userId;
  final int score;
  final String joinedAt;
  final String displayName;

  GamePlayer({
    required this.id,
    required this.gameId,
    required this.userId,
    required this.score,
    required this.joinedAt,
    required this.displayName,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'game_id': gameId,
      'user_id': userId,
      'score': score,
      'joined_at': joinedAt,
      'display_name': displayName,
    };
  }

  factory GamePlayer.fromMap(Map<String, dynamic> map) {
    return GamePlayer(
      id: (map['id'] ?? '').toString(),
      gameId: (map['game_id'] ?? '').toString(),
      userId: (map['user_id'] ?? '').toString(),
      score: int.tryParse(map['score']?.toString() ?? '0') ?? 0,
      joinedAt: (map['joined_at'] ?? '').toString(),
      displayName: (map['display_name'] ?? '').toString(),
    );
  }
}

class Question {
  final String id;
  final String gameId;
  final String questionText;
  final String questionType;
  final String options; // JSON string
  final String answer;
  final String createdAt;
  final String source;
  final int approved;
  final int points;
  final String? imagePath1;
  final String? imagePath2;
  final String? imagePath3;
  final String? imagePath4;
  int? selectedOption; // Added for UI state (nullable)

  Question({
    required this.id,
    required this.gameId,
    required this.questionText,
    required this.questionType,
    required this.options,
    required this.answer,
    required this.createdAt,
    required this.points,
    this.source = '',
    this.approved = 0,
    this.imagePath1,
    this.imagePath2,
    this.imagePath3,
    this.imagePath4,
    this.selectedOption,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'game_id': gameId,
      'question_text': questionText,
      'question_type': questionType,
      'options': options,
      'answer': answer,
      'created_at': createdAt,
      'points': points,
      'source': source,
      'approved': approved,
      'image_path_1': imagePath1,
      'image_path_2': imagePath2,
      'image_path_3': imagePath3,
      'image_path_4': imagePath4,
      'selected_option': selectedOption,
    };
  }

  factory Question.fromMap(Map<String, dynamic> map) {
    // Normalize question type
    String rawQt = (map['question_type'] ?? '').toString();
    String qt = rawQt.toLowerCase().trim();
    if (qt.contains('mcq') || qt.contains('multiple')) {
      qt = 'mcq';
    } else if (qt.contains('picture') || qt.contains('image')) {
      qt = 'picture';
    } else if (qt.contains('struct')) {
      qt = 'structured';
    } else {
      // Default to mcq if empty or unrecognized
      qt = qt.isEmpty ? 'mcq' : qt;
    }
    
    if (rawQt != qt) {
       debugPrint('Normalized question type: $rawQt -> $qt');
    }

    // Handle options (can be Map on Web/Sembast or String on Mobile/SQLite)
    dynamic optionsData = map['options'];
    String optionsStr = '';
    if (optionsData is Map) {
      optionsStr = jsonEncode(optionsData);
    } else {
      optionsStr = (optionsData ?? '').toString();
    }

    return Question(
      id: (map['id'] ?? '').toString(),
      gameId: (map['game_id'] ?? '').toString(),
      questionText: (map['question_text'] ?? '').toString(),
      questionType: qt,
      options: optionsStr,
      answer: (map['answer'] ?? '').toString(),
      createdAt: (map['created_at'] ?? '').toString(),
      points: int.tryParse(map['points']?.toString() ?? '2') ?? 2,
      source: (map['source'] ?? '').toString(),
      approved: int.tryParse(map['approved']?.toString() ?? '0') ?? 0,
      imagePath1: map['image_path_1']?.toString(),
      imagePath2: map['image_path_2']?.toString(),
      imagePath3: map['image_path_3']?.toString(),
      imagePath4: map['image_path_4']?.toString(),
      selectedOption: map['selected_option'],
    );
  }

  bool get isValid {
    final trimmedAnswer = answer.trim();
    if (trimmedAnswer.isEmpty) return false;

    if (questionType == 'mcq') {
      if (options.isEmpty || options == '{}' || options == '[]') return false;
      try {
        final decoded = jsonDecode(options);
        if (decoded is Map) {
          return decoded.values.any((v) => v != null && v.toString().trim().isNotEmpty);
        } else if (decoded is List) {
          return decoded.isNotEmpty;
        }
      } catch (_) {
        return false;
      }
    }
    return true;
  }
}

class Answer {
  final String id;
  final String gameId;
  final String questionId;
  final String userId;
  final String answer;
  final int isCorrect;
  final String answeredAt;

  Answer({
    required this.id,
    required this.gameId,
    required this.questionId,
    required this.userId,
    required this.answer,
    required this.isCorrect,
    required this.answeredAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'game_id': gameId,
      'question_id': questionId,
      'user_id': userId,
      'answer': answer,
      'is_correct': isCorrect,
      'answered_at': answeredAt,
    };
  }

  factory Answer.fromMap(Map<String, dynamic> map) {
    return Answer(
      id: (map['id'] ?? '').toString(),
      gameId: (map['game_id'] ?? '').toString(),
      questionId: (map['question_id'] ?? '').toString(),
      userId: (map['user_id'] ?? '').toString(),
      answer: (map['answer'] ?? '').toString(),
      isCorrect: int.tryParse(map['is_correct']?.toString() ?? '0') ?? 0,
      answeredAt: (map['answered_at'] ?? '').toString(),
    );
  }
}
