import 'package:flutter/foundation.dart';
import 'package:sembast/sembast.dart';
import 'package:sembast_web/sembast_web.dart';

Database? _webDb;

Future<Database> getDatabase() async {
  if (_webDb != null) return _webDb!;

  final dbPath = 'quiz_app.db';
  debugPrint('Sembast: Opening database at: $dbPath');
  _webDb = await databaseFactoryWeb.openDatabase(dbPath);
  return _webDb!;
}

class WebDatabaseHelper {
  /// Clear all records from a given store (table)
  static Future<void> clearTable(String storeName) async {
    final db = await getDatabase();
    final store = stringMapStoreFactory.store(storeName);
    await store.delete(db);
  }
  static Future<void> insert(
    String storeName,
    String id,
    Map<String, dynamic> data,
  ) async {
    final db = await getDatabase();
    final store = stringMapStoreFactory.store(storeName);
    await store.record(id).put(db, data);
  }

  static Future<void> delete(
    String storeName,
    String id,
  ) async {
    final db = await getDatabase();
    final store = stringMapStoreFactory.store(storeName);
    await store.record(id).delete(db);
  }

  static Future<Map<String, dynamic>?> get(
    String storeName,
    String id,
  ) async {
    final db = await getDatabase();
    final store = stringMapStoreFactory.store(storeName);
    return await store.record(id).get(db);
  }

  static Future<List<Map<String, dynamic>>> getAll(String storeName) async {
    final db = await getDatabase();
    final store = stringMapStoreFactory.store(storeName);

    debugPrint('Sembast: Fetching all from store: $storeName');
    final records = await store.find(
      db,
      finder: Finder(
        sortOrders: [
          SortOrder('created_at', false), // descending
        ],
      ),
    );

    debugPrint('Sembast: Found ${records.length} records in $storeName');
    return records.map((record) => record.value).toList();
  }
}