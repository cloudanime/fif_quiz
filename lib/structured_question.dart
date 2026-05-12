class StructuredQuestion {
  final String questionId;
  final String question;
  final String correctAnswer;
  final int points;
  final String source;

  StructuredQuestion({
    required this.questionId,
    required this.question,
    required this.correctAnswer,
    required this.points,
    required this.source,
  });

  factory StructuredQuestion.fromJson(Map<String, dynamic> json) {
    return StructuredQuestion(
      questionId: (json['id'] ?? json['question_id'] ?? '').toString(),
      question: (json['question'] ?? json['question_text'] ?? '').toString(),
      correctAnswer: (json['answer'] ?? json['correct_answer'] ?? '').toString(),
      points: int.tryParse((json['points'] ?? '2').toString()) ?? 2,
      source: (json['source'] ?? '').toString(),
    );
  }
}
