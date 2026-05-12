import 'dart:convert';

class MCQQuestion {
  final String questionText;
  final Map<String, bool>
      answers; // A map to store answer options and whether they are correct
  final int points;
  final String correctAnswer; 
  final String correctLetter; // Store A, B, C, or D
  final String source;

  MCQQuestion({
    required this.questionText,
    required this.answers,
    required this.points,
    required this.correctAnswer,
    required this.correctLetter,
    required this.source,
  });

  factory MCQQuestion.fromJson(Map<String, dynamic> json) {
    // Always parse options as JSON if it's a String
    final dynamic optionsData = json['options'];
    Map<String, dynamic> options = {};

    if (optionsData != null && optionsData is String) {
      try {
        dynamic decoded = jsonDecode(optionsData);
        // Handle potential double-encoded JSON from SQLite
        while (decoded is String) {
          try {
            decoded = jsonDecode(decoded);
          } catch (_) {
            break; // Stop if it's just a regular string
          }
        }
        if (decoded is Map) {
          options = Map<String, dynamic>.from(decoded);
        } else if (decoded is List) {
          if (decoded.isNotEmpty && decoded.first is Map) {
            for (var item in decoded) {
              if (item is Map) options.addAll(Map<String, dynamic>.from(item));
            }
          } else {
            if (decoded.length > 0) options['A'] = decoded[0];
            if (decoded.length > 1) options['B'] = decoded[1];
            if (decoded.length > 2) options['C'] = decoded[2];
            if (decoded.length > 3) options['D'] = decoded[3];
          }
        } else {
          throw Exception('Not a Map or List');
        }
      } catch (e) {
        options = {};
        try {
          final str = optionsData.toString();
          final aMatch = RegExp(r'A"?\s*:\s*"?([^"]*?)"?(?:\s*,\s*"?[B-E]"?\s*:|\s*})').firstMatch(str);
          final bMatch = RegExp(r'B"?\s*:\s*"?([^"]*?)"?(?:\s*,\s*"?[C-E]"?\s*:|\s*})').firstMatch(str);
          final cMatch = RegExp(r'C"?\s*:\s*"?([^"]*?)"?(?:\s*,\s*"?[D-E]"?\s*:|\s*})').firstMatch(str);
          final dMatch = RegExp(r'D"?\s*:\s*"?([^"]*?)"?(?:\s*,\s*"?[E]"?\s*:|\s*})').firstMatch(str);
          
          if (aMatch != null) options['A'] = aMatch.group(1)!.trim();
          if (bMatch != null) options['B'] = bMatch.group(1)!.trim();
          if (cMatch != null) options['C'] = cMatch.group(1)!.trim();
          if (dMatch != null) options['D'] = dMatch.group(1)!.trim();
        } catch (_) {}
      }
    } else if (optionsData != null && optionsData is Map) {
      options = Map<String, dynamic>.from(optionsData);
    } else if (optionsData != null && optionsData is List) {
      if (optionsData.isNotEmpty && optionsData.first is Map) {
        for (var item in optionsData) {
          if (item is Map) options.addAll(Map<String, dynamic>.from(item));
        }
      } else {
        if (optionsData.length > 0) options['A'] = optionsData[0];
        if (optionsData.length > 1) options['B'] = optionsData[1];
        if (optionsData.length > 2) options['C'] = optionsData[2];
        if (optionsData.length > 3) options['D'] = optionsData[3];
      }
    }

    // Normalize all keys to uppercase 'A', 'B', 'C', 'D' to prevent case-mismatch bugs
    Map<String, dynamic> normalizedOptions = {};
    options.forEach((key, value) {
      String upperKey = key.toString().toUpperCase().replaceAll('OPTION_', '');
      normalizedOptions[upperKey] = value;
    });
    options = normalizedOptions;

    // Final fallback for flat PHP structure if normalizedOptions is completely empty
    if (options.isEmpty) {
      options = {
        'A': json['option_a'] ?? '',
        'B': json['option_b'] ?? '',
        'C': json['option_c'] ?? '',
        'D': json['option_d'] ?? '',
      };
    }

    final correctAnswerKey = (json['correct_answer'] ?? json['answer'] ?? 'A').toString().toUpperCase();

    return MCQQuestion(
      questionText: (json['question'] ?? json['question_text'] ?? '').toString(),
      answers: {
        'A. ${options['A'] ?? options['option_a'] ?? ''}': correctAnswerKey == 'A',
        'B. ${options['B'] ?? options['option_b'] ?? ''}': correctAnswerKey == 'B',
        'C. ${options['C'] ?? options['option_c'] ?? ''}': correctAnswerKey == 'C',
        'D. ${options['D'] ?? options['option_d'] ?? ''}': correctAnswerKey == 'D',
      },
      points: int.tryParse((json['points'] ?? '2').toString()) ?? 2,
      correctLetter: correctAnswerKey,
      correctAnswer: (options[correctAnswerKey] ?? options['option_${correctAnswerKey.toLowerCase()}'] ?? '').toString(),
      source: (json['source'] ?? '').toString(),
    );
  }
}
