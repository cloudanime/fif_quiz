import 'package:church_quiz/offline/local_db_service_web.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/supabase_models.dart';
import 'local_db_service_mobile.dart';
import 'package:sqflite/sqflite.dart';
import 'local_db_service.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:convert';
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:uuid/uuid.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:flutter/services.dart' show rootBundle;

import 'package:shared_preferences/shared_preferences.dart';

class SuperUserDashboard extends StatefulWidget {
  const SuperUserDashboard({super.key});

  @override
  State<SuperUserDashboard> createState() => _SuperUserDashboardState();
}

class _SuperUserDashboardState extends State<SuperUserDashboard> {
  bool _syncEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadSyncSetting();
  }

  Future<void> _loadSyncSetting() async {
    try {
      final supabase = Supabase.instance.client;
      final settings = await supabase
          .from('games')
          .select('status')
          .eq('id', '00000000-0000-0000-0000-000000000000')
          .maybeSingle();
          
      if (mounted) {
        setState(() {
          _syncEnabled = settings == null || settings['status'] != 'sync_disabled';
        });
      }
    } catch (e) {
      debugPrint('Failed to load global sync setting: $e');
    }
  }

  Future<void> _toggleSyncSetting(bool value) async {
    setState(() {
      _syncEnabled = value;
    });
    
    try {
      final supabase = Supabase.instance.client;
      final status = value ? 'sync_enabled' : 'sync_disabled';
      
      final existing = await supabase
          .from('games')
          .select('id')
          .eq('id', '00000000-0000-0000-0000-000000000000')
          .maybeSingle();
          
      if (existing == null) {
        await supabase.from('games').insert({
          'id': '00000000-0000-0000-0000-000000000000',
          'mode': 'global_settings',
          'status': status,
        });
      } else {
        await supabase
            .from('games')
            .update({'status': status})
            .eq('id', '00000000-0000-0000-0000-000000000000');
      }
    } catch (e) {
      debugPrint('Failed to update global sync setting: $e');
    }
  }
      Future<void> fixQuestionTypesInDB() async {
        setState(() { _isLoading = true; _status = 'Fixing question types...'; });
        int updated = 0;
        if (kIsWeb) {
          final questions = await WebDatabaseHelper.getAll('questions');
          for (final q in questions) {
            String? type = q['question_type']?.toString().toLowerCase();
            // Guess type if not set or not valid
            if (type == null || !(type == 'mcq' || type == 'picture' || type == 'structured')) {
              // Heuristic: if options field is present and not empty, it's MCQ
              if ((q['options'] != null && q['options'].toString().trim().isNotEmpty)) {
                type = 'mcq';
              } else if (q['question_text']?.toString().toLowerCase().contains('image') == true || q['question_text']?.toString().toLowerCase().contains('picture') == true) {
                type = 'picture';
              } else {
                type = 'structured';
              }
            }
            q['question_type'] = type;
            await WebDatabaseHelper.insert('questions', q['id'], q);
            updated++;
          }
        } else {
          final db = await LocalDbService.database;
          final questions = await db.query('questions');
          for (final q in questions) {
            String? type = q['question_type']?.toString().toLowerCase().trim();
            // Guess type if not set or not valid
            if (type == null || type.isEmpty || !(type == 'mcq' || type == 'picture' || type == 'structured')) {
              // Heuristic: if options field is present and not empty, it's MCQ
              if ((q['options'] != null && q['options'].toString().trim().isNotEmpty && q['options'].toString().contains('{'))) {
                type = 'mcq';
              } else if (q['question_text']?.toString().toLowerCase().contains('image') == true || q['question_text']?.toString().toLowerCase().contains('picture') == true) {
                type = 'picture';
              } else {
                type = 'structured';
              }
            }
            
            // Create a modifiable copy since sqflite maps are read-only
            final modifiableQ = Map<String, dynamic>.from(q);
            modifiableQ['question_type'] = type;
            modifiableQ['approved'] = 1; // Mark as approved so they show up in grid
            
            await db.update('questions', modifiableQ, where: 'id = ?', whereArgs: [q['id']]);
            updated++;
          }
        }
        setState(() { _isLoading = false; _status = 'Fixed question_type for $updated questions.'; });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Fixed question_type for $updated questions.'), backgroundColor: Colors.green),
          );
        }
      }
    Future<void> _showAllQuestionsDialog() async {
      List<Map<String, dynamic>> allQuestions = [];
      if (kIsWeb) {
        allQuestions = await WebDatabaseHelper.getAll('questions');
      } else {
        final db = await LocalDbService.database;
        allQuestions = await db.query('questions');
      }
      if (!mounted) return;

      String filter = 'All';

      showDialog(
        context: context,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              final filteredQuestions = allQuestions.where((q) {
                final approvedVal = (q['approved'] ?? 0) is int 
                    ? q['approved'] 
                    : int.tryParse(q['approved'].toString()) ?? 0;
                final approved = approvedVal == 1;
                
                if (filter == 'Approved') return approved;
                if (filter == 'Unapproved') return !approved;
                return true;
              }).toList();

              return AlertDialog(
                title: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.storage, color: Colors.purple),
                        const SizedBox(width: 10),
                        const Text('All Questions in DB'),
                        const Spacer(),
                        Text('${filteredQuestions.length} total', style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: ['All', 'Approved', 'Unapproved'].map((f) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: ChoiceChip(
                              label: Text(f, style: const TextStyle(fontSize: 12)),
                              selected: filter == f,
                              onSelected: (val) {
                                setDialogState(() {
                                  if (val) filter = f;
                                  else if (filter == f) filter = 'All';
                                });
                              },
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
                content: SizedBox(
                  width: MediaQuery.of(context).size.width * 0.9,
                  height: MediaQuery.of(context).size.height * 0.7,
                  child: filteredQuestions.isEmpty
                      ? const Center(child: Text('No questions found matching filter.'))
                      : ListView.separated(
                          itemCount: filteredQuestions.length,
                          separatorBuilder: (context, index) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final q = filteredQuestions[index];
                            final type = q['question_type']?.toString() ?? '-';
                            final isApproved = (q['approved'] ?? 0) == 1;
                            Color typeColor = Colors.grey;
                            if (type == 'mcq') typeColor = Colors.green;
                            else if (type == 'picture') typeColor = Colors.red;
                            else if (type == 'structured') typeColor = Colors.blue;

                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: typeColor.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(color: typeColor),
                                        ),
                                        child: Text(type.toUpperCase(), style: TextStyle(fontSize: 10, color: typeColor, fontWeight: FontWeight.bold)),
                                      ),
                                      const SizedBox(width: 8),
                                      if (isApproved)
                                        const Icon(Icons.verified, color: Colors.green, size: 14),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          q['question_text']?.toString() ?? 'No text',
                                          style: const TextStyle(fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'ID: ${q['id']}\nGame ID: ${q['game_id'] ?? '-'}\nStatus: ${isApproved ? 'Approved' : 'Unapproved'}',
                                    style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                                  ),
                                  if (q['options'] != null && q['options'].toString().isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4.0),
                                      child: Text(
                                        'Options: ${q['options']}',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(fontSize: 9, color: Colors.blue.shade800),
                                      ),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                ],
              );
            },
          );
        },
      );
    }

  Future<void> _analyzeBrokenMCQs() async {
    setState(() {
      _isLoading = true;
      _status = 'Analyzing databases for broken MCQs...';
    });
    
    List<dynamic> allBroken = [];
    
    try {
      // 1. Check Supabase
      final supabase = Supabase.instance.client;
      final List<dynamic> cloudQuestions = await supabase
          .from('questions')
          .select()
          .or('question_type.eq.mcq,question_type.eq.multiple_choice');
          
      allBroken.addAll(_findBrokenInList(cloudQuestions, 'Cloud'));
      
      // 2. Check Local DB
      List<Map<String, dynamic>> localQuestions = [];
      if (kIsWeb) {
        localQuestions = await WebDatabaseHelper.getAll('questions');
      } else {
        final db = await LocalDbService.database;
        localQuestions = await db.query('questions', 
          where: 'question_type = ? OR question_type = ?', 
          whereArgs: ['mcq', 'multiple_choice']
        );
      }
      allBroken.addAll(_findBrokenInList(localQuestions, 'Local'));
      
      // De-duplicate by ID, merging source information
      final Map<String, dynamic> uniqueBroken = {};
      for (var q in allBroken) {
        final id = q['id']?.toString();
        if (id == null) continue;
        
        final String currentSource = (q['_source'] ?? 'Unknown').toString();
        
        if (uniqueBroken.containsKey(id)) {
          final existing = uniqueBroken[id];
          final String existingSource = (existing['_source'] ?? '').toString();
          
          if (!existingSource.contains(currentSource)) {
            existing['_source'] = existingSource.isEmpty 
                ? currentSource 
                : '$existingSource & $currentSource';
          }
        } else {
          uniqueBroken[id] = q;
        }
      }
      
      final finalBroken = uniqueBroken.values.toList();
      
      setState(() {
        _isLoading = false;
        _status = 'Analysis complete: Found ${finalBroken.length} issues.';
      });
      
      if (mounted) {
        _showBrokenMCQsDialog(finalBroken);
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _status = 'Analysis error: $e';
      });
      debugPrint('Analysis error: $e');
    }
  }

  List<dynamic> _findBrokenInList(List<dynamic> questions, String source) {
    return questions.where((q) {
      final String type = (q['question_type'] ?? '').toString().toLowerCase();
      final bool isMcq = type == 'mcq' || type == 'multiple_choice';
      
      dynamic options = q['options'];
      bool isBroken = false;
      
      // All questions MUST have an answer
      final String? answer = q['answer']?.toString().trim();
      if (answer == null || answer.isEmpty) {
        isBroken = true;
      } 
      // Only MCQs MUST have options
      else if (isMcq) {
        if (options == null) {
          isBroken = true;
        } else if (options is String) {
          final trimmed = options.trim();
          if (trimmed.isEmpty || trimmed == '{}' || trimmed == '[]') {
            isBroken = true;
          } else {
            try {
              final decoded = jsonDecode(trimmed);
              if (decoded is Map) {
                final hasContent = decoded.values.any((v) => v != null && v.toString().trim().isNotEmpty);
                if (!hasContent) isBroken = true;
              } else if (decoded is List) {
                if (decoded.isEmpty) isBroken = true;
              }
            } catch (e) {}
          }
        } else if (options is Map) {
          final hasContent = options.values.any((v) => v != null && v.toString().trim().isNotEmpty);
          if (!hasContent) isBroken = true;
        } else if (options is List) {
          if (options.isEmpty) isBroken = true;
        }
      }
      
      if (isBroken) {
        if (q is Map) {
          final modifiable = Map<String, dynamic>.from(q);
          modifiable['_source'] = source;
          return true;
        }
      }
      return false;
    }).toList();
  }

  Future<void> _showQuestionCRUDDialog(Map<String, dynamic> question, String source) async {
    final String type = (question['question_type'] ?? '').toString().toLowerCase();
    final bool isMcq = type == 'mcq' || type == 'multiple_choice';

    final TextEditingController questionController = TextEditingController(text: question['question_text'] ?? '');
    final dynamic optionsData = question['options'];
    Map<String, dynamic> options = {};
    if (optionsData is Map) options = Map<String, dynamic>.from(optionsData);
    else if (optionsData is String && optionsData.isNotEmpty) {
      try { options = Map<String, dynamic>.from(jsonDecode(optionsData)); } catch (_) {}
    }

    final TextEditingController optionA = TextEditingController(text: options['option_a'] ?? options['A'] ?? '');
    final TextEditingController optionB = TextEditingController(text: options['option_b'] ?? options['B'] ?? '');
    final TextEditingController optionC = TextEditingController(text: options['option_c'] ?? options['C'] ?? '');
    final TextEditingController optionD = TextEditingController(text: options['option_d'] ?? options['D'] ?? '');
    final TextEditingController answer = TextEditingController(text: question['answer'] ?? '');
    final TextEditingController sourceController = TextEditingController(text: question['source'] ?? '');
    bool isApproved = (question['approved'] ?? 0) == 1;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Edit ${isMcq ? 'MCQ' : 'Question'} (${source})'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: questionController, 
                  decoration: const InputDecoration(labelText: 'Question Text'),
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                ),
                if (isMcq) ...[
                  TextField(controller: optionA, decoration: const InputDecoration(labelText: 'Option A')),
                  TextField(controller: optionB, decoration: const InputDecoration(labelText: 'Option B')),
                  TextField(controller: optionC, decoration: const InputDecoration(labelText: 'Option C')),
                  TextField(controller: optionD, decoration: const InputDecoration(labelText: 'Option D')),
                ],
                TextField(
                  controller: answer, 
                  decoration: InputDecoration(labelText: isMcq ? 'Answer (A, B, C, or D)' : 'Answer Text'),
                  maxLines: isMcq ? 1 : null,
                ),
                TextField(controller: sourceController, decoration: const InputDecoration(labelText: 'Source')),
                SwitchListTile(
                  title: const Text('Approved'),
                  value: isApproved,
                  onChanged: (val) {
                    setDialogState(() => isApproved = val);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Confirm Delete'),
                    content: const Text('Are you sure you want to delete ONLY this question? This action cannot be undone.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                      TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
                    ],
                  ),
                );
                if (confirm == true) {
                  try {
                    final id = question['id'];
                    if (source == 'Cloud') {
                      await Supabase.instance.client.from('questions').delete().eq('id', id);
                    } else {
                      if (kIsWeb) {
                        await WebDatabaseHelper.delete('questions', id);
                      } else {
                        final db = await LocalDbService.database;
                        await db.delete('questions', where: 'id = ?', whereArgs: [id]);
                      }
                    }
                    Navigator.pop(context); // Close edit dialog
                    _analyzeBrokenMCQs(); // Refresh analysis
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
                  }
                }
              },
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                try {
                  final id = question['id'];
                  final updatedOptions = {
                    'option_a': optionA.text,
                    'option_b': optionB.text,
                    'option_c': optionC.text,
                    'option_d': optionD.text,
                  };
                  final updateData = {
                    'question_text': questionController.text,
                    'options': kIsWeb ? updatedOptions : jsonEncode(updatedOptions),
                    'answer': answer.text,
                    'source': sourceController.text,
                    'question_type': 'mcq', // Normalize type
                    'approved': isApproved ? 1 : 0,
                  };

                  if (source == 'Cloud') {
                    await Supabase.instance.client.from('questions').update(updateData).eq('id', id);
                  } else {
                    if (kIsWeb) {
                      await WebDatabaseHelper.insert('questions', id, updateData);
                    } else {
                      final db = await LocalDbService.database;
                      await db.update('questions', updateData, where: 'id = ?', whereArgs: [id]);
                    }
                  }
                  Navigator.pop(context);
                  _analyzeBrokenMCQs(); // Refresh
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Update failed: $e')));
                }
              },
              child: const Text('Save Changes'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showBrokenMCQsDialog(List<dynamic> broken) async {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.orange),
              const SizedBox(width: 10),
              const Text('Broken MCQs (No Options)'),
              const Spacer(),
              Text('${broken.length} found', style: const TextStyle(fontSize: 12)),
            ],
          ),
          content: SizedBox(
            width: MediaQuery.of(context).size.width * 0.9,
            height: MediaQuery.of(context).size.height * 0.6,
            child: broken.isEmpty
                ? const Center(child: Text('All MCQs have options! Great job.'))
                : ListView.separated(
                    itemCount: broken.length,
                    separatorBuilder: (context, index) => const Divider(),
                    itemBuilder: (context, index) {
                      final q = broken[index];
                      return ListTile(
                        title: Text(q['question_text'] ?? 'No Text'),
                        subtitle: Text('ID: ${q['id']}\nSource: ${q['_source'] ?? 'Unknown'}\nCreated: ${q['created_at']}'),
                        isThreeLine: true,
                        trailing: const Icon(Icons.edit, color: Colors.blue),
                        onTap: () {
                          Navigator.pop(context); // Close broken list
                          _showQuestionCRUDDialog(q, q['_source'] ?? 'Cloud');
                        },
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showDataHealthReport() async {
    setState(() {
      _isLoading = true;
      _status = 'Performing data health check...';
    });

    try {
      List<Map<String, dynamic>> allQuestions = [];
      if (kIsWeb) {
        allQuestions = await WebDatabaseHelper.getAll('questions');
      } else {
        final db = await LocalDbService.database;
        allQuestions = await db.query('questions');
      }

      final List<Map<String, dynamic>> missingAnswer = [];
      final List<Map<String, dynamic>> missingOptionsMCQ = [];
      final List<Map<String, dynamic>> invalidType = [];
      final List<Map<String, dynamic>> unapproved = [];

      for (var q in allQuestions) {
        final String type = q['question_type']?.toString().toLowerCase() ?? '';
        final String answer = q['answer']?.toString().trim() ?? '';
        final dynamic optionsData = q['options'];
        final int approved = int.tryParse(q['approved']?.toString() ?? '0') ?? 0;

        if (approved != 1) {
          unapproved.add(q);
        }

        if (answer.isEmpty) {
          missingAnswer.add(q);
        }

        if (type == 'mcq' || type == 'multiple_choice') {
          bool hasOptions = false;
          if (optionsData != null && optionsData.toString().isNotEmpty && optionsData.toString() != '{}') {
            try {
              final decoded = (optionsData is String) ? jsonDecode(optionsData) : optionsData;
              if (decoded is Map) {
                hasOptions = decoded.values.any((v) => v != null && v.toString().trim().isNotEmpty);
              } else if (decoded is List) {
                hasOptions = decoded.isNotEmpty;
              }
            } catch (_) {}
          }
          if (!hasOptions) {
            missingOptionsMCQ.add(q);
          }
        }

        if (type != 'mcq' && type != 'multiple_choice' && type != 'picture' && type != 'image' && type != 'structured') {
          invalidType.add(q);
        }
      }

      setState(() {
        _isLoading = false;
        _status = 'Health check complete.';
      });

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.health_and_safety, color: Colors.blue),
                SizedBox(width: 10),
                Text('Data Health Report'),
              ],
            ),
            content: SizedBox(
              width: MediaQuery.of(context).size.width * 0.9,
              height: MediaQuery.of(context).size.height * 0.7,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _healthSection('Unapproved Questions', unapproved, Colors.orange, 'These questions are ignored by the grid.'),
                    _healthSection('Missing Correct Answer', missingAnswer, Colors.red, 'These questions will be skipped.'),
                    _healthSection('MCQs Missing Options', missingOptionsMCQ, Colors.red, 'MCQs must have options to be valid.'),
                    _healthSection('Invalid Question Type', invalidType, Colors.purple, 'Should be mcq, picture, or structured.'),
                    if (unapproved.isEmpty && missingAnswer.isEmpty && missingOptionsMCQ.isEmpty && invalidType.isEmpty)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(20.0),
                          child: Text('✅ Your data looks healthy!', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          );
        },
      );
    } catch (e) {
      setState(() {
        _isLoading = false;
        _status = 'Health check error: $e';
      });
    }
  }

  Widget _healthSection(String title, List<Map<String, dynamic>> items, Color color, String subtitle) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('$title (${items.length})', style: TextStyle(fontWeight: FontWeight.bold, color: color)),
          subtitle: Text(subtitle, style: const TextStyle(fontSize: 11)),
        ),
        Container(
          height: 150,
          decoration: BoxDecoration(
            border: Border.all(color: color.withOpacity(0.3)),
            borderRadius: BorderRadius.circular(4),
          ),
          child: ListView.separated(
            itemCount: items.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final q = items[index];
              return ListTile(
                dense: true,
                title: Text(q['question_text'] ?? 'No text', maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text('ID: ${q['id']}'),
                trailing: const Icon(Icons.chevron_right, size: 14),
                onTap: () {
                  _showQuestionCRUDDialog(q, 'Local');
                },
              );
            },
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Future<void> _showUnconsideredQuestionsReport() async {
    setState(() {
      _isLoading = true;
      _status = 'Calculating unconsidered questions...';
    });

    try {
      List<Map<String, dynamic>> allQuestions = [];
      if (kIsWeb) {
        allQuestions = await WebDatabaseHelper.getAll('questions');
      } else {
        final db = await LocalDbService.database;
        allQuestions = await db.query('questions');
      }

      // Filter for approved questions only, as unapproved are already hidden
      final approvedQuestions = allQuestions.where((q) => (q['approved'] ?? 0) == 1).toList();

      final mcqQuestions = approvedQuestions.where((q) {
        final type = q['question_type']?.toString().toLowerCase() ?? '';
        return type == 'mcq' || type == 'multiple_choice';
      }).toList();

      final pictureQuestions = approvedQuestions.where((q) {
        final type = q['question_type']?.toString().toLowerCase() ?? '';
        return type == 'picture' || type == 'image';
      }).toList();

      final structuredQuestions = approvedQuestions.where((q) {
        final type = q['question_type']?.toString().toLowerCase() ?? '';
        return type == 'structured';
      }).toList();

      // Find overflows
      final unconsideredMCQ = mcqQuestions.length > 70 ? mcqQuestions.sublist(70) : [];
      final unconsideredPicture = pictureQuestions.length > 10 ? pictureQuestions.sublist(10) : [];
      final unconsideredStructured = structuredQuestions.length > 20 ? structuredQuestions.sublist(20) : [];

      final allUnconsidered = [...unconsideredMCQ, ...unconsideredPicture, ...unconsideredStructured];

      setState(() {
        _isLoading = false;
        _status = 'Report generated.';
      });

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.visibility_off, color: Colors.red),
                const SizedBox(width: 10),
                const Text('Unconsidered Questions'),
                const Spacer(),
                Text('${allUnconsidered.length} total', style: const TextStyle(fontSize: 12)),
              ],
            ),
            content: SizedBox(
              width: MediaQuery.of(context).size.width * 0.9,
              height: MediaQuery.of(context).size.height * 0.7,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'These questions are in the DB but exceed the 100-slot grid capacity:',
                          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
                        ),
                        const SizedBox(height: 8),
                        Text('• MCQ Overflow: ${unconsideredMCQ.length} (Max 70 allowed)', style: const TextStyle(fontSize: 12)),
                        Text('• Picture Overflow: ${unconsideredPicture.length} (Max 10 allowed)', style: const TextStyle(fontSize: 12)),
                        Text('• Structured Overflow: ${unconsideredStructured.length} (Max 20 allowed)', style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Detailed List:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const Divider(),
                  Expanded(
                    child: allUnconsidered.isEmpty
                        ? const Center(child: Text('All approved questions fit in the grid!'))
                        : ListView.separated(
                            itemCount: allUnconsidered.length,
                            separatorBuilder: (context, index) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final q = allUnconsidered[index];
                              final type = q['question_type']?.toString() ?? '-';
                              Color typeColor = Colors.grey;
                              if (type == 'mcq') typeColor = Colors.green;
                              else if (type == 'picture') typeColor = Colors.red;
                              else if (type == 'structured') typeColor = Colors.blue;

                              return ListTile(
                                dense: true,
                                title: Text(q['question_text'] ?? 'No text', style: const TextStyle(fontWeight: FontWeight.w500)),
                                subtitle: Text('Type: ${type.toUpperCase()} | ID: ${q['id']}'),
                                trailing: Icon(Icons.warning_amber_rounded, color: typeColor, size: 16),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          );
        },
      );
    } catch (e) {
      setState(() {
        _isLoading = false;
        _status = 'Report error: $e';
      });
    }
  }
 


  Future<String?> _downloadAndSaveImage(String imageUrlOrPath) async {
    if (imageUrlOrPath.isEmpty) return null;
    try {
      String url = imageUrlOrPath;
      // If it looks like a Supabase storage path (not a full URL), we'd need the client to get the URL.
      // For now, assume we're passed the public URL or we resolve it outside.
      
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final directory = await getApplicationDocumentsDirectory();
        final imagesDir = Directory('${directory.path}/offline_images');
        if (!await imagesDir.exists()) {
          await imagesDir.create(recursive: true);
        }
        
        // Use a hash or the original filename to avoid duplicates
        final fileName = p.basename(Uri.parse(url).path);
        final safeFileName = '${DateTime.now().millisecondsSinceEpoch}_$fileName';
        final localFile = File('${imagesDir.path}/$safeFileName');
        
        await localFile.writeAsBytes(response.bodyBytes);
        return localFile.path;
      }
    } catch (e) {
      debugPrint('Error downloading image $imageUrlOrPath: $e');
    }
    return null;
  }
  bool _isLoading = false;
  String _status = '';

  Map<String, dynamic> _filterMap(Map<String, dynamic> data, List<String> allowedKeys) {
    final Map<String, dynamic> filtered = {};
    for (var key in allowedKeys) {
      if (data.containsKey(key)) {
        filtered[key] = data[key];
      }
    }
    return filtered;
  }

  Future<void> importAllData() async {
    setState(() {
      _isLoading = true;
      _status = 'Importing required data...';
    });

    final db = !kIsWeb ? await LocalDbService.database : null;
    final supabase = Supabase.instance.client;

    try {
      // Whitelists for DB insertion
      final allowedQuestionKeys = ['id', 'game_id', 'question_text', 'question_type', 'options', 'answer', 'created_at', 'points', 'source', 'approved', 'image_path_1', 'image_path_2', 'image_path_3', 'image_path_4'];
      final allowedGameKeys = ['id', 'mode', 'status', 'created_at', 'max_players', 'question_count'];
      final allowedUserKeys = ['id', 'username', 'created_at'];

      print('[SuperUserDashboard] Fetching approved questions...');
      final questions = await supabase.from('questions').select().eq('approved', 1);
      
      print('[SuperUserDashboard] Fetching games...');
      final games = await supabase.from('games').select();

      print('[SuperUserDashboard] Fetching users...');
      final users = await supabase.from('users').select();

      if (kIsWeb) {
        for (var q in questions) {
          await WebDatabaseHelper.insert('questions', q['id'], _filterMap(q, allowedQuestionKeys));
        }
        // ... (skipping web image download for now as filesystem is different)
        for (var u in users) {
          await WebDatabaseHelper.insert('users', u['id'], _filterMap(u, allowedUserKeys));
        }
      } else {
        final batch = db!.batch();
        for (var q in questions) {
          Map<String, dynamic> filtered = _filterMap(q, allowedQuestionKeys);
          
          // Download images if they exist in image_path_X columns
          for (int i = 1; i <= 4; i++) {
            final key = 'image_path_$i';
            if (filtered[key] != null && filtered[key].toString().isNotEmpty) {
              String publicUrl = supabase.storage.from('quiz_images').getPublicUrl(filtered[key].toString());
              String? localPath = await _downloadAndSaveImage(publicUrl);
              if (localPath != null) filtered[key] = localPath;
            }
          }

          // Also check options for embedded images (legacy/structured)
          if (filtered['question_type'] == 'picture' && filtered['options'] != null) {
             try {
               final options = jsonDecode(filtered['options'].toString());
               if (options['images'] is List) {
                 List<String> localPaths = [];
                 for (var img in options['images']) {
                   String publicUrl = supabase.storage.from('quiz_images').getPublicUrl(img.toString());
                   String? localPath = await _downloadAndSaveImage(publicUrl);
                   if (localPath != null) localPaths.add(localPath);
                 }
                 if (localPaths.isNotEmpty) {
                   options['images'] = localPaths;
                   filtered['options'] = jsonEncode(options);
                 }
               }
             } catch (e) {
               debugPrint('Error processing image options for question ${q['id']}: $e');
             }
          }

          batch.insert('questions', filtered, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        for (var g in games) {
          batch.insert('games', _filterMap(g, allowedGameKeys), conflictAlgorithm: ConflictAlgorithm.replace);
        }
        for (var u in users) {
          batch.insert('users', _filterMap(u, allowedUserKeys), conflictAlgorithm: ConflictAlgorithm.replace);
        }
        await batch.commit(noResult: true);
      }

      setState(() {
        _isLoading = false;
        _status = 'Successfully imported ${questions.length} questions, ${games.length} games, and ${users.length} users.';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import complete! (${questions.length} questions)'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _status = 'Error: ${e.toString()}';
      });
      print('[SuperUserDashboard] Import error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import failed: Check console for details'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> importQuestionsFromCSV() async {
    setState(() {
      _isLoading = true;
      _status = 'Importing questions from CSV...';
    });
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom, 
        allowedExtensions: ['csv'],
        withData: true, // Request bytes for web/small files
      );
      
      if (result != null) {
        String csvString = '';
        if (result.files.single.bytes != null) {
          csvString = utf8.decode(result.files.single.bytes!);
        } else if (result.files.single.path != null) {
          // On mobile, bytes might be null, so read from path
          final file = File(result.files.single.path!);
          csvString = await file.readAsString();
        } else {
          throw Exception('No file data available.');
        }

        final rows = const CsvToListConverter(eol: '\n').convert(csvString);
        final headers = rows.first.where((e) => e != null && e.toString().trim().isNotEmpty).map((e) => e.toString()).toList();
        debugPrint('CSV HEADERS: $headers');
        final questionRows = rows.skip(1);
        await _processCsvData(csvString);
        
        setState(() {
          _isLoading = false;
          _status = 'CSV Questions import complete!';
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('CSV Questions import complete!'), backgroundColor: Colors.green),
          );
        }
      } else {
        setState(() {
          _isLoading = false;
          _status = 'No file selected.';
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _status = 'CSV Import Error: ${e.toString()}';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('CSV Import failed: ${e.toString()}'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> importBundledQuestions() async {
    setState(() {
      _isLoading = true;
      _status = 'Importing bundled questions...';
    });
    try {
      final csvString = await rootBundle.loadString('assets/questions.csv');
      await _processCsvData(csvString);
      setState(() {
        _isLoading = false;
        _status = 'Bundled Questions import complete!';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bundled Questions import complete!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _status = 'Bundled Import Error: ${e.toString()}';
      });
      debugPrint('Bundled Import Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Bundled Import failed: ${e.toString()}'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _processCsvData(String csvString) async {
    final rows = const CsvToListConverter(eol: '\n').convert(csvString);
    if (rows.isEmpty) return;

    // Filter out null or empty headers and normalize to lowercase
    final headers = rows.first
        .map((e) => e?.toString().trim() ?? '')
        .toList();
    
    debugPrint('CSV HEADERS: $headers');
    final questionRows = rows.skip(1);
    final db = !kIsWeb ? await LocalDbService.database : null;
    const uuid = Uuid();
    final String defaultGameId = uuid.v4();
    
    final allowedKeys = ['id', 'game_id', 'question_text', 'question_type', 'options', 'answer', 'created_at', 'points', 'source', 'approved', 'image_path_1', 'image_path_2', 'image_path_3', 'image_path_4'];

    for (final row in questionRows) {
      if (row.isEmpty || row.every((element) => element == null || element.toString().trim().isEmpty)) {
        continue;
      }
      
      final rawMap = <String, dynamic>{};
      for (int i = 0; i < headers.length; i++) {
        if (headers[i].isEmpty) continue;
        final value = i < row.length ? row[i] : null;
        rawMap[headers[i]] = value;
      }

      final cleanMap = <String, dynamic>{};
      
      // Map and normalize keys
      rawMap.forEach((key, value) {
        final k = key.toLowerCase().trim();
        // Trim string values to remove \r etc.
        final cleanValue = (value is String) ? value.trim() : value;
        
        if (k == 'id' || k == 'question_id') {
          cleanMap['id'] = cleanValue?.toString();
        } else if (k == 'question' || k == 'question_text') {
          cleanMap['question_text'] = cleanValue?.toString();
        } else if (k == 'correct_answer' || k == 'answer') {
          cleanMap['answer'] = cleanValue?.toString();
        } else {
          cleanMap[k] = cleanValue;
        }
      });

      if (cleanMap['id'] == null || cleanMap['id'].toString().isEmpty) {
        // Generate a UUID if missing
        cleanMap['id'] = uuid.v4();
      }

      // Clean points
      cleanMap['points'] = int.tryParse(cleanMap['points']?.toString() ?? '2') ?? 2;
      
      // Check approved
      String approvedVal = cleanMap['approved']?.toString().toLowerCase() ?? '1';
      bool isApproved = approvedVal == '1' || approvedVal == 'true' || approvedVal == 'yes' || approvedVal == 'approved';
      cleanMap['approved'] = isApproved ? 1 : 0;

      // Normalize question_type
      String qt = cleanMap['question_type']?.toString().toLowerCase() ?? '';
      if (qt.contains('mcq') || qt.contains('multiple')) {
        cleanMap['question_type'] = 'mcq';
      } else if (qt.contains('picture') || qt.contains('image')) {
        cleanMap['question_type'] = 'picture';
      } else if (qt.contains('struct')) {
        cleanMap['question_type'] = 'structured';
      } else {
        // Fallback detection
        if (cleanMap.containsKey('option_a') || cleanMap.containsKey('option a')) {
           cleanMap['question_type'] = 'mcq';
        } else {
           cleanMap['question_type'] = 'mcq'; // Default
        }
      }

      // Handle MCQ options
      if (cleanMap['question_type'] == 'mcq') {
        final options = <String, dynamic>{};
        bool hasOptions = false;
        
        // Check various naming conventions
        final a = cleanMap['option_a'] ?? cleanMap['option a'] ?? cleanMap['a'];
        final b = cleanMap['option_b'] ?? cleanMap['option b'] ?? cleanMap['b'];
        final c = cleanMap['option_c'] ?? cleanMap['option c'] ?? cleanMap['c'];
        final d = cleanMap['option_d'] ?? cleanMap['option d'] ?? cleanMap['d'];
        
        if (a != null) { options['option_a'] = a.toString(); hasOptions = true; }
        if (b != null) { options['option_b'] = b.toString(); hasOptions = true; }
        if (c != null) { options['option_c'] = c.toString(); hasOptions = true; }
        if (d != null) { options['option_d'] = d.toString(); hasOptions = true; }
        
        if (hasOptions) {
          cleanMap['options'] = jsonEncode(options);
        }
      }

      // Handle Image based questions
      if (cleanMap['question_type'] == 'picture') {
        List<String> imagePaths = [];
        for (int i = 1; i <= 4; i++) {
          final key = 'image_path_$i';
          if (cleanMap.containsKey(key) && cleanMap[key]?.toString().trim().isNotEmpty == true) {
            String pathOrUrl = cleanMap[key].toString().trim();
            if (!kIsWeb && pathOrUrl.startsWith('http')) {
               String? localPath = await _downloadAndSaveImage(pathOrUrl);
               if (localPath != null) pathOrUrl = localPath;
            }
            imagePaths.add(pathOrUrl);
          }
        }
        if (imagePaths.isNotEmpty) {
          cleanMap['options'] = jsonEncode({'images': imagePaths});
        }
      }

      // Default game_id
      if (cleanMap['game_id'] == null || cleanMap['game_id'].toString().isEmpty) {
        cleanMap['game_id'] = defaultGameId;
      }

      // Whitelist filter for DB
      final finalMap = _filterMap(cleanMap, allowedKeys);
      
      if (kIsWeb) {
        await WebDatabaseHelper.insert('questions', finalMap['id'], finalMap);
      } else {
        await db!.insert('questions', finalMap, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
     
      body: Center(
        child: _isLoading
            ? const CircularProgressIndicator()
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton(
                    onPressed: importAllData,
                    child: const Text('Import All Data from Supabase'),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: importQuestionsFromCSV,
                    child: const Text('Import Questions from CSV File'),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: importBundledQuestions,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange.shade800,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Import Bundled Questions (Auto)'),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: fixQuestionTypesInDB,
                    child: const Text('Fix Question Types in DB'),
                  ),
                  const SizedBox(height: 20),
                   ElevatedButton(
                     onPressed: _showAllQuestionsDialog,
                     child: const Text('Show All Questions in DB'),
                   ),
                   const SizedBox(height: 20),
                   ElevatedButton(
                     onPressed: _showUnconsideredQuestionsReport,
                     style: ElevatedButton.styleFrom(
                       backgroundColor: Colors.red.shade50,
                       foregroundColor: Colors.red.shade900,
                       side: BorderSide(color: Colors.red.shade200),
                     ),
                     child: const Row(
                       mainAxisSize: MainAxisSize.min,
                       children: [
                         Icon(Icons.visibility_off_outlined, size: 18),
                         const SizedBox(width: 8),
                         Text('Unconsidered Questions Report'),
                       ],
                     ),
                   ),
                   const SizedBox(height: 20),
                   ElevatedButton(
                     onPressed: _showDataHealthReport,
                     style: ElevatedButton.styleFrom(
                       backgroundColor: Colors.blue.shade50,
                       foregroundColor: Colors.blue.shade900,
                       side: BorderSide(color: Colors.blue.shade200),
                     ),
                     child: const Row(
                       mainAxisSize: MainAxisSize.min,
                       children: [
                         Icon(Icons.health_and_safety_outlined, size: 18),
                         const SizedBox(width: 8),
                         Text('Data Health Report'),
                       ],
                     ),
                   ),
                   const SizedBox(height: 20),
                   ElevatedButton(
                     onPressed: _analyzeBrokenMCQs,
                     style: ElevatedButton.styleFrom(
                       backgroundColor: Colors.purple.shade50,
                       foregroundColor: Colors.purple.shade900,
                       side: BorderSide(color: Colors.purple.shade200),
                     ),
                     child: const Row(
                       mainAxisSize: MainAxisSize.min,
                       children: [
                         Icon(Icons.analytics_outlined, size: 18),
                         SizedBox(width: 8),
                         Text('Analyze Broken MCQs (Missing Options)'),
                       ],
                     ),
                   ),
                   const SizedBox(height: 20),
                  Text(_status),
                  const SizedBox(height: 20),
                  Container(
                    width: 300,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: SwitchListTile(
                      title: const Text('Enable Cloud Sync', style: TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: const Text('Allow operators to sync questions on this device', style: TextStyle(fontSize: 12)),
                      value: _syncEnabled,
                      onChanged: _toggleSyncSetting,
                      activeColor: Colors.purple,
                    ),
                  ),
                  const SizedBox(height: 80),
                ],
              ),
      ),
    );
  }
}
