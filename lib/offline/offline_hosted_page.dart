import 'dart:convert';
import 'dart:io';

import 'package:church_quiz/offline/local_db_service.dart';
import 'package:church_quiz/offline/local_db_service_web.dart';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

import 'offline_player_setup_page.dart';

class OfflineHostedPage extends StatefulWidget {
  const OfflineHostedPage({super.key}); // Main entry for offline hosting

  @override
  State<OfflineHostedPage> createState() => _OfflineHostedPageState();
}

class _OfflineHostedPageState extends State<OfflineHostedPage> {
  bool _isLoading = false;
  String _status = '';

  Future<void> _logSync(int count, String type) async {
    try {
      final supabase = Supabase.instance.client;
      await supabase.from('offline_sync_logs').insert({
        'question_count': count,
        'sync_type': type,
        'platform': kIsWeb ? 'web' : 'mobile',
        'user_id': supabase.auth.currentUser?.id,
      });
    } catch (e) {
      debugPrint('Sync logging skipped or failed: $e');
    }
  }

  Future<String?> _downloadAndSaveImage(String imageUrlOrPath) async {
    if (imageUrlOrPath.isEmpty) return null;
    try {
      String url = imageUrlOrPath;
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final directory = await getApplicationDocumentsDirectory();
        final imagesDir = Directory('${directory.path}/offline_images');
        if (!await imagesDir.exists()) {
          await imagesDir.create(recursive: true);
        }
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

  Map<String, dynamic> _filterMap(Map<String, dynamic> data, List<String> allowedKeys) {
    final Map<String, dynamic> filtered = {};
    for (var key in allowedKeys) {
      if (data.containsKey(key)) {
        filtered[key] = data[key];
      }
    }
    return filtered;
  }

  Future<void> syncFromSupabase() async {
    // Check if admin has disabled syncing globally
    try {
      final supabase = Supabase.instance.client;
      final settings = await supabase
          .from('games')
          .select('status')
          .eq('id', '00000000-0000-0000-0000-000000000000')
          .maybeSingle();
          
      final syncEnabled = settings == null || settings['status'] != 'sync_disabled';
      
      if (!syncEnabled) {
        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Sync Disabled'),
              content: const Text('Cloud syncing is currently not available. if you recently synced, your data is likely up to date. You can still play the game offline.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
        return;
      }
    } catch (e) {
      debugPrint('Error checking global sync status: $e');
    }

    setState(() {
      _isLoading = true;
      _status = 'Connecting to cloud...';
    });

    final db = !kIsWeb ? await LocalDbService.database : null;
    final supabase = Supabase.instance.client;

    try {
      final allowedQuestionKeys = ['id', 'game_id', 'question_text', 'question_type', 'options', 'answer', 'created_at', 'points', 'source', 'approved', 'image_path_1', 'image_path_2', 'image_path_3', 'image_path_4'];
      final allowedGameKeys = ['id', 'mode', 'status', 'created_at', 'max_players', 'question_count'];
      final allowedUserKeys = ['id', 'username', 'created_at'];

      setState(() => _status = 'Fetching questions...');
      // Explicitly use 1 for approved as it is an integer in the database
      var questionsResponse = await supabase.from('questions').select().eq('approved', 1);
      
      final questions = questionsResponse as List<dynamic>;
      final games = await supabase.from('games').select();
      final users = await supabase.from('users').select();

      setState(() => _status = 'Processing questions...');

      if (kIsWeb) {
        for (var q in questions) {
          await WebDatabaseHelper.insert('questions', q['id'], _filterMap(q, allowedQuestionKeys));
        }
        for (var u in users) {
          await WebDatabaseHelper.insert('users', u['id'], _filterMap(u, allowedUserKeys));
        }
      } else {
        final batch = db!.batch();
        int processedCount = 0;
        for (var q in questions) {
          processedCount++;
          if (processedCount % 5 == 0) {
            setState(() => _status = 'Syncing...');
          }
          
          Map<String, dynamic> filtered = _filterMap(q, allowedQuestionKeys);
          
          // Ensure approved is int
          if (filtered['approved'] is bool) {
            filtered['approved'] = filtered['approved'] == true ? 1 : 0;
          }
          
          if (filtered['options'] != null && filtered['options'] is Map) {
            filtered['options'] = jsonEncode(filtered['options']);
          }

          for (int i = 1; i <= 4; i++) {
            final key = 'image_path_$i';
            if (filtered[key] != null && filtered[key].toString().isNotEmpty) {
              try {
                String publicUrl = supabase.storage.from('quiz_images').getPublicUrl(filtered[key].toString());
                String? localPath = await _downloadAndSaveImage(publicUrl);
                if (localPath != null) filtered[key] = localPath;
              } catch (e) {
                debugPrint('Image sync error: $e');
              }
            }
          }
          batch.insert('questions', filtered, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        
        setState(() => _status = 'Finalizing database...');
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
        _status = 'Sync complete! Questions updated.';
      });
      
      _logSync(questions.length, 'Cloud Sync');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cloud sync complete!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      debugPrint('Sync Error: $e');
      setState(() {
        _isLoading = false;
        _status = 'Sync failed: $e';
      });
    }
  }

  Future<void> importFromAssets() async {
    setState(() {
      _isLoading = true;
      _status = 'Loading questions from assets...';
    });
    try {
      final csvString = await rootBundle.loadString('assets/questions.csv');
      if (csvString.isEmpty) throw 'Asset file is empty';

      await _processCsvData(csvString);
      
      setState(() {
        _isLoading = false;
        _status = 'Default questions loaded successfully!';
      });
    } catch (e) {
      debugPrint('Asset Import Error: $e');
      setState(() {
        _isLoading = false;
        _status = 'Failed to load assets: $e';
      });
    }
  }

  Future<void> importFromCSV() async {
    setState(() {
      _isLoading = true;
      _status = 'Picking CSV file...';
    });
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom, 
        allowedExtensions: ['csv'],
        withData: true,
      );
      
      if (result != null) {
        String csvString = '';
        if (result.files.single.bytes != null) {
          csvString = utf8.decode(result.files.single.bytes!, allowMalformed: true);
        } else if (result.files.single.path != null) {
          final file = File(result.files.single.path!);
          final bytes = await file.readAsBytes();
          csvString = utf8.decode(bytes, allowMalformed: true);
        }

        if (csvString.isEmpty) throw 'Selected file is empty';

        await _processCsvData(csvString);
        
        setState(() {
          _isLoading = false;
          _status = 'CSV Import complete!';
        });
      } else {
        setState(() { _isLoading = false; _status = ''; });
      }
    } catch (e) {
      debugPrint('CSV Import Error: $e');
      setState(() {
        _isLoading = false;
        _status = 'Import failed: $e';
      });
    }
  }

  Future<void> _processCsvData(String csvString) async {
    // Robustly handle different line endings (CRLF, LF, CR)
    final normalizedContent = csvString.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final rows = const CsvToListConverter(eol: '\n').convert(normalizedContent);
    
    if (rows.isEmpty) return;
    final headers = rows.first.map((e) => e?.toString().trim().toLowerCase().replaceAll(' ', '_').replaceAll('-', '_') ?? '').toList();
    final questionRows = rows.skip(1);
    
    final db = !kIsWeb ? await LocalDbService.database : null;
    const uuid = Uuid();
    final String defaultGameId = uuid.v4();
    final allowedKeys = ['id', 'game_id', 'question_text', 'question_type', 'options', 'answer', 'created_at', 'points', 'source', 'approved', 'image_path_1', 'image_path_2', 'image_path_3', 'image_path_4'];

    int importedCount = 0;
    List<Map<String, dynamic>> questionsToInsert = [];
    for (final row in questionRows) {
      if (row.isEmpty || row.every((element) => element == null || element.toString().trim().isEmpty)) continue;
      
      final rawMap = <String, dynamic>{};
      for (int i = 0; i < headers.length; i++) {
        if (headers[i].isEmpty) continue;
        var value = i < row.length ? row[i] : null;
        if (value is String) value = value.trim();
        rawMap[headers[i]] = value;
      }
      
      final cleanMap = <String, dynamic>{};
      rawMap.forEach((key, value) {
        final k = key.toLowerCase().trim().replaceAll(' ', '_').replaceAll('-', '_');
        if (k == 'id' || k == 'question_id' || k == 'no') cleanMap['id'] = value?.toString();
        else if (k == 'question' || k == 'question_text' || k == 'questiontext' || k == 'text') cleanMap['question_text'] = value?.toString();
        else if (k == 'correct_answer' || k == 'answer' || k == 'correctanswer') cleanMap['answer'] = value?.toString();
        else if (k == 'type' || k == 'question_type' || k == 'category') cleanMap['question_type'] = value?.toString();
        else cleanMap[k] = value;
      });

      if (cleanMap['id'] == null || cleanMap['id'].toString().isEmpty) cleanMap['id'] = uuid.v4();
      
      // Defaults and parsing
      cleanMap['points'] = int.tryParse(cleanMap['points']?.toString() ?? '2') ?? 2;
      String approvedVal = cleanMap['approved']?.toString().toLowerCase() ?? '1';
      cleanMap['approved'] = (approvedVal == '1' || approvedVal == 'true' || approvedVal == 'yes' || approvedVal.isEmpty) ? 1 : 0;

      String qt = cleanMap['question_type']?.toString().toLowerCase() ?? '';
      if (qt.contains('mcq') || qt.contains('multi')) cleanMap['question_type'] = 'mcq';
      else if (qt.contains('picture') || qt.contains('image')) cleanMap['question_type'] = 'picture';
      else if (qt.contains('struct')) cleanMap['question_type'] = 'structured';
      else cleanMap['question_type'] = 'mcq';

      if (cleanMap['question_type'] == 'mcq') {
        final options = <String, dynamic>{};
        final a = cleanMap['option_a'] ?? cleanMap['option a'] ?? cleanMap['a'];
        final b = cleanMap['option_b'] ?? cleanMap['option b'] ?? cleanMap['b'];
        final c = cleanMap['option_c'] ?? cleanMap['option c'] ?? cleanMap['c'];
        final d = cleanMap['option_d'] ?? cleanMap['option d'] ?? cleanMap['d'];
        if (a != null) options['option_a'] = a.toString();
        if (b != null) options['option_b'] = b.toString();
        if (c != null) options['option_c'] = c.toString();
        if (d != null) options['option_d'] = d.toString();
        if (options.isNotEmpty) cleanMap['options'] = jsonEncode(options);
      }

      if (cleanMap['question_type'] == 'picture') {
        List<String> imagePaths = [];
        for (int i = 1; i <= 4; i++) {
          final key = 'image_path_$i';
          if (cleanMap.containsKey(key) && cleanMap[key]?.toString().trim().isNotEmpty == true) {
            String pathOrUrl = cleanMap[key].toString().trim();
            if (!kIsWeb && pathOrUrl.startsWith('http')) {
               try {
                 String? localPath = await _downloadAndSaveImage(pathOrUrl);
                 if (localPath != null) pathOrUrl = localPath;
               } catch (_) {}
            }
            imagePaths.add(pathOrUrl);
          }
        }
        if (imagePaths.isNotEmpty) cleanMap['options'] = jsonEncode({'images': imagePaths});
      }

      if (cleanMap['game_id'] == null) cleanMap['game_id'] = defaultGameId;
      questionsToInsert.add(_filterMap(cleanMap, allowedKeys));
    }

    if (kIsWeb) {
      for (final q in questionsToInsert) {
        await WebDatabaseHelper.insert('questions', q['id'], q);
      }
    } else {
      final batch = db!.batch();
      for (final q in questionsToInsert) {
        batch.insert('questions', q, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    }
  }

  Future<void> _showDbDebugInfo() async {
    try {
      int total = 0;
      int approved = 0;
      if (kIsWeb) {
        final maps = await WebDatabaseHelper.getAll('questions');
        total = maps.length;
        approved = maps.where((e) => (e['approved'] ?? 0) == 1).length;
      } else {
        final db = await LocalDbService.database;
        final resTotal = await db.rawQuery('SELECT COUNT(*) as count FROM questions');
        final resApproved = await db.rawQuery('SELECT COUNT(*) as count FROM questions WHERE approved = 1');
        total = Sqflite.firstIntValue(resTotal) ?? 0;
        approved = Sqflite.firstIntValue(resApproved) ?? 0;
      }

      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Database Status'),
          content: Text('Total Questions: $total\nApproved Questions: $approved\n\nQuestions must be approved (value 1) to show in the grid.'),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
        ),
      );
    } catch (e) {
      debugPrint('Debug Info Error: $e');
    }
  }

  Future<void> _showImportedQuestionsTable() async {
    try {
      List<Map<String, dynamic>> questions = [];
      if (kIsWeb) {
        questions = await WebDatabaseHelper.getAll('questions');
      } else {
        final db = await LocalDbService.database;
        questions = await db.query('questions', limit: 100, orderBy: 'created_at DESC');
      }

      if (!mounted) return;
      
      showDialog(
        context: context,
        builder: (context) => Dialog.fullscreen(
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Imported Questions (Last 100)'),
              leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              backgroundColor: const Color.fromARGB(255, 96, 5, 105),
            ),
            body: questions.isEmpty 
              ? const Center(child: Text('No questions found in database.'))
              : SingleChildScrollView(
                  scrollDirection: Axis.vertical,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('ID')),
                        DataColumn(label: Text('Text')),
                        DataColumn(label: Text('Type')),
                        DataColumn(label: Text('Approved')),
                      ],
                      rows: questions.map((q) => DataRow(
                        cells: [
                          DataCell(Text(q['id']?.toString().substring(0, 8) ?? '')),
                          DataCell(SizedBox(width: 200, child: Text(q['question_text']?.toString() ?? '', overflow: TextOverflow.ellipsis))),
                          DataCell(Text(q['question_type']?.toString() ?? '')),
                          DataCell(Text(q['approved']?.toString() ?? '0')),
                        ],
                      )).toList(),
                    ),
                  ),
                ),
          ),
        ),
      );
    } catch (e) {
      debugPrint('View Table Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Offline Multiplayer Quiz (host)',
          style: TextStyle(fontSize: (screenHeight * 0.020).clamp(16.0, 20.0)),
        ),
        backgroundColor: const Color.fromARGB(255, 96, 5, 105),
      ),
      body: SafeArea(
        child: Stack(
          children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: SingleChildScrollView(
                child: Column(
                children: [
                  ElevatedButton(
                    onPressed: _isLoading ? null : () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const OfflinePlayerSetupPage()),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color.fromARGB(255, 96, 5, 105),
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.1, vertical: 20),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                      elevation: 8,
                    ),
                    child: Text(
                      'Start New Offline Game',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 50),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40.0),
                    child: Row(
                      children: [
                        const Expanded(child: Divider()),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10.0),
                          child: Text('DATABASE MANAGEMENT', 
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                        ),
                        const Expanded(child: Divider()),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                 Padding(
  padding: const EdgeInsets.symmetric(horizontal: 40.0),
  child: RichText(
    textAlign: TextAlign.center,
    text: TextSpan(
      style: TextStyle(color: Colors.grey.shade700, fontSize: 13, height: 1.4),
      children: const [
        TextSpan(
          text: 'To play offline, first get questions online by clicking Sync Cloud below or Load Package below.\n\n',
        ),
        TextSpan(
          text: 'Note: ',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        TextSpan(
          text: 'Questions in the database is updated to make sure you periodically get the latest questions. To update via the \'Load Pakage\', you need to get the latest installation file. ',
        ),
      ],
    ),
  ),
),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildImportButton(
                        icon: Icons.cloud_sync,
                        label: 'Sync Cloud',
                        onPressed: syncFromSupabase,
                        color: Colors.blue.shade700,
                      ),
                      const SizedBox(width: 15),
                      _buildImportButton(
                        icon: Icons.auto_awesome,
                        label: 'Load Package',
                        onPressed: importFromAssets,
                        color: Colors.purple.shade700,
                      ),
                    ],
                  ),
                  const SizedBox(height: 30),
                  if (_status.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        _status,
                        style: TextStyle(color: Colors.grey.shade800, fontSize: 13, fontStyle: FontStyle.italic),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                    
                      const SizedBox(width: 10),
                      
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
          if (_isLoading)
            Container(
              color: Colors.black26,
              child: const Center(child: CircularProgressIndicator(color: Colors.white)),
            ),
        ],
      ),
    ),
  );
}

  Widget _buildImportButton({required IconData icon, required String label, required VoidCallback onPressed, required Color color}) {
    return Column(
      children: [
        IconButton.filled(
          onPressed: _isLoading ? null : onPressed,
          icon: Icon(icon, size: 28),
          style: IconButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.all(15),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
      ],
    );
  }
}