import 'dart:convert';

class PictureQuestion {
  final String id;
  final String question;
  final List<String> imageUrls;
  final String answer;
  final int points;
  final String source;

  PictureQuestion({
    required this.id,
    required this.question,
    required this.imageUrls,
    required this.answer,
    required this.points,
    required this.source,
  });

  // A factory method to parse JSON data into a PictureQuestion object
  factory PictureQuestion.fromJson(Map<String, dynamic> json) {
    List<String> images = [];
    
    // Check for nested images
    var options = json['options'];
    if (options is String && options.isNotEmpty) {
      try {
        options = jsonDecode(options);
      } catch (_) {
        options = null;
      }
    }

    if (options != null && options is Map && options['images'] != null) {
      images = (options['images'] as List<dynamic>).cast<String>();
    } else {
      // Fallback for flat structure (PHP)
      for (int i = 1; i <= 4; i++) {
        final path = json['image_path_$i'];
        if (path != null && path.toString().isNotEmpty) {
          images.add(path.toString());
        }
      }
    }
    
    return PictureQuestion(
      id: (json['id'] ?? json['question_id'] ?? '').toString(),
      question: (json['question'] ?? json['question_text'] ?? '').toString(),
      imageUrls: images,
      answer: (json['answer'] ?? json['correct_answer'] ?? '').toString(),
      points: int.tryParse((json['points'] ?? '2').toString()) ?? 2,
      source: (json['source'] ?? '').toString(),
    );
  }
}
