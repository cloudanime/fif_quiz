import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class QuizApp extends StatelessWidget {
  const QuizApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Legacy Quiz',
      theme: ThemeData(
        primarySwatch: Colors.purple,
        scaffoldBackgroundColor: Colors.grey[50],
        appBarTheme: const AppBarTheme(
          backgroundColor: Color.fromARGB(255, 69, 18, 78),
          elevation: 0,
          centerTitle: false,
        ),
        cardTheme: const CardThemeData(
          elevation: 2,
        ),
      ),
      home: const InstructionsPage(),
    );
  }
}

class InstructionsPage extends StatelessWidget {
  const InstructionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 600;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color.fromARGB(255, 69, 18, 78),
        elevation: 0,
        automaticallyImplyLeading: false, // Remove back arrow
        title: Row(
          children: [
            Image.asset(
              'assets/logo.png',
              width: MediaQuery.of(context).size.width * 0.12,
              height: MediaQuery.of(context).size.height * 0.05,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: 'Legacy Quiz\n',
                      style: TextStyle(
                        fontSize: (MediaQuery.of(context).size.height * 0.02).clamp(14.0, 22.0),
                        color: const Color.fromARGB(247, 251, 232, 13),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    TextSpan(
                      text: '(Dynamic questions)',
                      style: TextStyle(
                        fontSize: (MediaQuery.of(context).size.height * 0.012).clamp(10.0, 14.0),
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
       
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            tooltip: 'Close Instructions',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: SingleChildScrollView(
              padding: EdgeInsets.all(isSmallScreen ? 16 : 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Welcome Banner
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFF450E4E),
                          Color(0xFF6A1B9A),
                          Color(0xFF8E24AA),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF450E4E).withOpacity(0.4),
                          blurRadius: 15,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.auto_awesome,
                                color: Colors.yellow,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 16),
                            const Text(
                              '100 Years of Legacy',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'The FIFMI 100 Quiz Challenge App is both a tribute to our church history and a reflection on the 100 years of earthly life lived by our visionary and founder, the bondservant of God, Archbishop Ezekiel Handinawangu Guti. Explore, learn, and celebrate years of devine grace.',
                          style: TextStyle(
                            fontSize: 15,
                            color: Colors.white.withOpacity(0.95),
                            height: 1.6,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Choose Your Journey Section
                  _buildSectionHeader(Icons.map, 'Choose Your Playing Mode'),
                  const SizedBox(height: 12),
                  _buildInfoCard(
                    icon: Icons.psychology,
                    iconColor: Colors.blue,
                    title: 'Quiz Master (Online)',
                    description: 'No Login. Host a game on this device using the latest cloud questions (Requires Internet).',
                  ),
                  const SizedBox(height: 12),
                  _buildInfoCard(
                    icon: Icons.wifi_off,
                    iconColor: Colors.orange,
                    title: 'Quiz Master (Offline)',
                    description: 'No Login. Host a game on this device using local questions (No Internet required).',
                  ),
                  const SizedBox(height: 12),
                  _buildInfoCard(
                    icon: Icons.people,
                    iconColor: Colors.purple,
                    title: 'Online Challenge',
                    description: 'Requires Login. Host or Join rooms to compete with others globally in real-time synchronized races.',
                  ),
                  const SizedBox(height: 12),
                  _buildInfoCard(
                    icon: Icons.bolt,
                    iconColor: Colors.amber,
                    title: 'Quick Join Rooms',
                    description: 'Join a live challenge instantly! Pick a player count (2, 3, 5, etc.) and jump straight into the action.',
                  ),

                  const SizedBox(height: 24),

                  // How To Play Section
                  _buildSectionHeader(Icons.play_circle_filled, 'Getting Started'),
                  const SizedBox(height: 12),
                  _buildStepCard(1, 'Pick a Mode', 'Choose between Solo/Local play (No Login) or Global Challenges (Login Required).'),
                  _buildStepCard(2, 'Set the Stage', 'For Quiz Master modes, choose the number of players. For Online rooms, share your 6-digit Join Code.'),
                  _buildStepCard(3, 'Question Grid', '100 questions are randomly selected per session:\n• MCQ (1-70)\n• Picture-based (71-80)\n• Structured Questions (81-100)'),
                  _buildStepCard(4, 'Marking & Scoring', 'Quiz Masters can manually mark responses on their device. Online games feature automated scoring and real-time leaderboards.'),

                  const SizedBox(height: 24),

                  // Online Challenge Features
                  _buildSectionHeader(Icons.cloud_queue, 'Online Multiplayer Features'),
                  const SizedBox(height: 12),
                  _buildFeatureCard(
                    Icons.groups,
                    'Team Mode',
                    'Join forces with others! Aggregate your scores and compete as a single unit.',
                  ),
                  _buildFeatureCard(
                    Icons.sync,
                    'Real-time Synchronization',
                    'All players answer the same question at the same time for a fair race.',
                  ),
                  _buildFeatureCard(
                    Icons.bar_chart,
                    'Live Leaderboards',
                    'Watch the race unfold with animated bar charts showing everyone\'s progress.',
                  ),

                  const SizedBox(height: 24),

                  // Scoring Rules
                  _buildSectionHeader(Icons.scoreboard, 'Scoring & Rules'),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.green[50],
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.green[200]!),
                    ),
                    child: Column(
                      children: [
                        _buildBulletPoint(Icons.check_circle, Colors.green, 'Correct answers: points awarded'),
                        const SizedBox(height: 8),
                        // Bonus Points Card
                        Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF450E4E), Color(0xFF7B1FA2)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF450E4E).withOpacity(0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.bolt, color: Colors.white, size: 24),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Bonus Points',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                        letterSpacing: 1,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Be the fastest to answer correctly and get bonus points!',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.white.withOpacity(0.95),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        _buildBulletPoint(Icons.cancel, Colors.red, 'Incorrect answers: points deducted'),
                        const SizedBox(height: 8),
                        _buildBulletPoint(Icons.remove_circle, Colors.grey, 'Unattempted: 0 points'),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Special Features
                  _buildSectionHeader(Icons.star, 'Special Features'),
                  const SizedBox(height: 12),
                  _buildSpecialFeatureCard(
                    Icons.play_circle_outline,
                    Colors.purple,
                    'Legacy Video',
                    'Tap the "100 Years" logo on the home screen to watch "The Legacy Continues" video.',
                  ),
                  _buildSpecialFeatureCard(
                    Icons.update,
                    Colors.blue,
                    'Dynamic Questions',
                    'The database is constantly updated with new questions from church history.',
                  ),
                  _buildSpecialFeatureCard(
                    Icons.add_circle_outline,
                    Colors.green,
                    'Contribute Questions',
                    'Click the "+" menu in the Session or Grid pages to submit MCQ, Picture, or Structured questions.',
                  ),
                  _buildSpecialFeatureCard(
                    Icons.verified,
                    Colors.orange,
                    'Verification',
                    'Submissions are reviewed by administrators before being added to the official database.',
                  ),

                  const SizedBox(height: 16),

                  // Disclaimer
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.red[50],
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.red[200]!),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber, color: Colors.red[700]),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'While every effort has been made to ensure accuracy, errors or omissions may occur. Please report any such issues to the Legacy Quiz Administrators',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.red[800],
                              fontWeight: FontWeight.w500,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Footer
                  Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GestureDetector(
                          onTap: () async {
                            final Uri emailLaunchUri = Uri(
                              scheme: 'mailto',
                              path: 'fifmime.egea@gmail.com',
                            );
                            if (await canLaunchUrl(emailLaunchUri)) {
                              await launchUrl(emailLaunchUri);
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF45124E).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(30),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.email, size: 16, color: Color(0xFF45124E)),
                                SizedBox(width: 8),
                                Text(
                                  'fifmime.egea@gmail.com',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF45124E),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Text(
                          'Haiperi 🙏',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.purple[700],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Compact Support Link
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.orange[50],
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.orange[100]!),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center, // Icon aligns with first line
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.emoji_food_beverage, size: 18, color: Colors.orange[900]),
                          const SizedBox(width: 13),
                          Expanded(
                            child: Text(
                              'If you find this App helpful and would like to support, you can buy us a coffee or chai ☕🫖',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.normal,
                                color: Colors.orange[900],
                              ),
                              softWrap: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 5),
                ],
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
        decoration: const BoxDecoration(
          color: Color(0xFF450E4E),
          borderRadius: BorderRadius.zero,
        ),
        child: const Text(
          'Developed by FIFMI Middle East (EGEA and Media)',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.normal,
            fontStyle: FontStyle.italic,
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF45124E), size: 28),
        const SizedBox(width: 12),
        Text(
          title,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Color(0xFF45124E),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String description,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.grey.withOpacity(0.1)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: iconColor, size: 28),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF45124E),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[800],
                      height: 1.5,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepCard(int step, String title, String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: const BoxDecoration(
              color: Color.fromARGB(255, 69, 18, 78),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '$step',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[700],
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureCard(IconData icon, String title, String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: const Color.fromARGB(255, 69, 18, 78), size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSpecialFeatureCard(
    IconData icon,
    Color color,
    String title,
    String description,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          border: Border.all(color: color.withOpacity(0.3)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[700],
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBulletPoint(IconData icon, Color color, String text) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 14),
          ),
        ),
      ],
    );
  }
}
