import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/user_service.dart';

class AllStructuredTab extends StatefulWidget {
  const AllStructuredTab({super.key});

  @override
  _AllStructuredTabState createState() => _AllStructuredTabState();
}

class _AllStructuredTabState extends State<AllStructuredTab> {
  final _supabase = Supabase.instance.client;
  List<dynamic> structuredQuestions = [];
  List<dynamic> filteredQuestions = [];
  String searchQuery = '';
  String approvalFilter = 'All'; // All, Approved, Unapproved

  @override
  void initState() {
    super.initState();
    fetchStructuredQuestions();
  }

  // Fetch structured questions from Supabase
  Future<void> fetchStructuredQuestions() async {
    try {
      final isSuper = await UserService.isSuperAdmin();
      var query = _supabase
          .from('questions')
          .select()
          .eq('question_type', 'structured');

      if (!isSuper) {
        query = query.or('approved.eq.0,approved.is.null');
      }

      final response = await query.order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          structuredQuestions = response as List<dynamic>;
          // Sort the questions locally if needed
          structuredQuestions.sort((a, b) {
            int approvedA = (a['approved'] ?? 0) is int ? a['approved'] : int.tryParse(a['approved'].toString()) ?? 0;
            int approvedB = (b['approved'] ?? 0) is int ? b['approved'] : int.tryParse(b['approved'].toString()) ?? 0;
            return approvedA.compareTo(approvedB);
          });
          _applyFilters();
        });
      }
        } catch (e) {
      if (mounted) {
        print('Error fetching Supabase structured questions: $e');
      }
    }
  }

  void _filterQuestions(String query) {
    searchQuery = query;
    _applyFilters();
  }

  void _applyFilters() {
    setState(() {
      final q = searchQuery.toLowerCase();
      filteredQuestions = structuredQuestions.where((item) {
        final text = (item['question_text'] ?? '').toString().toLowerCase();
        final source = (item['source'] ?? '').toString().toLowerCase();
        final matchesSearch = text.contains(q) || source.contains(q);

        final approvedVal = item['approved'] is int 
            ? item['approved'] 
            : int.tryParse(item['approved'].toString()) ?? 0;
        final isApproved = approvedVal == 1;

        bool matchesFilter = true;
        if (approvalFilter == 'Approved') matchesFilter = isApproved;
        else if (approvalFilter == 'Unapproved') matchesFilter = !isApproved;

        return matchesSearch && matchesFilter;
      }).toList();
    });
  }

  // Approve or unapprove the structured question in Supabase
  Future<void> updateApprovalStatus(dynamic id, int approved) async {
    try {
      await _supabase.from('questions').update({'approved': approved}).eq('id', id);
      fetchStructuredQuestions();
    } catch (e) {
      print('Error updating approval status: $e');
    }
  }

  // Delete the structured question from Supabase
  Future<void> deleteQuestion(dynamic id) async {
    try {
      await _supabase.from('questions').delete().eq('id', id);
      fetchStructuredQuestions();
    } catch (e) {
      print('Error deleting structured question: $e');
    }
  }

  // Show dialog to update a question
  void showUpdateDialog(Map<String, dynamic> question) {
    final TextEditingController questionController = TextEditingController(text: question['question_text'] ?? question['question'] ?? '');
    final TextEditingController answerController = TextEditingController(text: question['answer'] ?? question['correct_answer'] ?? '');
    final TextEditingController sourceController = TextEditingController(text: question['source'] ?? '');
    int approvalStatus = (question['approved'] ?? 0) is int ? (question['approved'] ?? 0) : int.tryParse(question['approved'].toString()) ?? 0;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Update Question'),
          content: SingleChildScrollView(
            child: Column(
              children: [
                TextField(controller: questionController, decoration: const InputDecoration(labelText: 'Question')),
                TextField(controller: answerController, decoration: const InputDecoration(labelText: 'Answer')),
                TextField(controller: sourceController, decoration: const InputDecoration(labelText: 'Source')),
                DropdownButtonFormField<int>(
                  initialValue: approvalStatus,
                  items: const [
                    DropdownMenuItem(value: 1, child: Text('Approved')),
                    DropdownMenuItem(value: 0, child: Text('Unapproved')),
                  ],
                  onChanged: (value) {
                    approvalStatus = value!;
                  },
                  decoration: const InputDecoration(labelText: 'Approval Status'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                await updateStructuredQuestion(question['id'] ?? question['question_id'], questionController.text, answerController.text, sourceController.text, approvalStatus);
                Navigator.pop(context);
              },
              child: const Text('Update'),
            ),
          ],
        );
      },
    );
  }

  // Update structured question in Supabase
  Future<void> updateStructuredQuestion(dynamic id, String questionText, String answer, String source, int approved) async {
    try {
      await _supabase.from('questions').update({
        'question_text': questionText,
        'answer': answer,
        'source': source,
        'approved': approved,
      }).eq('id', id);
      fetchStructuredQuestions();
    } catch (e) {
      print('Error updating Supabase structured question: $e');
    }
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
                  hintText: 'Search structured questions...',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.9),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
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
                            _applyFilters();
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
          child: filteredQuestions.isEmpty
              ? const Center(child: Text('No questions found'))
              : ListView.builder(
                  itemCount: filteredQuestions.length + 1,
                  itemBuilder: (context, index) {
                    if (index == filteredQuestions.length) {
                      return const SizedBox(height: 80);
                    }
                    final question = filteredQuestions[index];
                    int approvedValue = (question['approved'] ?? 0) is int ? question['approved'] : int.tryParse(question['approved'].toString()) ?? 0;
                    Color backgroundColor = approvedValue == 1 ? Colors.green.shade100 : Colors.red.shade100;

                    return buildQuestionCard(question, backgroundColor, titleSize);
                  },
                ),
        ),
      ],
    );
  }

  Widget buildQuestionCard(dynamic question, Color backgroundColor, double titleSize) {
    int approvedValue = (question['approved'] ?? 0) is int ? question['approved'] : int.tryParse(question['approved'].toString()) ?? 0;
    return Card(
      color: backgroundColor,
      margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
      child: ListTile(
        title: Text(question['question_text'] ?? question['question'] ?? 'No text', style: TextStyle(fontWeight: FontWeight.bold, fontSize: titleSize)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Answer: ${question['answer'] ?? question['correct_answer'] ?? ''}", style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
            Text("Source: ${question['source'] ?? ''}", style: const TextStyle(color: Colors.blue)),
            const SizedBox(height: 5),
            Row(
              children: [
                const Text("Status: "),
                DropdownButton<int>(
                  value: approvedValue,
                  items: const [
                    DropdownMenuItem<int>(value: 1, child: Text('Approved')),
                    DropdownMenuItem<int>(value: 0, child: Text('Unapproved')),
                  ],
                  onChanged: (value) {
                    if (value != null) updateApprovalStatus(question['id'] ?? question['question_id'], value);
                  },
                ),
              ],
            ),
          ],
        ),
        trailing: FutureBuilder<bool>(
          future: UserService.isSuperAdmin(),
          builder: (context, snapshot) {
            final isSuper = snapshot.data ?? false;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isSuper) IconButton(icon: const Icon(Icons.edit, color: Colors.blue), onPressed: () => showUpdateDialog(question), tooltip: 'Edit'),
                if (isSuper) IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => deleteQuestion(question['id'] ?? question['question_id']), tooltip: 'Delete'),
              ],
            );
          }
        ),
      ),
    );
  }
}
