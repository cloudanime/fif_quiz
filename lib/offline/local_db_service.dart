import 'local_db_service_stub.dart'
    if (dart.library.html) 'local_db_service_web.dart'
    if (dart.library.io) 'local_db_service_mobile.dart';

abstract class LocalDbService {
  static Future<dynamic> get database => getDatabase();
}