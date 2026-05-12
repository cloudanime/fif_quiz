class UserModel {
  final String id;
  final String username;
  final DateTime createdAt;

  UserModel({required this.id, required this.username, required this.createdAt});

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: (json['id'] ?? '').toString(),
      username: (json['username'] ?? 'Anonymous').toString(),
      createdAt: json['created_at'] != null 
          ? DateTime.parse(json['created_at'].toString()) 
          : DateTime.now(),
    );
  }
}

class GameModel {
  final String id;
  final String mode;
  final String? adminId;
  final String status;
  final String? joinCode;
  final int? maxPlayers;
  final int questionCount;
  final bool isAutoStart;
  final bool isTeamMode;
  final DateTime createdAt;

  GameModel({
    required this.id,
    required this.mode,
    this.adminId,
    required this.status,
    this.joinCode,
    this.maxPlayers,
    this.questionCount = 10,
    this.isAutoStart = false,
    this.isTeamMode = false,
    required this.createdAt,
  });

  factory GameModel.fromJson(Map<String, dynamic> json) {
    return GameModel(
      id: (json['id'] ?? '').toString(),
      mode: (json['mode'] ?? 'private').toString(),
      adminId: json['admin_id']?.toString(),
      status: (json['status'] ?? 'waiting').toString(),
      joinCode: json['join_code']?.toString(),
      maxPlayers: (json['max_players'] ?? 0) as int?,
      questionCount: (json['question_count'] ?? 10) as int,
      isAutoStart: json['is_auto_start'] == true,
      isTeamMode: json['is_team_mode'] == true,
      createdAt: json['created_at'] != null 
          ? DateTime.parse(json['created_at'].toString()) 
          : DateTime.now(),
    );
  }
}

class QuestionModel {
  final String id;
  final String? gameId;
  final String questionText;
  final String questionType;
  final List<String>? options;
  final String? answer;
  final String source;
  final int points;
  final List<String> imageUrls;
  final int approved;
  final String? imagePath1;
  final String? imagePath2;
  final String? imagePath3;
  final String? imagePath4;
  final DateTime createdAt;

  QuestionModel({
    required this.id,
    this.gameId,
    required this.questionText,
    required this.questionType,
    this.options,
    this.answer,
    this.source = '',
    this.points = 2,
    this.imageUrls = const [],
    this.approved = 0,
    this.imagePath1,
    this.imagePath2,
    this.imagePath3,
    this.imagePath4,
    required this.createdAt,
  });

  factory QuestionModel.fromJson(Map<String, dynamic> json) {
    List<String>? parsedOptions;
    List<String> imageUrls = [];
    final dynamic optionsData = json['options'];
    
    // Check for image paths directly in the json (SQL dump structure)
    if (json.containsKey('image_path_1') && json['image_path_1'] != null) imageUrls.add(json['image_path_1'].toString());
    if (json.containsKey('image_path_2') && json['image_path_2'] != null) imageUrls.add(json['image_path_2'].toString());
    if (json.containsKey('image_path_3') && json['image_path_3'] != null) imageUrls.add(json['image_path_3'].toString());
    if (json.containsKey('image_path_4') && json['image_path_4'] != null) imageUrls.add(json['image_path_4'].toString());

    if (optionsData != null) {
      if (optionsData is List) {
        parsedOptions = List<String>.from(optionsData);
      } else if (optionsData is Map<String, dynamic>) {
        parsedOptions = [];
        if (optionsData.containsKey('option_a') || optionsData.containsKey('A')) {
          parsedOptions.add('A. ${optionsData['option_a'] ?? optionsData['A'] ?? ''}');
        }
        if (optionsData.containsKey('option_b') || optionsData.containsKey('B')) {
          parsedOptions.add('B. ${optionsData['option_b'] ?? optionsData['B'] ?? ''}');
        }
        if (optionsData.containsKey('option_c') || optionsData.containsKey('C')) {
          parsedOptions.add('C. ${optionsData['option_c'] ?? optionsData['C'] ?? ''}');
        }
        if (optionsData.containsKey('option_d') || optionsData.containsKey('D')) {
          parsedOptions.add('D. ${optionsData['option_d'] ?? optionsData['D'] ?? ''}');
        }
        
        // Also check for images inside options map if any
        if (optionsData.containsKey('images') && optionsData['images'] is List) {
          imageUrls.addAll(List<String>.from(optionsData['images']));
        }
      }
    }

    return QuestionModel(
      id: (json['id'] ?? json['question_id'] ?? '').toString(),
      gameId: json['game_id']?.toString(),
      questionText: (json['question_text'] ?? json['question'] ?? '').toString(),
      questionType: (json['question_type'] ?? (json.containsKey('option_a') ? 'mcq' : 'structured')).toString(),
      options: parsedOptions,
      answer: (json['answer'] ?? json['correct_answer'] ?? '').toString(),
      source: (json['source'] ?? '').toString(),
      points: (json['points'] ?? 2) as int,
      imageUrls: imageUrls,
      approved: (json['approved'] ?? 0) is int 
          ? (json['approved'] ?? 0) 
          : int.tryParse(json['approved'].toString()) ?? 0,
      imagePath1: json['image_path_1']?.toString(),
      imagePath2: json['image_path_2']?.toString(),
      imagePath3: json['image_path_3']?.toString(),
      imagePath4: json['image_path_4']?.toString(),
      createdAt: json['created_at'] != null 
          ? DateTime.parse(json['created_at'].toString()) 
          : DateTime.now(),
    );
  }
}

class AnswerModel {
  final String id;
  final String gameId;
  final String questionId;
  final String userId;
  final String answer;
  final bool isCorrect;
  final DateTime answeredAt;

  AnswerModel({required this.id, required this.gameId, required this.questionId, required this.userId, required this.answer, required this.isCorrect, required this.answeredAt});

  factory AnswerModel.fromJson(Map<String, dynamic> json) {
    return AnswerModel(
      id: (json['id'] ?? '').toString(),
      gameId: (json['game_id'] ?? '').toString(),
      questionId: (json['question_id'] ?? '').toString(),
      userId: (json['user_id'] ?? '').toString(),
      answer: (json['answer'] ?? '').toString(),
      isCorrect: json['is_correct'] == true,
      answeredAt: json['answered_at'] != null 
          ? DateTime.parse(json['answered_at'].toString()) 
          : DateTime.now(),
    );
  }
}

class GamePlayerModel {
  final String id;
  final String gameId;
  final String userId;
  final int score;
  final bool isReady;
  final DateTime joinedAt;
  final String? username;
  final String? lastSelection;
  final String? displayName;
  final String? teamName;
  final String? teamCode;

  GamePlayerModel({
    required this.id,
    required this.gameId,
    required this.userId,
    required this.score,
    required this.isReady,
    required this.joinedAt,
    this.username,
    this.lastSelection,
    this.displayName,
    this.teamName,
    this.teamCode,
  });

  factory GamePlayerModel.fromJson(Map<String, dynamic> json) {
    return GamePlayerModel(
      id: (json['id'] ?? '').toString(),
      gameId: (json['game_id'] ?? '').toString(),
      userId: (json['user_id'] ?? '').toString(),
      score: (json['score'] ?? 0) as int,
      isReady: json['is_ready'] == true,
      joinedAt: json['joined_at'] != null 
          ? DateTime.parse(json['created_at']?.toString() ?? json['joined_at'].toString()) 
          : DateTime.now(),
      username: json['users']?['username']?.toString(),
      lastSelection: json['last_selection']?.toString(),
      displayName: json['display_name']?.toString(),
      teamName: json['team_name']?.toString(),
      teamCode: json['team_code']?.toString(),
    );
  }
}
