import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AddStructuredQuestionPage extends StatefulWidget {
  const AddStructuredQuestionPage({super.key});

  @override
  _AddStructuredQuestionPageState createState() =>
      _AddStructuredQuestionPageState();
}

class _AddStructuredQuestionPageState extends State<AddStructuredQuestionPage> {
  final _formKey = GlobalKey<FormState>();

  String questionText = '';
  String answerText = '';
  String sourceText = '';

  // Function to send data to the PHP script
  Future<void> saveStructuredQuestion() async {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();

      try {
        final supabase = Supabase.instance.client;
        
        await supabase.from('questions').insert({
          'question_text': questionText.trim(),
          'question_type': 'structured',
          'answer': answerText.trim(),
          'source': sourceText.trim(),
          'options': {},
          'approved': 0,
        });


        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Structured Question Added Successfully')),
        );

        // Clear the form
        setState(() {
          questionText = '';
          answerText = '';
          sourceText = '';
        });
        
        if (mounted) Navigator.pop(context);

      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
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
          'Add Structured Question',
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
                      '4. The source is important for verifying the authenticity of the question.',
                      style: TextStyle(
                        fontSize: 14 * textScaleFactor,
                        fontWeight: FontWeight.w500,
                        height: 1.5,
                      ),
                      softWrap: true,
                    ),
                  ),
                  SizedBox(height: screenHeight * 0.02),
                  Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        buildTextFormField('Question Text', (value) {
                          if (value == null || value.isEmpty) return 'Please enter the question';
                          return null;
                        }, (value) => questionText = value!, screenWidth, maxLines: 3),
                        SizedBox(height: screenHeight * 0.015),
                        buildTextFormField('Answer', (value) {
                          if (value == null || value.isEmpty) return 'Please enter the answer';
                          return null;
                        }, (value) => answerText = value!, screenWidth),
                        SizedBox(height: screenHeight * 0.015),
                        buildTextFormField('Source', (value) {
                          if (value == null || value.isEmpty) return 'Please enter the source';
                          return null;
                        }, (value) => sourceText = value!, screenWidth),
                        SizedBox(height: screenHeight * 0.04),
                        Center(
                          child: SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: saveStructuredQuestion,
                              style: ElevatedButton.styleFrom(
                                padding: EdgeInsets.symmetric(vertical: screenHeight * 0.02),
                              ),
                              child: Text(
                                'Add Structured Question',
                                style: TextStyle(
                                  fontSize: 16 * textScaleFactor,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(height: screenHeight * 0.05),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget buildTextFormField(String labelText, String? Function(String?) validator,
      void Function(String?) onSaved, double screenWidth, {int maxLines = 1}) {
    return TextFormField(
      decoration: InputDecoration(
        labelText: labelText,
        labelStyle: const TextStyle(fontWeight: FontWeight.w500),
        counterText: labelText == 'Question Text' ? null : '',
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        contentPadding: EdgeInsets.symmetric(
          horizontal: screenWidth * 0.04,
          vertical: 12,
        ),
      ),
      validator: validator,
      onSaved: onSaved,
      maxLength: labelText == 'Question Text' ? 130 : null,
      maxLines: maxLines,
      minLines: 1,

    );
  }
}
