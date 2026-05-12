import 'package:flutter/material.dart';

class AppHeader extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final double baseLogoHeight;
  final double baseFontSize;

  const AppHeader({
    super.key,
    required this.title,
    this.baseLogoHeight = 40.0, // Default logo height for standard screens
    this.baseFontSize = 20.0, // Default font size, dynamically set later
  });

  @override
  Widget build(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;
    double screenHeight = MediaQuery.of(context).size.height;

    // Adjust the logo height based on the smaller dimension (width or height), with reasonable limits
    double adjustedLogoHeight =
        (screenHeight * 0.06).clamp(30.0, baseLogoHeight);

    // Adjust the font size based on screen width with a reasonable limit
    double adjustedFontSize = (screenWidth * 0.028).clamp(14.0, baseFontSize);

    return AppBar(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset(
            'assets/baba100new.jpg',
            height: adjustedLogoHeight *
                1.5, // Increased size for the new logo aspect ratio
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: adjustedFontSize, // Use adjusted font size
                fontWeight: FontWeight.bold,
                color: const Color.fromARGB(255, 230, 220, 232),
              ),
            ),
          ),
        ],
      ),
      centerTitle: true,
      backgroundColor: const Color.fromARGB(255, 83, 2, 107),
    );
  }

  @override
  Size get preferredSize =>
      const Size.fromHeight(60.0); // Default AppBar height
}
