import 'package:flutter/material.dart';
import '../models/network_quality.dart';

/// Network quality indicator widget (signal bars style)
class NetworkQualityIndicator extends StatelessWidget {
  final NetworkQuality quality;
  final bool showLabel;

  const NetworkQualityIndicator({
    super.key,
    required this.quality,
    this.showLabel = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Signal bars
        _buildSignalBars(),

        // Optional label
        if (showLabel) ...[
          const SizedBox(width: 6),
          Text(
            quality.displayText,
            style: TextStyle(
              color: quality.color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSignalBars() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(5, (index) {
        final isActive = index < quality.bars;
        return Container(
          width: 3,
          height: 6.0 + (index * 2.5), // Increasing height
          margin: const EdgeInsets.only(right: 2),
          decoration: BoxDecoration(
            color: isActive ? quality.color : Colors.grey.withOpacity(0.3),
            borderRadius: BorderRadius.circular(1),
          ),
        );
      }),
    );
  }
}
