import 'package:supabase_flutter/supabase_flutter.dart';
import 'mcq_question.dart';
import 'picture_question.dart';
import 'structured_question.dart';
import 'services/quiz_supabase_service.dart';
import 'models/supabase_models.dart';

class QuizService {
  static final _supabase = Supabase.instance.client;
  static final _supabaseQuizService = SupabaseQuizService();

  // Unified Fetch: This now uses the same 70/15/15 split logic as the Online Challenge
  static Future<List<dynamic>> fetchAllQuestions({required String sessionId}) async {
    print('Fetching Supabase questions for session: $sessionId');
    
    // We fetch 100 questions using the same proportion logic as Online Mode
    final List<QuestionModel?> models = await _supabaseQuizService.fetchOnlineQuestions(100);
    
    // Convert QuestionModel (Supabase) to the specific types expected by QuizGridPage
    return models.map((m) {
      if (m == null) return null;
      if (m.questionType == 'multiple_choice') {
        return MCQQuestion(
          questionText: m.questionText,
          answers: {
            if (m.options != null && m.options!.isNotEmpty)
              for (var opt in m.options!) opt: (m.answer != null && opt.startsWith(m.answer!))
          },
          points: m.points,
          correctLetter: m.answer ?? 'A',
          correctAnswer: m.answer ?? '',
          source: m.source,
        );
      } else if (m.questionType == 'picture') {
        return PictureQuestion(
          id: m.id,
          question: m.questionText,
          imageUrls: m.imageUrls,
          answer: m.answer ?? '',
          points: m.points,
          source: m.source,
        );
      } else {
        return StructuredQuestion(
          questionId: m.id,
          question: m.questionText,
          correctAnswer: m.answer ?? '',
          points: m.points,
          source: m.source,
        );
      }
    }).toList();
  }

  // Compatibility methods for QuizGridPage
  static Future<List<MCQQuestion>> fetchQuestions({required String sessionId}) async {
    final all = await fetchAllQuestions(sessionId: sessionId);
    return all.whereType<MCQQuestion>().toList();
  }

  static Future<List<PictureQuestion>> fetchPictureQuestions({required String sessionId}) async {
    final all = await fetchAllQuestions(sessionId: sessionId);
    return all.whereType<PictureQuestion>().toList();
  }

  static Future<List<StructuredQuestion>> fetchStructuredQuestions({required String sessionId}) async {
    final all = await fetchAllQuestions(sessionId: sessionId);
    return all.whereType<StructuredQuestion>().toList();
  }

  // Create a new session in Supabase (consistent with Online Mode)
  static Future<String> createSession() async {
    final gameId = await _supabaseQuizService.createGame(
      mode: 'admin_hosted',
      status: 'waiting',
      adminId: _supabase.auth.currentUser?.id,
      questionCount: 100,
    );
    return gameId ?? 'local-session-${DateTime.now().millisecondsSinceEpoch}';
  }
}
