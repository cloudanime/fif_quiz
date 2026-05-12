import 'package:flutter/material.dart';

class Scoreboard extends StatelessWidget {
  final List<int> scores;

  const Scoreboard({super.key, required this.scores});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 100,
      child: ListView.builder(
        itemCount: scores.length,
        itemBuilder: (context, index) {
          return ListTile(
            title: Text('Team ${index + 1}'),
            trailing: Text('${scores[index]}'),
          );
        },
      ),
    );
  }
}
