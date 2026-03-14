import 'dart:math';
import 'package:flutter/material.dart';

/// Fan chart: historical line on the left, percentile bands on the right.
/// [historical] = recent daily closes shown as context.
/// [p5..p95]   = forecast bands, length = horizonDays + 1 (index 0 = today).
class ForecastChart extends StatelessWidget {
  final List<double> historical;
  final List<double> p5, p25, p50, p75, p95;
  final String currency;

  const ForecastChart({
    super.key,
    required this.historical,
    required this.p5,
    required this.p25,
    required this.p50,
    required this.p75,
    required this.p95,
    this.currency = r'$',
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _ForecastPainter(
        historical: historical,
        p5: p5,
        p25: p25,
        p50: p50,
        p75: p75,
        p95: p95,
        currency: currency,
        primaryColor: Theme.of(context).colorScheme.primary,
        outlineColor: Theme.of(context).colorScheme.outline,
      ),
    );
  }
}

class _ForecastPainter extends CustomPainter {
  final List<double> historical;
  final List<double> p5, p25, p50, p75, p95;
  final String currency;
  final Color primaryColor, outlineColor;

  static const double _yAxisW = 56.0;

  const _ForecastPainter({
    required this.historical,
    required this.p5,
    required this.p25,
    required this.p50,
    required this.p75,
    required this.p95,
    required this.currency,
    required this.primaryColor,
    required this.outlineColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final chartW = size.width - _yAxisW;
    final chartH = size.height;

    final histLen = historical.length;
    final foreLen = p50.length; // horizonDays + 1

    if (histLen < 2 || foreLen < 2) return;

    // X layout: equal pixel-per-segment across both regions
    final totalSegs = (histLen - 1) + (foreLen - 1);
    if (totalSegs == 0) return;
    final segW = chartW / totalSegs;
    final histW = (histLen - 1) * segW;

    // Y range: covers historical + forecast extremes
    final allPrices = [...historical, ...p5, ...p95];
    final minP = allPrices.reduce(min);
    final maxP = allPrices.reduce(max);
    final pad = ((maxP - minP) * 0.1).clamp(minP * 0.01, double.infinity);
    final lo = minP - pad;
    final hi = maxP + pad;
    if (hi <= lo) return;

    double xH(int i) => i * segW;
    double xF(int i) => histW + i * segW;
    double y(double p) => chartH * (1.0 - (p - lo) / (hi - lo));

    // ── Forecast bands (drawn first, behind everything) ───────────────────
    _fillBand(canvas, p95, p5, xF, y, primaryColor.withAlpha(20));
    _fillBand(canvas, p75, p25, xF, y, primaryColor.withAlpha(50));

    // ── Median line ───────────────────────────────────────────────────────
    _strokeLine(canvas, p50, xF, y, primaryColor, 2.0);

    // ── Historical line ───────────────────────────────────────────────────
    _strokeLine(canvas, historical, xH, y, outlineColor.withAlpha(160), 1.5);

    // ── "Today" dashed separator ──────────────────────────────────────────
    _dashedVLine(canvas, histW, chartH, outlineColor.withAlpha(70));

    // ── "Today" label ─────────────────────────────────────────────────────
    _drawText(canvas, 'Today', histW, chartH - 14,
        outlineColor.withAlpha(120), center: true);

    // ── Y-axis labels (right side) ────────────────────────────────────────
    const steps = 5;
    for (var i = 0; i <= steps; i++) {
      final frac = i / steps;
      final price = hi - frac * (hi - lo);
      final yPos = frac * chartH;
      final label = '$currency${_fmt(price)}';
      final tp = TextPainter(
        text: TextSpan(
            text: label,
            style: TextStyle(fontSize: 9, color: outlineColor.withAlpha(180))),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: _yAxisW);
      tp.paint(canvas, Offset(chartW + 4, yPos - tp.height / 2));
    }

    // ── Horizon end label ─────────────────────────────────────────────────
    final horizonLabel = '+${foreLen - 1}d';
    _drawText(canvas, horizonLabel, chartW - 2, chartH - 14,
        outlineColor.withAlpha(120),
        center: false);
  }

  void _fillBand(
    Canvas canvas,
    List<double> upper,
    List<double> lower,
    double Function(int) toX,
    double Function(double) toY,
    Color color,
  ) {
    final path = Path();
    path.moveTo(toX(0), toY(upper[0]));
    for (var i = 1; i < upper.length; i++) {
      path.lineTo(toX(i), toY(upper[i]));
    }
    for (var i = lower.length - 1; i >= 0; i--) {
      path.lineTo(toX(i), toY(lower[i]));
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color);
  }

  void _strokeLine(
    Canvas canvas,
    List<double> prices,
    double Function(int) toX,
    double Function(double) toY,
    Color color,
    double width,
  ) {
    if (prices.isEmpty) return;
    final path = Path();
    path.moveTo(toX(0), toY(prices[0]));
    for (var i = 1; i < prices.length; i++) {
      path.lineTo(toX(i), toY(prices[i]));
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..strokeWidth = width
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round);
  }

  void _dashedVLine(Canvas canvas, double x, double h, Color color) {
    const dash = 5.0, gap = 5.0;
    var dy = 0.0;
    while (dy < h) {
      canvas.drawLine(Offset(x, dy), Offset(x, min(dy + dash, h)),
          Paint()..color = color..strokeWidth = 1);
      dy += dash + gap;
    }
  }

  void _drawText(Canvas canvas, String text, double x, double y, Color color,
      {required bool center}) {
    final tp = TextPainter(
      text: TextSpan(
          text: text, style: TextStyle(fontSize: 9, color: color)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(center ? x - tp.width / 2 : x - tp.width, y));
  }

  String _fmt(double p) {
    if (p >= 10000) return p.toStringAsFixed(0);
    if (p >= 1000) return p.toStringAsFixed(1);
    if (p >= 100) return p.toStringAsFixed(2);
    return p.toStringAsFixed(3);
  }

  @override
  bool shouldRepaint(_ForecastPainter old) =>
      old.p50 != p50 || old.historical != historical;
}
