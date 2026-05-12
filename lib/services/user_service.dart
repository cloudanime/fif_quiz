import 'package:supabase_flutter/supabase_flutter.dart';

class UserService {
  static final _supabase = Supabase.instance.client;

  /// Checks if the current user is a super admin.
  static Future<bool> isSuperAdmin() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return false;

    try {
      final response = await _supabase
          .from('profiles')
          .select('is_super_admin')
          .eq('id', user.id)
          .single();
      
      return response['is_super_admin'] == true;
    } catch (e) {
      return false;
    }
  }

  /// Checks if the current user is an admin or super admin.
  static Future<bool> isAdmin() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return false;

    try {
      final response = await _supabase
          .from('profiles')
          .select('is_admin, is_super_admin')
          .eq('id', user.id)
          .single();
      
      return response['is_admin'] == true || response['is_super_admin'] == true;
    } catch (e) {
      print('Error checking admin status: $e');
      return false;
    }
  }

  /// Gets the current user's profile data.
  static Future<Map<String, dynamic>?> getProfile() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return null;

    try {
      return await _supabase
          .from('profiles')
          .select()
          .eq('id', user.id)
          .single();
    } catch (e) {
      print('Error fetching profile: $e');
      return null;
    }
  }

  /// Resolves a username to an email address.
  static Future<String?> getEmailByUsername(String username) async {
    try {
      // 1. Find user ID from the public users table
      final userResponse = await _supabase
          .from('users')
          .select('id')
          .eq('username', username)
          .maybeSingle();

      if (userResponse == null) return null;

      final userId = userResponse['id'];

      // 2. Find email from the profiles table linked to that ID
      final profileResponse = await _supabase
          .from('profiles')
          .select('email')
          .eq('id', userId)
          .maybeSingle();

      return profileResponse?['email'];
    } catch (e) {
      print('Error resolving username to email: $e');
      return null;
    }
  }

  /// Checks if an email already exists in the profiles table.
  static Future<bool> checkEmailExists(String email) async {
    try {
      final response = await _supabase
          .from('profiles')
          .select('id')
          .eq('email', email)
          .maybeSingle();
      return response != null;
    } catch (e) {
      print('Error checking email existence: $e');
      return false;
    }
  }

  /// Fetches user join counts per day from Supabase
  static Future<List<Map<String, dynamic>>> fetchUsersJoinedPerDay(
      String startDate, String endDate) async {
    try {
      final response = await _supabase
          .from('users')
          .select('created_at')
          .gte('created_at', '${startDate}T00:00:00')
          .lte('created_at', '${endDate}T23:59:59');

      final List<dynamic> data = response as List<dynamic>;
      
      // Group by day and count
      Map<String, int> dailyCounts = {};
      for (var item in data) {
        final dateStr = item['created_at'].toString().split('T').first;
        dailyCounts[dateStr] = (dailyCounts[dateStr] ?? 0) + 1;
      }

      // Convert to the list format expected by the UI
      List<Map<String, dynamic>> results = dailyCounts.entries.map((e) => {
        'session_date': e.key,
        'session_count': e.value,
      }).toList();

      // Sort by date
      results.sort((a, b) => a['session_date'].compareTo(b['session_date']));
      
      return results;
    } catch (e) {
      print('Error fetching users joined stats: $e');
      return [];
    }
  }

  /// Registers a new session ID for the current user.
  static Future<void> registerSession(String sessionId) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    try {
      await _supabase.from('profiles').update({
        'last_session_id': sessionId,
      }).eq('id', user.id);
    } catch (e) {
      print('Error registering session: $e');
    }
  }

  /// Checks if the current session is still valid.
  static Future<bool> isSessionValid(String localSessionId) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return true;

    try {
      final response = await _supabase
          .from('profiles')
          .select('last_session_id')
          .eq('id', user.id)
          .maybeSingle();
      
      if (response == null || response['last_session_id'] == null) return true;
      
      return response['last_session_id'] == localSessionId;
    } catch (e) {
      print('Error validating session: $e');
      return true;
    }
  }
}
