import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> initializeSupabase() async {
  await Supabase.initialize(
    url: 'https://myjtpbacjtanlqcqqsyk.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im15anRwYmFjanRhbmxxY3Fxc3lrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzY5ODYzMjcsImV4cCI6MjA5MjU2MjMyN30.yRAp5je3PpLKWP5xNA81i8NZ90xmSQuOppcj-_FHjtY',
  );
}
