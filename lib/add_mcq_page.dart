import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AddMcqPage extends StatefulWidget {
  const AddMcqPage({super.key});

  @override
  _AddMcqPageState createState() => _AddMcqPageState();
}

class _AddMcqPageState extends State<AddMcqPage> {
  final TextEditingController _questionController = TextEditingController();
  final TextEditingController _optionAController = TextEditingController();
  final TextEditingController _optionBController = TextEditingController();
  final TextEditingController _optionCController = TextEditingController();
  final TextEditingController _optionDController = TextEditingController();
  final TextEditingController _correctAnswerController =
      TextEditingController();
  final TextEditingController _sourceController = TextEditingController();

  bool isLoading = false;
  String error = '';

  Future<void> submitQuestion() async {
    setState(() {
      isLoading = true;
      error = '';
    });

    if (_questionController.text.isEmpty ||
        _optionAController.text.isEmpty ||
        _optionBController.text.isEmpty ||
        _optionCController.text.isEmpty ||
        _optionDController.text.isEmpty ||
        _correctAnswerController.text.isEmpty ||
        _sourceController.text.isEmpty) {
      setState(() {
        error = 'All fields are required';
        isLoading = false;
      });
      return;
    }

    final correctAnswer = _correctAnswerController.text.trim().toUpperCase();
    if (!['A', 'B', 'C', 'D'].contains(correctAnswer)) {
      setState(() {
        error = 'Correct Answer must be A, B, C, or D';
        isLoading = false;
      });
      return;
    }

    try {
      final supabase = Supabase.instance.client;
      await supabase.from('questions').insert({
        'question_text': _questionController.text.trim(),
        'question_type': 'multiple_choice',
        'answer': correctAnswer,
        'source': _sourceController.text.trim(),
        'options': {
          'option_a': _optionAController.text.trim(),
          'option_b': _optionBController.text.trim(),
          'option_c': _optionCController.text.trim(),
          'option_d': _optionDController.text.trim(),
        },
        'approved': 0,
      });


      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Question added successfully!')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      setState(() {
        error = 'Error submitting question: $e';
      });
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    double screenHeight = MediaQuery.of(context).size.height;
    double screenWidth = MediaQuery.of(context).size.width;
    double textScaleFactor = MediaQuery.of(context).textScaleFactor;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          'Add MCQ',
          style: TextStyle(
            fontSize: (screenHeight * 0.02).clamp(14.0, 22.0),
            fontWeight: FontWeight.bold,
          ),
          overflow: TextOverflow.visible,
          softWrap: true,
        ),
        centerTitle: true,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.all(screenWidth * 0.04),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: EdgeInsets.all(screenWidth * 0.03),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Text(
                      'Instructions:\n\n'
                      '1. Use this page to add questions to the Legacy Quiz.\n'
                      '2. Your question must be related to the church (Forward in Faith Ministries International).\n'
                      '3. Type in your question and answers, indicating the correct answer to the question and providing a source, if book give title and page number.\n'
                      '4. NOTE: Your question will not automatically appear in the quiz; it will be verified and approved before it is included.',
                      style: TextStyle(
                        fontSize: 14 * textScaleFactor,
                        fontWeight: FontWeight.w500,
                        height: 1.5,
                      ),
                      softWrap: true,
                    ),
                  ),
                  SizedBox(height: screenHeight * 0.02),
                  buildTextField('Question', _questionController, screenWidth),
                  SizedBox(height: screenHeight * 0.015),
                  buildTextField('Option A', _optionAController, screenWidth),
                  SizedBox(height: screenHeight * 0.015),
                  buildTextField('Option B', _optionBController, screenWidth),
                  SizedBox(height: screenHeight * 0.015),
                  buildTextField('Option C', _optionCController, screenWidth),
                  SizedBox(height: screenHeight * 0.015),
                  buildTextField('Option D', _optionDController, screenWidth),
                  SizedBox(height: screenHeight * 0.015),
                  buildTextField('Correct Answer (A, B, C, or D)',
                      _correctAnswerController, screenWidth),
                  SizedBox(height: screenHeight * 0.015),
                  buildTextField('Source', _sourceController, screenWidth),
                  if (error.isNotEmpty)
                    Padding(
                      padding: EdgeInsets.only(top: screenHeight * 0.02),
                      child: Text(
                        error,
                        style: const TextStyle(color: Colors.red),
                        softWrap: true,
                      ),
                    ),
                  SizedBox(height: screenHeight * 0.03),
                  isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: submitQuestion,
                            style: ElevatedButton.styleFrom(
                              padding: EdgeInsets.symmetric(
                                vertical: screenHeight * 0.02,
                              ),
                            ),
                            child: Text(
                              'Submit Question',
                              style: TextStyle(
                                fontSize: 16 * textScaleFactor,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                  // Added extra space after the button
                  SizedBox(height: screenHeight * 0.05),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget buildTextField(
      String labelText, TextEditingController controller, double screenWidth) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: labelText,
        labelStyle: const TextStyle(fontWeight: FontWeight.w500),
        counterText: labelText == 'Question' ? null : '', // Show counter only for question
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        contentPadding: EdgeInsets.symmetric(
          horizontal: screenWidth * 0.04,
          vertical: 12,
        ),
      ),
      maxLength: labelText == 'Question' ? 130 : null,
      maxLines: labelText == 'Question' ? 3 : 1,
      minLines: 1,

    );
  }
}