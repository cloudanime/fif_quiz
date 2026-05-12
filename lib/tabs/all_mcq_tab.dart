import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/user_service.dart';

class AllMCQTab extends StatefulWidget {
  const AllMCQTab({super.key});

  @override
  _AllMCQTabState createState() => _AllMCQTabState();
}

class _AllMCQTabState extends State<AllMCQTab> {
  final _supabase = Supabase.instance.client;
  List<dynamic> unapprovedMCQs = [];
  List<dynamic> approvedMCQs = [];
  List<dynamic> filteredUnapproved = [];
  List<dynamic> filteredApproved = [];
  String searchQuery = '';
  String approvalFilter = 'All'; // All, Approved, Unapproved

  @override
  void initState() {
    super.initState();
    fetchMCQQuestions();
  }

  // Fetch MCQ questions from Supabase
  Future<void> fetchMCQQuestions() async {
    try {
      final isSuper = await UserService.isSuperAdmin();
      var query = _supabase
          .from('questions')
          .select()
          .eq('question_type', 'multiple_choice');

      if (!isSuper) {
        query = query.or('approved.eq.0,approved.is.null');
      }

      final response = await query.order('created_at', ascending: false);

      final List<dynamic> data = response as List<dynamic>;
      setState(() {
        unapprovedMCQs = data.where((q) {
          final val = q['approved'] is int ? q['approved'] : int.tryParse(q['approved'].toString()) ?? 0;
          return val == 0 || val == null;
        }).toList();
        approvedMCQs = data.where((q) {
          final val = q['approved'] is int ? q['approved'] : int.tryParse(q['approved'].toString()) ?? 1;
          return val == 1;
        }).toList();
        _applyFilters();
      });
        } catch (e) {
      print('Error fetching Supabase MCQs: $e');
    }
  }

  void _filterQuestions(String query) {
    searchQuery = query;
    _applyFilters();
  }

  void _applyFilters() {
    setState(() {
      final q = searchQuery.toLowerCase();
      
      filteredUnapproved = unapprovedMCQs.where((item) {
        final text = (item['question_text'] ?? '').toString().toLowerCase();
        final source = (item['source'] ?? '').toString().toLowerCase();
        return text.contains(q) || source.contains(q);
      }).toList();

      filteredApproved = approvedMCQs.where((item) {
        final text = (item['question_text'] ?? '').toString().toLowerCase();
        final source = (item['source'] ?? '').toString().toLowerCase();
        return text.contains(q) || source.contains(q);
      }).toList();
    });
  }

  // Parse options safely from various formats
  Map<String, dynamic> _parseOptions(dynamic optionsData) {
    if (optionsData == null) return {};
    if (optionsData is Map<String, dynamic>) return optionsData;
    if (optionsData is String) {
      try {
        final decoded = jsonDecode(optionsData);
        if (decoded is Map<String, dynamic>) return decoded;
      } catch (e) {
        print('Error decoding options JSON: $e');
      }
    }
    return {};
  }

  // Approve MCQ question in Supabase
  Future<void> approveQuestion(dynamic id) async {
    try {
      await _supabase.from('questions').update({'approved': 1}).eq('id', id);
      fetchMCQQuestions();
    } catch (e) {
      print('Error approving question: $e');
    }
  }

  // Delete MCQ question from Supabase
  Future<void> deleteQuestion(dynamic id) async {
    try {
      await _supabase.from('questions').delete().eq('id', id);
      fetchMCQQuestions();
    } catch (e) {
      print('Error deleting question: $e');
    }
  }

  // Update MCQ question - open dialog for editing
  void updateQuestion(dynamic question) {
    TextEditingController questionController = TextEditingController(text: question['question_text'] ?? question['question']);
    final options = _parseOptions(question['options']);
    TextEditingController optionAController = TextEditingController(text: options['option_a'] ?? question['option_a']);
    TextEditingController optionBController = TextEditingController(text: options['option_b'] ?? question['option_b']);
    TextEditingController optionCController = TextEditingController(text: options['option_c'] ?? question['option_c']);
    TextEditingController optionDController = TextEditingController(text: options['option_d'] ?? question['option_d']);
    TextEditingController correctAnswerController = TextEditingController(text: question['answer'] ?? question['correct_answer']);
    TextEditingController sourceController = TextEditingController(text: question['source']);

    int selectedApprovalStatus = (question['approved'] ?? 0) is int ? question['approved'] : int.tryParse(question['approved'].toString()) ?? 0;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Edit Question'),
          content: SingleChildScrollView(
            child: Column(
              children: [
                buildTextField('Question', questionController),
                buildTextField('Option A', optionAController),
                buildTextField('Option B', optionBController),
                buildTextField('Option C', optionCController),
                buildTextField('Option D', optionDController),
                buildTextField('Correct Answer (A, B, C, or D)', correctAnswerController),
                buildTextField('Source', sourceController),
                const SizedBox(height: 10),
                DropdownButtonFormField<int>(
                  decoration: const InputDecoration(
                    labelText: 'Approval Status',
                    border: OutlineInputBorder(),
                  ),
                  initialValue: selectedApprovalStatus,
                  items: const [
                    DropdownMenuItem<int>(value: 0, child: Text('Unapproved')),
                    DropdownMenuItem<int>(value: 1, child: Text('Approved')),
                  ],
                  onChanged: (value) {
                    selectedApprovalStatus = value!;
                  },
                ),
              ],
            ),
          ),
          actions: [
            ElevatedButton(
              onPressed: () async {
                await saveUpdatedQuestion(
                  question['id'],
                  questionController.text,
                  optionAController.text,
                  optionBController.text,
                  optionCController.text,
                  optionDController.text,
                  correctAnswerController.text,
                  sourceController.text,
                  selectedApprovalStatus,
                );
                Navigator.pop(context);
              },
              child: const Text('Save Changes'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  Future<void> saveUpdatedQuestion(dynamic questionId, String questionText, String optionA, String optionB, String optionC, String optionD, String correctAnswer, String source, int approvalStatus) async {
    try {
      await _supabase.from('questions').update({
        'question_text': questionText,
        'options': {
          'option_a': optionA,
          'option_b': optionB,
          'option_c': optionC,
          'option_d': optionD,
        },
        'answer': correctAnswer,
        'source': source,
        'approved': approvalStatus,
      }).eq('id', questionId);
      fetchMCQQuestions();
    } catch (e) {
      print('Error updating Supabase MCQ: $e');
    }
  }

  Widget buildTextField(String labelText, TextEditingController controller) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10.0),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: labelText,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final double titleSize = screenWidth < 600 ? 16 : 18;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(10.0),
          child: Column(
            children: [
              TextField(
                onChanged: _filterQuestions,
                decoration: InputDecoration(
                  hintText: 'Search questions...',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.9),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: ['All', 'Approved', 'Unapproved'].map((f) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: ChoiceChip(
                        label: Text(f),
                        selected: approvalFilter == f,
                        onSelected: (val) {
                          setState(() {
                            if (val) approvalFilter = f;
                            else if (approvalFilter == f) approvalFilter = 'All';
                          });
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(8.0),
            children: [
              if ((approvalFilter == 'All' || approvalFilter == 'Unapproved') && filteredUnapproved.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8.0),
                  child: Text('Unapproved MCQs', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                ...filteredUnapproved.map((q) => buildQuestionCard(q, titleSize)),
              ],
              if ((approvalFilter == 'All' || approvalFilter == 'Approved') && filteredApproved.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16.0),
                  child: Text('Approved MCQs', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                ...filteredApproved.map((q) => buildQuestionCard(q, titleSize)),
              ],
              if ((approvalFilter == 'All' && filteredUnapproved.isEmpty && filteredApproved.isEmpty) ||
                  (approvalFilter == 'Unapproved' && filteredUnapproved.isEmpty) ||
                  (approvalFilter == 'Approved' && filteredApproved.isEmpty))
                const Center(child: Padding(padding: EdgeInsets.all(20.0), child: Text('No questions found'))),
              const SizedBox(height: 80),
            ],
          ),
        ),
      ],
    );
  }

  Widget buildQuestionCard(Map<String, dynamic> question, double titleSize) {
    bool isApproved = (question['approved'] ?? 0) == 1;
    final options = _parseOptions(question['options']);
    return Card(
      color: isApproved ? Colors.green.shade100 : Colors.red.shade100,
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        title: Text(
          question['question_text'] ?? question['question'] ?? '',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: titleSize),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Options:", style: TextStyle(fontWeight: FontWeight.bold)),
            Text("A) ${options['option_a'] ?? options['A'] ?? question['option_a'] ?? ''}"),
            Text("B) ${options['option_b'] ?? options['B'] ?? question['option_b'] ?? ''}"),
            Text("C) ${options['option_c'] ?? options['C'] ?? question['option_c'] ?? ''}"),
            Text("D) ${options['option_d'] ?? options['D'] ?? question['option_d'] ?? ''}"),
            const SizedBox(height: 4),
            Text("Answer: ${question['answer'] ?? question['correct_answer'] ?? ''}", style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
            Text("Source: ${question['source'] ?? ''}", style: const TextStyle(color: Colors.blue)),
          ],
        ),
        trailing: FutureBuilder<bool>(
          future: UserService.isSuperAdmin(),
          builder: (context, snapshot) {
            final isSuper = snapshot.data ?? false;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(icon: const Icon(Icons.check, color: Colors.green), onPressed: () => approveQuestion(question['id']), tooltip: 'Approve'),
                if (isSuper) IconButton(icon: const Icon(Icons.edit, color: Colors.blue), onPressed: () => updateQuestion(question), tooltip: 'Edit'),
                if (isSuper) IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => deleteQuestion(question['id']), tooltip: 'Delete'),
              ],
            );
          }
        ),
      ),
    );
  }
}
