import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class UnapprovedMCQTab extends StatefulWidget {
  const UnapprovedMCQTab({super.key});

  @override
  _UnapprovedMCQTabState createState() => _UnapprovedMCQTabState();
}

class _UnapprovedMCQTabState extends State<UnapprovedMCQTab> {
  List<dynamic> mcqQuestions = [];

  @override
  void initState() {
    super.initState();
    fetchUnapprovedMCQ();
  }

  Future<void> fetchUnapprovedMCQ() async {
    final response = await http
        .get(Uri.parse('https://your-api-endpoint.com/get_unapproved_mcq.php'));

    if (response.statusCode == 200) {
      setState(() {
        mcqQuestions = json.decode(response.body);
      });
    } else {
      throw Exception('Failed to load unapproved MCQ questions');
    }
  }

  void approveQuestion(int id) {
    // Implement the logic to approve a question, e.g., make an API call
  }

  void deleteQuestion(int id) {
    // Implement the logic to delete a question, e.g., make an API call
  }

  void updateQuestion(int id) {
    // Implement the logic to update a question, e.g., navigate to an edit page
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: mcqQuestions.length,
      itemBuilder: (context, index) {
        final question = mcqQuestions[index];
        return ListTile(
          title: Text(question['question_text']),
          subtitle: Text('Options: ${question['options']}'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.check),
                onPressed: () => approveQuestion(question['id']),
                tooltip: 'Approve',
              ),
              IconButton(
                icon: const Icon(Icons.edit),
                onPressed: () => updateQuestion(question['id']),
                tooltip: 'Edit',
              ),
              IconButton(
                icon: const Icon(Icons.delete),
                onPressed: () => deleteQuestion(question['id']),
                tooltip: 'Delete',
              ),
            ],
          ),
        );
      },
    );
  }
}
