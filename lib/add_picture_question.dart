import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart'; 
import 'package:file_picker/file_picker.dart'; 
import 'dart:io'; 
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:path/path.dart' as path;

class AddPictureQuestionPage extends StatefulWidget {
  const AddPictureQuestionPage({super.key});

  @override
  _AddPictureQuestionPageState createState() => _AddPictureQuestionPageState();
}

class _AddPictureQuestionPageState extends State<AddPictureQuestionPage> {
  final TextEditingController _questionController = TextEditingController();
  final TextEditingController _answerController = TextEditingController();
  final TextEditingController _sourceController = TextEditingController();
  final List<XFile?> _selectedImages = []; // For mobile
  final List<PlatformFile?> _selectedWebImages = []; // For web
  bool isLoading = false;
  String error = '';

  Future<void> selectImage() async {
    if (kIsWeb) {
      if (_selectedWebImages.length < 4) {
        FilePickerResult? result = await FilePicker.platform.pickFiles(
          type: FileType.image,
          allowMultiple: false,
        );
        if (result != null) {
          setState(() {
            _selectedWebImages.add(result.files.first);
          });
        }
      }
    } else {
      final ImagePicker picker = ImagePicker();
      if (_selectedImages.length < 4) {
        final XFile? image =
            await picker.pickImage(source: ImageSource.gallery);
        if (image != null) {
          setState(() {
            _selectedImages.add(image);
          });
        }
      }
    }
  }

  Future<void> submitPictureQuestion() async {
    setState(() {
      isLoading = true;
      error = '';
    });

    try {
      final supabase = Supabase.instance.client;
      final List<String> imageUrls = [];

      // Upload Mobile Images
      for (int i = 0; i < _selectedImages.length; i++) {
        if (_selectedImages[i] != null) {
          final file = File(_selectedImages[i]!.path);
          final fileName = '${DateTime.now().millisecondsSinceEpoch}_${path.basename(file.path)}';
          final pathStr = 'picture_questions/$fileName';
          
          await supabase.storage.from('question-images').upload(pathStr, file);
          final url = supabase.storage.from('question-images').getPublicUrl(pathStr);
          imageUrls.add(url);
        }
      }

      // Upload Web Images
      for (int i = 0; i < _selectedWebImages.length; i++) {
        if (_selectedWebImages[i] != null && _selectedWebImages[i]!.bytes != null) {
          final fileName = '${DateTime.now().millisecondsSinceEpoch}_${_selectedWebImages[i]!.name}';
          final pathStr = 'picture_questions/$fileName';
          
          await supabase.storage.from('question-images').uploadBinary(pathStr, _selectedWebImages[i]!.bytes!);
          final url = supabase.storage.from('question-images').getPublicUrl(pathStr);
          imageUrls.add(url);
        }
      }

      // Save to Database (Using specific image_path columns as per schema)
      await supabase.from('questions').insert({
        'question_text': _questionController.text.trim(),
        'question_type': 'picture',
        'answer': _answerController.text.trim(),
        'source': _sourceController.text.trim(),
        'approved': 0,
        'image_path_1': imageUrls.isNotEmpty ? imageUrls[0] : null,

        'image_path_2': imageUrls.length > 1 ? imageUrls[1] : null,
        'image_path_3': imageUrls.length > 2 ? imageUrls[2] : null,
        'image_path_4': imageUrls.length > 3 ? imageUrls[3] : null,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Picture question added successfully!')),
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
          'Add Picture Based Question',
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
                  buildTextField('Question', _questionController, screenWidth),
                  SizedBox(height: screenHeight * 0.015),
                  buildTextField('Answer', _answerController, screenWidth),
                  SizedBox(height: screenHeight * 0.015),
                  buildTextField('Source (Optional)', _sourceController, screenWidth),
                  SizedBox(height: screenHeight * 0.02),
                  buildImagePreview(screenHeight),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: (_selectedImages.length < 4 ||
                              _selectedWebImages.length < 4)
                          ? selectImage
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.deepPurple,
                        side: const BorderSide(color: Colors.deepPurple),
                        padding: EdgeInsets.symmetric(vertical: screenHeight * 0.015),
                      ),
                      child: Text(
                          'Select Image (${_selectedImages.length + _selectedWebImages.length}/4)',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  SizedBox(height: screenHeight * 0.02),
                  if (error.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(error, style: const TextStyle(color: Colors.red), softWrap: true),
                    ),
                  isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: submitPictureQuestion,
                            style: ElevatedButton.styleFrom(
                              padding: EdgeInsets.symmetric(vertical: screenHeight * 0.02),
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
        counterText: labelText == 'Question' ? null : '',
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

  Widget buildImagePreview(double screenHeight) {
    return Wrap(
      children: _selectedImages.map((image) {
        if (image != null && File(image.path).existsSync()) {
          return Padding(
            padding: const EdgeInsets.all(4.0),
            child: Image.file(
              File(image.path),
              height: screenHeight * 0.15,
              width: screenHeight * 0.15,
              fit: BoxFit.cover,
            ),
          );
        }
        return Container();
      }).toList()
        ..addAll(_selectedWebImages.map((image) {
          if (image != null) {
            return Padding(
              padding: const EdgeInsets.all(4.0),
              child: Image.memory(
                image.bytes!,
                height: screenHeight * 0.15,
                width: screenHeight * 0.15,
                fit: BoxFit.cover,
              ),
            );
          }
          return Container();
        }).toList()),
    );
  }
}
