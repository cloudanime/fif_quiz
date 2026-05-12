import 'dart:async';
import 'package:flutter/material.dart';

class TimerWidget extends StatefulWidget {
  final int timeLimit;
  final Function onTimerComplete;

  const TimerWidget(
      {super.key, required this.timeLimit, required this.onTimerComplete});

  @override
  _TimerWidgetState createState() => _TimerWidgetState();
}

class _TimerWidgetState extends State<TimerWidget> {
  late int remainingTime;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    remainingTime = widget.timeLimit;
    startTimer();
  }

  void startTimer() {
    timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (remainingTime > 0) {
        setState(() {
          remainingTime--;
        });
      } else {
        timer.cancel();
        widget.onTimerComplete();
      }
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      '$remainingTime',
      style: const TextStyle(fontSize: 50, fontWeight: FontWeight.bold),
    );
  }
}
