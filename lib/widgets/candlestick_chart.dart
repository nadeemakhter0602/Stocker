import 'package:flutter/material.dart';
import '../models/chart_data.dart';
import '../theme/app_theme.dart';

class CandlestickChart extends StatefulWidget {
  final List<ChartPoint> points;
  final String currency;

  const CandlestickChart({
    super.key,
    required this.points,
    this.currency = r'$',
  });

  @override
  State<CandlestickChart> createState() => _CandlestickChartState();
}

class _CandlestickChartState extends State<CandlestickChart> {
  static const double _defaultStep = 14.0;
  static const double _minStep = 3.0;
  static const double _maxStep = 60.0;
  static const double _yAxisW = 52.0;
  static const double _xAxisH = 24.0;

  double _stepSize = _defaultStep;
  double _scrollOffset = 0.0;
  double _viewW = 0.0;
  int? _selectedIdx;

  // Gesture state
  double _scaleStartStep = _defaultStep;
  double _scaleStartOffset = 0.0;
  double _focalStartLocalX = 0.0;

  bool _scrolledToEnd = false;

  @override
  void didUpdateWidget(covariant CandlestickChart old) {
    super.didUpdateWidget(old);
    if (old.points.length != widget.points.length) {
      _scrolledToEnd = false;
    }
  }

  double get _totalWidth => widget.points.length * _stepSize;

  void _clampOffset() {
    final maxOffset = (_totalWidth - _viewW).clamp(0.0, double.infinity);
    _scrollOffset = _scrollOffset.clamp(0.0, maxOffset);
  }

  ({double min, double max}) get _priceRange {
    if (widget.points.isEmpty) return (min: 0, max: 1);
    double lo = double.infinity, hi = double.negativeInfinity;
    for (final p in widget.points) {
      if (p.low < lo) lo = p.low;
      if (p.high > hi) hi = p.high;
    }
    final pad = (hi - lo) * 0.1;
    return (min: lo - pad, max: hi + pad);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.points.isEmpty) {
      return const Center(child: Text('No chart data'));
    }

    final range = _priceRange;
    final outlineColor = Theme.of(context).colorScheme.outline;
    final surfaceColor = Theme.of(context).colorScheme.surfaceContainerHigh;
    final selected = (_selectedIdx != null && _selectedIdx! < widget.points.length)
        ? widget.points[_selectedIdx!]
        : null;

    return LayoutBuilder(builder: (context, c) {
      final totalH = c.maxHeight;
      final chartH = totalH - _xAxisH;
      _viewW = (c.maxWidth - _yAxisW).clamp(1.0, double.infinity);

      if (!_scrolledToEnd) {
        _scrolledToEnd = true;
        _scrollOffset = (_totalWidth - _viewW).clamp(0.0, double.infinity);
      }

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onScaleStart: (details) {
          _scaleStartStep = _stepSize;
          _scaleStartOffset = _scrollOffset;
          _focalStartLocalX = details.localFocalPoint.dx - _yAxisW;
        },
        onScaleUpdate: (details) {
          if (_scaleStartStep == 0) return;
          final curFocalX = details.localFocalPoint.dx - _yAxisW;
          final newStep =
              (_scaleStartStep * details.scale).clamp(_minStep, _maxStep);

          setState(() {
            _stepSize = newStep;
            // Keep the candle under the focal point fixed on screen
            _scrollOffset =
                (_scaleStartOffset + _focalStartLocalX) / _scaleStartStep *
                    newStep -
                curFocalX;
            _clampOffset();

            if (details.pointerCount == 1) {
              final idx =
                  ((_scrollOffset + curFocalX) / _stepSize).floor();
              _selectedIdx =
                  (idx >= 0 && idx < widget.points.length) ? idx : null;
            } else {
              _selectedIdx = null;
            }
          });
        },
        onScaleEnd: (_) {
          Future.delayed(const Duration(milliseconds: 800), () {
            if (mounted) setState(() => _selectedIdx = null);
          });
        },
        child: Stack(children: [
          Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // Fixed Y-axis
            SizedBox(
              width: _yAxisW,
              child: CustomPaint(
                painter: _YAxisPainter(
                  minY: range.min,
                  maxY: range.max,
                  chartH: chartH,
                  currency: widget.currency,
                  labelColor: outlineColor,
                  gridColor: outlineColor.withAlpha(30),
                ),
              ),
            ),
            // Scrollable/zoomable candle area
            Expanded(
              child: ClipRect(
                child: CustomPaint(
                  painter: _CandlePainter(
                    points: widget.points,
                    minY: range.min,
                    maxY: range.max,
                    chartH: chartH,
                    stepSize: _stepSize,
                    scrollOffset: _scrollOffset,
                    selectedIdx: _selectedIdx,
                    currency: widget.currency,
                    gridColor: outlineColor.withAlpha(30),
                    labelColor: outlineColor,
                    crosshairColor: outlineColor.withAlpha(100),
                  ),
                ),
              ),
            ),
          ]),
          if (selected != null)
            Positioned(
              top: 4,
              left: _yAxisW + 8,
              child: _OhlcOverlay(
                point: selected,
                currency: widget.currency,
                bgColor: surfaceColor.withAlpha(230),
                labelColor: outlineColor,
                valueColor: Theme.of(context).colorScheme.onSurface,
              ),
            ),
        ]),
      );
    });
  }
}

// ──────────────────────────────────────────
// Painters
// ──────────────────────────────────────────

class _YAxisPainter extends CustomPainter {
  final double minY, maxY, chartH;
  final String currency;
  final Color labelColor, gridColor;

  const _YAxisPainter({
    required this.minY,
    required this.maxY,
    required this.chartH,
    required this.currency,
    required this.labelColor,
    required this.gridColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final style = TextStyle(fontSize: 9, color: labelColor);
    const steps = 5;
    for (var i = 0; i <= steps; i++) {
      final frac = i / steps;
      final price = maxY - frac * (maxY - minY);
      final y = frac * chartH;
      final label = '$currency${price >= 1000 ? price.toStringAsFixed(0) : price >= 100 ? price.toStringAsFixed(1) : price.toStringAsFixed(2)}';
      final tp = TextPainter(
        text: TextSpan(text: label, style: style),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width - 2);
      tp.paint(canvas, Offset(2, y - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(_YAxisPainter old) =>
      old.minY != minY || old.maxY != maxY;
}

class _CandlePainter extends CustomPainter {
  final List<ChartPoint> points;
  final double minY, maxY, chartH;
  final double stepSize, scrollOffset;
  final int? selectedIdx;
  final String currency;
  final Color gridColor, labelColor, crosshairColor;

  static const double _wickW = 1.5;

  const _CandlePainter({
    required this.points,
    required this.minY,
    required this.maxY,
    required this.chartH,
    required this.stepSize,
    required this.scrollOffset,
    this.selectedIdx,
    required this.currency,
    required this.gridColor,
    required this.labelColor,
    required this.crosshairColor,
  });

  double _toY(double price) =>
      (1 - (price - minY) / (maxY - minY)) * chartH;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;

    // Horizontal grid lines
    const gridSteps = 5;
    for (var i = 0; i <= gridSteps; i++) {
      final y = (i / gridSteps) * chartH;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    if (stepSize <= 0 || points.isEmpty) return;

    final viewW = size.width;
    final firstIdx = ((scrollOffset / stepSize).floor() - 1).clamp(0, points.length - 1);
    final lastIdx = (((scrollOffset + viewW) / stepSize).ceil() + 1).clamp(0, points.length - 1);
    final bodyW = (stepSize * 0.55).clamp(1.5, 24.0);

    for (var i = firstIdx; i <= lastIdx; i++) {
      final p = points[i];
      final x = i * stepSize - scrollOffset + stepSize / 2;
      final color = p.isGreen ? AppTheme.positiveColor : AppTheme.negativeColor;

      final openY = _toY(p.open);
      final closeY = _toY(p.close);
      final highY = _toY(p.high);
      final lowY = _toY(p.low);

      // Wick
      canvas.drawLine(
        Offset(x, highY),
        Offset(x, lowY),
        Paint()
          ..color = color
          ..strokeWidth = _wickW,
      );

      // Body
      final bodyTop = p.isGreen ? closeY : openY;
      final bodyBot = p.isGreen ? openY : closeY;
      final bodyH = (bodyBot - bodyTop).abs().clamp(1.0, double.infinity);
      canvas.drawRect(
        Rect.fromLTWH(x - bodyW / 2, bodyTop, bodyW, bodyH),
        Paint()..color = color,
      );
    }

    // X-axis date labels
    final labelStyle = TextStyle(fontSize: 9, color: labelColor);
    const months = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final visibleCount = (viewW / stepSize).ceil();
    final labelInterval = visibleCount > 100 ? 30 : visibleCount > 30 ? 10 : visibleCount > 10 ? 5 : 2;

    for (var i = firstIdx; i <= lastIdx; i++) {
      if (i % labelInterval != 0) continue;
      final d = points[i].date;
      final x = i * stepSize - scrollOffset + stepSize / 2;
      final tp = TextPainter(
        text: TextSpan(text: '${months[d.month]} ${d.day}', style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, chartH + 4));
    }

    // Vertical crosshair
    if (selectedIdx != null && selectedIdx! < points.length) {
      final x = selectedIdx! * stepSize - scrollOffset + stepSize / 2;
      if (x >= 0 && x <= viewW) {
        canvas.drawLine(
          Offset(x, 0),
          Offset(x, chartH),
          Paint()
            ..color = crosshairColor
            ..strokeWidth = 1,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_CandlePainter old) =>
      old.points != points ||
      old.selectedIdx != selectedIdx ||
      old.minY != minY ||
      old.maxY != maxY ||
      old.stepSize != stepSize ||
      old.scrollOffset != scrollOffset;
}

// ──────────────────────────────────────────
// OHLC overlay card
// ──────────────────────────────────────────

class _OhlcOverlay extends StatelessWidget {
  final ChartPoint point;
  final String currency;
  final Color bgColor, labelColor, valueColor;

  const _OhlcOverlay({
    required this.point,
    required this.currency,
    required this.bgColor,
    required this.labelColor,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    String fmt(double v) =>
        '$currency${v.toStringAsFixed(v >= 1000 ? 0 : 2)}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Field('O', fmt(point.open), labelColor, valueColor),
          const SizedBox(width: 8),
          _Field('H', fmt(point.high), labelColor, valueColor),
          const SizedBox(width: 8),
          _Field('L', fmt(point.low), labelColor, valueColor),
          const SizedBox(width: 8),
          _Field('C', fmt(point.close), labelColor, valueColor),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final String label, value;
  final Color labelColor, valueColor;

  const _Field(this.label, this.value, this.labelColor, this.valueColor);

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(children: [
        TextSpan(
          text: '$label ',
          style: TextStyle(fontSize: 10, color: labelColor),
        ),
        TextSpan(
          text: value,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: valueColor,
          ),
        ),
      ]),
    );
  }
}
