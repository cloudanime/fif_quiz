import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/user_service.dart';

class AllPictureTab extends StatefulWidget {
  const AllPictureTab({super.key});

  @override
  _AllPictureTabState createState() => _AllPictureTabState();
}

class _AllPictureTabState extends State<AllPictureTab> {
  final _supabase = Supabase.instance.client;
  List<dynamic> pictureQuestions = [];
  List<dynamic> filteredQuestions = [];
  String searchQuery = '';
  String approvalFilter = 'All'; // All, Approved, Unapproved

  @override
  void initState() {
    super.initState();
    fetchAllPictureQuestions();
  }

  // Fetch picture questions from Supabase
  Future<void> fetchAllPictureQuestions() async {
    try {
      final isSuper = await UserService.isSuperAdmin();
      var query = _supabase
          .from('questions')
          .select()
          .eq('question_type', 'picture');

      if (!isSuper) {
        query = query.or('approved.eq.0,approved.is.null');
      }

      final response = await query.order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          pictureQuestions = response as List<dynamic>;
          _applyFilters();
        });
      }
        } catch (e) {
      if (mounted) {
        print('Error fetching Supabase picture questions: $e');
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
      filteredQuestions = pictureQuestions.where((item) {
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

  // Approve or unapprove the picture question in Supabase
  Future<void> updateApprovalStatus(dynamic id, int approved) async {
    try {
      await _supabase.from('questions').update({'approved': approved}).eq('id', id);
      fetchAllPictureQuestions();
    } catch (e) {
      print('Error updating approval status: $e');
    }
  }

  // Delete the picture question from Supabase
  Future<void> deleteQuestion(dynamic id) async {
    try {
      await _supabase.from('questions').delete().eq('id', id);
      fetchAllPictureQuestions();
    } catch (e) {
      print('Error deleting picture question: $e');
    }
  }

  // Show edit dialog for updating all fields
  void showEditDialog(Map<String, dynamic> question) {
    final TextEditingController questionController = TextEditingController(text: question['question_text'] ?? question['question'] ?? '');
    final TextEditingController answerController = TextEditingController(text: question['answer'] ?? '');
    final TextEditingController sourceController = TextEditingController(text: question['source'] ?? '');
    int approved = (question['approved'] ?? 0) is int ? (question['approved'] ?? 0) : int.tryParse(question['approved'].toString()) ?? 0;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Edit Question'),
          content: SingleChildScrollView(
            child: Column(
              children: [
                TextField(controller: questionController, decoration: const InputDecoration(labelText: 'Question')),
                TextField(controller: answerController, decoration: const InputDecoration(labelText: 'Answer')),
                TextField(controller: sourceController, decoration: const InputDecoration(labelText: 'Source')),
                DropdownButtonFormField<int>(
                  initialValue: approved,
                  items: const [
                    DropdownMenuItem<int>(value: 1, child: Text('Approved')),
                    DropdownMenuItem<int>(value: 0, child: Text('Unapproved')),
                  ],
                  onChanged: (value) {
                    approved = value!;
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                updateQuestion(question['id'], questionController.text, answerController.text, sourceController.text, approved);
                Navigator.of(context).pop();
              },
              child: const Text('Update'),
            ),
          ],
        );
      },
    );
  }

  // Update the question in Supabase
  Future<void> updateQuestion(dynamic id, String questionText, String answer, String source, int approved) async {
    try {
      await _supabase.from('questions').update({
        'question_text': questionText,
        'answer': answer,
        'source': source,
        'approved': approved,
      }).eq('id', id);
      fetchAllPictureQuestions();
    } catch (e) {
      print('Error updating Supabase picture question: $e');
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
                  hintText: 'Search picture questions...',
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
          child: ListView.builder(
            itemCount: filteredQuestions.length + 1,
            itemBuilder: (context, index) {
              if (index == filteredQuestions.length) {
                return const SizedBox(height: 80);
              }
              final question = filteredQuestions[index];
              final approvedValue = (question['approved'] ?? 0) is int ? question['approved'] : int.tryParse(question['approved'].toString()) ?? 0;
              
              List<String> images = [];
              for (int i = 1; i <= 4; i++) {
                final path = question['image_path_$i'];
                if (path != null && path.toString().isNotEmpty) images.add(path.toString());
              }

              return buildQuestionCard(question, approvedValue, images, titleSize);
            },
          ),
        ),
      ],
    );
  }

  Widget buildQuestionCard(dynamic question, int approvedValue, List<String> images, double titleSize) {
    return Card(
      color: (approvedValue == 1) ? Colors.green.shade100 : Colors.red.shade100,
      margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
      child: ListTile(
        title: Text(question['question_text'] ?? question['question'] ?? 'No text', style: TextStyle(fontWeight: FontWeight.bold, fontSize: titleSize)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (images.isNotEmpty)
              SizedBox(
                height: 70,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: images.length,
                  itemBuilder: (ctx, i) => Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: Image.network(images[i], width: 60, height: 60, fit: BoxFit.cover, errorBuilder: (c, e, s) => const Icon(Icons.broken_image)),
                  ),
                ),
              ),
            Text('Answer: ${question['answer'] ?? 'No answer available'}', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
            Text('Source: ${question['source'] ?? ''}', style: const TextStyle(color: Colors.blue)),
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
                    if (value != null) updateApprovalStatus(question['id'], value);
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
                if (isSuper) IconButton(icon: const Icon(Icons.edit, color: Colors.blue), onPressed: () => showEditDialog(question), tooltip: 'Edit'),
                if (isSuper) IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => deleteQuestion(question['id']), tooltip: 'Delete'),
              ],
            );
          }
        ),
      ),
    );
  }
}
