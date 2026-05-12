import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class UsersManagementTab extends StatefulWidget {
  const UsersManagementTab({super.key});

  @override
  State<UsersManagementTab> createState() => _UsersManagementTabState();
}

class _UsersManagementTabState extends State<UsersManagementTab> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> users = [];
  List<Map<String, dynamic>> filteredUsers = [];
  String searchQuery = '';
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchUsers();
  }

  Future<void> _fetchUsers() async {
    setState(() => isLoading = true);
    try {
      final response = await _supabase
          .from('users')
          .select('id, username, profiles!inner(is_admin, is_super_admin)')
          .order('username');

      List<Map<String, dynamic>> fetchedUsers = List<Map<String, dynamic>>.from(response);
      
      // Sort: Super Admins (3) > Admins (2) > Regular Users (1)
      fetchedUsers.sort((a, b) {
        final profileA = a['profiles'] as Map<String, dynamic>;
        final profileB = b['profiles'] as Map<String, dynamic>;
        
        int getRoleScore(Map p) {
          if (p['is_super_admin'] == true || p['is_super_admin'].toString() == 'true') return 3;
          if (p['is_admin'] == true || p['is_admin'].toString() == 'true') return 2;
          return 1;
        }
        
        int scoreA = getRoleScore(profileA);
        int scoreB = getRoleScore(profileB);
        
        if (scoreA != scoreB) return scoreB.compareTo(scoreA); // Higher score first
        return (a['username'] ?? '').toString().toLowerCase().compareTo((b['username'] ?? '').toString().toLowerCase());
      });

      setState(() {
        users = fetchedUsers;
        filteredUsers = users;
        isLoading = false;
      });
    } catch (e) {
      print('Error fetching users: $e');
      setState(() => isLoading = false);
    }
  }

  void _filterUsers(String query) {
    setState(() {
      searchQuery = query;
      filteredUsers = users.where((user) {
        final username = (user['username'] ?? '').toString().toLowerCase();
        return username.contains(query.toLowerCase());
      }).toList();
    });
  }

  Future<void> _toggleAdmin(String userId, bool currentStatus) async {
    try {
      await _supabase
          .from('profiles')
          .update({'is_admin': !currentStatus})
          .eq('id', userId);
      _fetchUsers();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error updating user: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final double titleSize = screenWidth < 600 ? 14 : 16;

    if (isLoading) return const Center(child: CircularProgressIndicator());

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(10.0),
            child: TextField(
              onChanged: _filterUsers,
              decoration: InputDecoration(
                hintText: 'Search users...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: filteredUsers.length + 1,
              itemBuilder: (context, index) {
                if (index == filteredUsers.length) {
                  return const SizedBox(height: 80);
                }
                final user = filteredUsers[index];
                final profile = user['profiles'] as Map<String, dynamic>;
                final isAdmin = profile['is_admin'] == true;
                final isSuper = profile['is_super_admin'] == true;

                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  color: isSuper ? Colors.orange.shade50 : (isAdmin ? Colors.blue.shade50 : Colors.white),
                  elevation: 1,
                  child: ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                    leading: CircleAvatar(
                      radius: 16,
                      backgroundColor: isSuper ? Colors.orange : (isAdmin ? Colors.blue : Colors.grey),
                      child: Icon(
                        isSuper ? Icons.star : (isAdmin ? Icons.admin_panel_settings : Icons.person),
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                    title: Text(
                      user['username'] ?? 'Unknown User',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: titleSize),
                    ),
                    subtitle: Text(
                      isSuper ? 'Super Admin' : (isAdmin ? 'Admin' : 'Regular User'),
                      style: const TextStyle(fontSize: 11),
                    ),
                    trailing: isSuper 
                      ? Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.orange,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text('Owner', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                        )
                      : Transform.scale(
                          scale: 0.8,
                          child: Switch(
                            value: isAdmin,
                            onChanged: (val) => _toggleAdmin(user['id'], isAdmin),
                            activeThumbColor: Colors.blue,
                          ),
                        ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
