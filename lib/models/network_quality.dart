import 'package:flutter/material.dart';

/// Network quality levels for real-time connection feedback
enum NetworkQuality {
  excellent,
  good,
  poor,
  reconnecting,
}

extension NetworkQualityDisplay on NetworkQuality {
  /// Get display text
  String get displayText {
    switch (this) {
      case NetworkQuality.excellent:
        return 'Excellent';
      case NetworkQuality.good:
        return 'Good';
      case NetworkQuality.poor:
        return 'Poor';
      case NetworkQuality.reconnecting:
        return 'Reconnecting';
    }
  }

  /// Get indicator color
  Color get color {
    switch (this) {
      case NetworkQuality.excellent:
        return const Color(0xFF34C759); // Green
      case NetworkQuality.good:
        return const Color(0xFF34C759); // Green
      case NetworkQuality.poor:
        return const Color(0xFFFF9500); // Orange
      case NetworkQuality.reconnecting:
        return const Color(0xFFFF3B30); // Red
    }
  }

  /// Get number of bars (1-5)
  int get bars {
    switch (this) {
      case NetworkQuality.excellent:
        return 5;
      case NetworkQuality.good:
        return 3;
      case NetworkQuality.poor:
        return 1;
      case NetworkQuality.reconnecting:
        return 0;
    }
  }
}
