import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'session_data.dart';

class ChartWidget extends StatelessWidget {
  final List<SessionData> sessions;

  // Updated constructor
  const ChartWidget({super.key, required this.sessions});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: BarChart(
            BarChartData(
              barGroups: sessions.map((session) {
                return BarChartGroupData(
                  x: session.sessionNumber,
                  barRods: [
                    BarChartRodData(
                      toY: session.correctAnswers.toDouble(),
                      color: Colors.green,
                      width: 10,
                    ),
                    BarChartRodData(
                      toY: session.incorrectAnswers.toDouble(),
                      color: Colors.red,
                      width: 10,
                    ),
                    BarChartRodData(
                      toY: session.unansweredQuestions.toDouble(),
                      color: Colors.blue,
                      width: 10,
                    ),
                  ],
                );
              }).toList(),
              titlesData: const FlTitlesData(show: true),
            ),
          ),
        ),
        Expanded(
          child: LineChart(
            LineChartData(
              lineBarsData: [
                LineChartBarData(
                  spots: sessions
                      .map((session) => FlSpot(
                            session.sessionNumber.toDouble(),
                            session.playersCount.toDouble(),
                          ))
                      .toList(),
                  isCurved: true,
                  gradient: const LinearGradient(
                    colors: [Colors.orange, Colors.deepOrange],
                  ),
                  barWidth: 4,
                  dotData: const FlDotData(show: true),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
