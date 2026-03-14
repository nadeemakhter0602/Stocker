import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class ChangeBadge extends StatelessWidget {
  final double change;
  final double changePercent;
  final bool compact;

  const ChangeBadge({
    super.key,
    required this.change,
    required this.changePercent,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final isPositive = change >= 0;
    final color = isPositive ? AppTheme.positiveColor : AppTheme.negativeColor;
    final sign = isPositive ? '+' : '';
    final icon = isPositive ? Icons.arrow_drop_up : Icons.arrow_drop_down;

    if (compact) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withAlpha(25),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          '$sign${changePercent.toStringAsFixed(2)}%',
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 20),
        Text(
          '$sign${change.toStringAsFixed(2)} ($sign${changePercent.toStringAsFixed(2)}%)',
          style: TextStyle(
            color: color,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
