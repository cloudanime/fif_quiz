import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

Database? _mobileDb;

Future<Database> getDatabase() async {
  if (_mobileDb != null) return _mobileDb!;

  final dbPath = await getDatabasesPath();

  _mobileDb = await openDatabase(
    path.join(dbPath, 'quiz_app.db'),
    version: 4,
    onCreate: (db, version) async {
      await _createTables(db);
    },
    onUpgrade: (db, oldVersion, newVersion) async {
      if (oldVersion < 2) {
        try { await db.execute('ALTER TABLE questions ADD COLUMN source TEXT'); } catch (_) {}
        try { await db.execute('ALTER TABLE questions ADD COLUMN approved INTEGER DEFAULT 0'); } catch (_) {}
      }
      if (oldVersion < 3) {
        try { await db.execute('ALTER TABLE questions ADD COLUMN image_path_1 TEXT'); } catch (_) {}
        try { await db.execute('ALTER TABLE questions ADD COLUMN image_path_2 TEXT'); } catch (_) {}
        try { await db.execute('ALTER TABLE questions ADD COLUMN image_path_3 TEXT'); } catch (_) {}
        try { await db.execute('ALTER TABLE questions ADD COLUMN image_path_4 TEXT'); } catch (_) {}
      }
      if (oldVersion < 4) {
        // Add points column if upgrading to version 4
        try { await db.execute('ALTER TABLE questions ADD COLUMN points INTEGER DEFAULT 2'); } catch (_) {}
      }
    },
  );

  return _mobileDb!;
}

Future<void> _createTables(Database db) async {
  await db.execute('''
    CREATE TABLE users (
      id TEXT PRIMARY KEY,
      username TEXT,
      created_at TEXT
    );
  ''');

  await db.execute('''
    CREATE TABLE games (
      id TEXT PRIMARY KEY,
      mode TEXT,
      status TEXT,
      created_at TEXT,
      max_players INTEGER,
      question_count INTEGER
    );
  ''');

  await db.execute('''
    CREATE TABLE game_players (
      id TEXT PRIMARY KEY,
      game_id TEXT,
      user_id TEXT,
      score INTEGER,
      joined_at TEXT,
      display_name TEXT
    );
  ''');

  await db.execute('''
    CREATE TABLE questions (
      id TEXT PRIMARY KEY,
      game_id TEXT,
      question_text TEXT,
      question_type TEXT,
      options TEXT,
      answer TEXT,
      created_at TEXT,
      points INTEGER,
      source TEXT,
      approved INTEGER DEFAULT 0,
      image_path_1 TEXT,
      image_path_2 TEXT,
      image_path_3 TEXT,
      image_path_4 TEXT
    );
  ''');

  await db.execute('''
    CREATE TABLE answers (
      id TEXT PRIMARY KEY,
      game_id TEXT,
      question_id TEXT,
      user_id TEXT,
      answer TEXT,
      is_correct INTEGER,
      answered_at TEXT
    );
  ''');
}