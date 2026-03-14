import 'package:flutter/material.dart';

class QuoteTypeBadge extends StatelessWidget {
  final String quoteType;

  const QuoteTypeBadge({super.key, required this.quoteType});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isEtf = quoteType.toUpperCase() == 'ETF';
    final label = quoteType.toUpperCase() == 'MUTUALFUND' ? 'FUND' : quoteType.toUpperCase();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isEtf
            ? colorScheme.tertiary.withAlpha(30)
            : colorScheme.primary.withAlpha(30),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: isEtf ? colorScheme.tertiary : colorScheme.primary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
