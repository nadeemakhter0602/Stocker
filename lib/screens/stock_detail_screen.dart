import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';
import '../models/chart_data.dart';
import '../models/news_item.dart';
import '../models/quant_models.dart';
import '../models/stock_quote.dart';
import '../services/quant_service.dart';
import '../widgets/forecast_chart.dart';
import '../providers/quote_provider.dart';
import '../providers/watchlist_provider.dart';
import '../widgets/change_badge.dart';
import '../widgets/error_view.dart';
import '../widgets/price_chart.dart';
import '../widgets/quote_type_badge.dart';
import '../widgets/stat_card.dart';


class StockDetailScreen extends StatefulWidget {
  final String symbol;

  const StockDetailScreen({super.key, required this.symbol});

  @override
  State<StockDetailScreen> createState() => _StockDetailScreenState();
}

class _StockDetailScreenState extends State<StockDetailScreen>
    with SingleTickerProviderStateMixin {
  String _chartRange = '1Y';
  late TabController _tabController;

  // Forecast tab state — fixed 7-day horizon
  static const _horizonDays = 7;
  SimResult? _simResult;
  ArimaResult? _arimaResult;
  GarchArimaResult? _garchArimaResult;
  bool _simLoading = false;
  bool _arimaLoading = false;
  bool _garchArimaLoading = false;
  int _lookbackDays = 252; // 0 = max
  bool _useEwma = false;

  // 1W/1M/1Y slice from daily data; Max uses weekly data (full history)
  static const _rangeSliceDays = {'1W': 5, '1M': 21, '1Y': 0};

  List<ChartPoint> _sliceChart(List<ChartPoint> pts) {
    final days = _rangeSliceDays[_chartRange] ?? 0;
    if (days == 0 || pts.length <= days) return pts;
    return pts.sublist(pts.length - days);
  }

  void _onRangeChanged(String range) {
    setState(() => _chartRange = range);
    if (range == 'Max') {
      final provider = context.read<QuoteProvider>();
      if (provider.getChartState(widget.symbol, '1wk') == QuoteState.idle) {
        provider.fetchQuote(widget.symbol, interval: '1wk', range: 'max');
      }
    }
  }

  ({double change, double changePct}) _intervalChange(
      List<ChartPoint> sliced, double currentPrice) {
    if (sliced.isEmpty) return (change: 0, changePct: 0);
    final first = sliced.first.close;
    if (first == 0) return (change: 0, changePct: 0);
    final change = currentPrice - first;
    return (change: change, changePct: (change / first) * 100);
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (_tabController.index == 1) {
        _maybeRunSimulation();
      }
      if (_tabController.index == 3) {
        final quote = context.read<QuoteProvider>().getQuote(widget.symbol);
        context.read<QuoteProvider>().fetchNews(
              widget.symbol,
              name: quote?.shortName,
            );
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<QuoteProvider>().fetchQuote(widget.symbol,
          interval: '1d', range: '1y');
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _maybeRunSimulation() {
    if (_simResult != null && _arimaResult != null && _garchArimaResult != null) return;
    final pts = context.read<QuoteProvider>().getChart(widget.symbol, '1d');
    if (pts.isEmpty) return;
    if (_simResult == null) _runGbm(pts);
    if (_arimaResult == null) _runArima(pts);
    if (_garchArimaResult == null) _runGarchArima(pts);
  }

  Future<void> _runGbm(List<ChartPoint> pts) async {
    if (_simLoading) return;
    setState(() => _simLoading = true);
    final result = await QuantService.simulate(pts, _horizonDays,
        lookbackDays: _lookbackDays, useEwma: _useEwma);
    if (mounted) {
      setState(() {
        _simResult = result;
        _simLoading = false;
      });
    }
  }

  Future<void> _runArima(List<ChartPoint> pts) async {
    if (_arimaLoading) return;
    setState(() => _arimaLoading = true);
    final result = await QuantService.arima(pts, _horizonDays,
        lookbackDays: _lookbackDays, useEwma: _useEwma);
    if (mounted) {
      setState(() {
        _arimaResult = result;
        _arimaLoading = false;
      });
    }
  }

  Future<void> _runGarchArima(List<ChartPoint> pts) async {
    if (_garchArimaLoading) return;
    setState(() => _garchArimaLoading = true);
    final result = await QuantService.garchArima(pts, _horizonDays,
        lookbackDays: _lookbackDays, useEwma: _useEwma);
    if (mounted) {
      setState(() {
        _garchArimaResult = result;
        _garchArimaLoading = false;
      });
    }
  }

  void _resetAndRerunForecast(List<ChartPoint> pts) {
    setState(() {
      _simResult = null;
      _arimaResult = null;
      _garchArimaResult = null;
    });
    _runGbm(pts);
    _runArima(pts);
    _runGarchArima(pts);
  }

  String _formatLargeNumber(double? value) {
    if (value == null) return 'N/A';
    return NumberFormat.compact().format(value);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<QuoteProvider, WatchlistProvider>(
      builder: (context, quoteProvider, watchlistProvider, _) {
        final quoteState = quoteProvider.getState(widget.symbol);
        final quote = quoteProvider.getQuote(widget.symbol);
        final dailyChart = quoteProvider.getChart(widget.symbol, '1d');
        final weeklyChart = quoteProvider.getChart(widget.symbol, '1wk');
        final isMax = _chartRange == 'Max';
        final rawChart = isMax ? weeklyChart : dailyChart;
        final chartState = quoteProvider.getChartState(
            widget.symbol, isMax ? '1wk' : '1d');
        final sliced = _sliceChart(rawChart);
        final inWatchlist = watchlistProvider.contains(widget.symbol);

        final (:change, :changePct) =
            _intervalChange(sliced, quote?.price ?? 0);

        return Scaffold(
          appBar: AppBar(
            title: Row(
              children: [
                Text(
                  widget.symbol,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (quote != null) ...[
                  const SizedBox(width: 8),
                  QuoteTypeBadge(quoteType: quote.quoteType),
                ],
              ],
            ),
            actions: [
              IconButton(
                icon: Icon(
                  inWatchlist
                      ? Icons.bookmark_rounded
                      : Icons.bookmark_border_rounded,
                  color: inWatchlist
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
                onPressed: () => watchlistProvider.toggle(widget.symbol),
                tooltip: inWatchlist
                    ? 'Remove from watchlist'
                    : 'Add to watchlist',
              ),
              const SizedBox(width: 4),
            ],
            bottom: TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: 'Overview'),
                Tab(text: 'Forecast'),
                Tab(text: 'Technical'),
                Tab(text: 'News'),
              ],
            ),
          ),
          body: _buildBody(context, quoteState, chartState, quote, sliced,
              dailyChart, quoteProvider, change, changePct),
        );
      },
    );
  }

  Widget _buildBody(
    BuildContext context,
    QuoteState quoteState,
    QuoteState chartState,
    StockQuote? quote,
    List<ChartPoint> sliced,
    List<ChartPoint> dailyChart,
    QuoteProvider quoteProvider,
    double change,
    double changePct,
  ) {
    if (quoteState == QuoteState.loading && quote == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (quoteState == QuoteState.error) {
      return ErrorView(
        message: quoteProvider.getError(widget.symbol),
        onRetry: () => quoteProvider.fetchQuote(widget.symbol,
            interval: '1d', range: '1y'),
      );
    }
    if (quote == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final currencySymbol = quote.currency == 'INR' ? '₹' : r'$';

    return Column(
      children: [
        _buildPriceHeader(context, quote, currencySymbol, change, changePct),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildOverviewTab(
                  context, quote, sliced, chartState, currencySymbol, change),
              _buildForecastTab(context, dailyChart, currencySymbol),
              _buildTechnicalTab(context, quote, dailyChart, currencySymbol),
              _buildNewsTab(context, quoteProvider),
            ],
          ),
        ),
      ],
    );
  }

  // ─── Price Header ───────────────────────────────────────────────────────────

  Widget _buildPriceHeader(BuildContext context, StockQuote quote, String cs,
      double change, double changePct) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outline.withAlpha(30),
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  quote.shortName,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '$cs${quote.price.toStringAsFixed(2)}',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
          ),
          ChangeBadge(
            change: change,
            changePercent: changePct,
          ),
        ],
      ),
    );
  }

  // ─── Overview Tab ────────────────────────────────────────────────────────────

  Widget _buildOverviewTab(
    BuildContext context,
    StockQuote quote,
    List<ChartPoint> sliced,
    QuoteState chartState,
    String cs,
    double change,
  ) {
    final isEtf = quote.quoteType.toUpperCase() == 'ETF';

    return RefreshIndicator(
      onRefresh: () => context
          .read<QuoteProvider>()
          .fetchQuote(widget.symbol, interval: '1d', range: '1y'),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Range chips
          Row(
            children: ['1W', '1M', '1Y', 'Max'].map((label) {
              final selected = _chartRange == label;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(label),
                  selected: selected,
                  visualDensity: VisualDensity.compact,
                  labelStyle: TextStyle(
                    fontSize: 12,
                    fontWeight:
                        selected ? FontWeight.w700 : FontWeight.normal,
                  ),
                  onSelected: (_) => _onRangeChanged(label),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),

          // Chart
          SizedBox(
            height: 240,
            child: chartState == QuoteState.loading
                ? const Center(child: CircularProgressIndicator())
                : _buildChart(sliced, change >= 0, cs),
          ),
          const SizedBox(height: 24),

          // Key Statistics
          Text(
            'Key Statistics',
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 2.5,
            children: [
              StatCard(
                label: 'Open',
                value: quote.open != null
                    ? '$cs${quote.open!.toStringAsFixed(2)}'
                    : 'N/A',
              ),
              StatCard(
                label: 'Prev Close',
                value: quote.previousClose != null
                    ? '$cs${quote.previousClose!.toStringAsFixed(2)}'
                    : 'N/A',
              ),
              StatCard(
                label: 'Day High',
                value: quote.dayHigh != null
                    ? '$cs${quote.dayHigh!.toStringAsFixed(2)}'
                    : 'N/A',
              ),
              StatCard(
                label: 'Day Low',
                value: quote.dayLow != null
                    ? '$cs${quote.dayLow!.toStringAsFixed(2)}'
                    : 'N/A',
              ),
              StatCard(
                label: '52W High',
                value: quote.fiftyTwoWeekHigh != null
                    ? '$cs${quote.fiftyTwoWeekHigh!.toStringAsFixed(2)}'
                    : 'N/A',
              ),
              StatCard(
                label: '52W Low',
                value: quote.fiftyTwoWeekLow != null
                    ? '$cs${quote.fiftyTwoWeekLow!.toStringAsFixed(2)}'
                    : 'N/A',
              ),
              StatCard(
                label: 'Volume',
                value: _formatLargeNumber(quote.volume),
              ),
              isEtf
                  ? StatCard(
                      label: 'Total Assets',
                      value: _formatLargeNumber(quote.marketCap),
                    )
                  : StatCard(
                      label: 'Market Cap',
                      value: _formatLargeNumber(quote.marketCap),
                    ),
              if (!isEtf)
                StatCard(
                  label: 'P/E Ratio',
                  value: quote.trailingPE != null
                      ? quote.trailingPE!.toStringAsFixed(2)
                      : 'N/A',
                ),
            ],
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildChart(
      List<ChartPoint> chartPoints, bool isPositive, String currency) {
    if (chartPoints.isEmpty) {
      return const Center(child: Text('No chart data'));
    }
    return PriceChart(
      points: chartPoints,
      isPositive: isPositive,
      currency: currency,
    );
  }

  // ─── Technical Analysis Tab ─────────────────────────────────────────────────

  Widget _buildTechnicalTab(BuildContext context, StockQuote quote,
      List<ChartPoint> pts, String cs) {
    if (pts.isEmpty) {
      return const Center(child: Text('Loading chart data…'));
    }

    final price = quote.price;
    final ma20 = _sma(pts, 20);
    final ma50 = _sma(pts, 50);
    final ma200 = _sma(pts, 200);
    final rsiVal = _rsi(pts);
    final (:macdLine, :signalLine, :histogram) = _macd(pts);
    final volRatio = _volumeRatio(pts);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _sectionTitle(context, 'Moving Averages'),
        const SizedBox(height: 8),
        _maCard(context, 'MA 20', ma20, price, cs),
        _maCard(context, 'MA 50', ma50, price, cs),
        _maCard(context, 'MA 200', ma200, price, cs),
        const SizedBox(height: 20),

        _sectionTitle(context, 'RSI (14)'),
        const SizedBox(height: 8),
        if (rsiVal != null) _rsiCard(context, rsiVal),
        if (rsiVal == null) _naCard(context, 'RSI (14)', 'Not enough data'),
        const SizedBox(height: 20),

        _sectionTitle(context, 'MACD (12/26/9)'),
        const SizedBox(height: 8),
        if (macdLine != null)
          _macdCard(context, macdLine, signalLine!, histogram!),
        if (macdLine == null) _naCard(context, 'MACD', 'Not enough data'),
        const SizedBox(height: 20),

        _sectionTitle(context, 'Volume'),
        const SizedBox(height: 8),
        if (volRatio != null) _volumeCard(context, volRatio, quote),
        if (volRatio == null) _naCard(context, 'Volume', 'No volume data'),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _sectionTitle(BuildContext context, String title) => Text(
        title,
        style: Theme.of(context)
            .textTheme
            .titleSmall
            ?.copyWith(fontWeight: FontWeight.w700),
      );

  Widget _maCard(
      BuildContext context, String label, double? ma, double price, String cs) {
    if (ma == null) return _naCard(context, label, 'Not enough data');
    final diff = price - ma;
    final pct = (diff / ma) * 100;
    final isBullish = price > ma;
    return _IndicatorCard(
      label: label,
      value: '$cs${ma.toStringAsFixed(ma >= 100 ? 2 : 4)}',
      subtitle:
          '${isBullish ? '+' : ''}${pct.toStringAsFixed(2)}% from price',
      signal: isBullish ? 'Bullish' : 'Bearish',
      isBullish: isBullish,
    );
  }

  Widget _rsiCard(BuildContext context, double rsi) {
    final String signal;
    final bool? isBullish;
    if (rsi < 30) {
      signal = 'Oversold';
      isBullish = true;
    } else if (rsi > 70) {
      signal = 'Overbought';
      isBullish = false;
    } else {
      signal = 'Neutral';
      isBullish = null;
    }
    return _IndicatorCard(
      label: 'RSI (14)',
      value: rsi.toStringAsFixed(1),
      subtitle: rsi < 30
          ? 'Below 30 — potential buy signal'
          : rsi > 70
              ? 'Above 70 — potential sell signal'
              : '30–70 normal range',
      signal: signal,
      isBullish: isBullish,
    );
  }

  Widget _macdCard(BuildContext context, double macdLine, double signalLine,
      double histogram) {
    final isBullish = macdLine > signalLine;
    return _IndicatorCard(
      label: 'MACD',
      value: macdLine.toStringAsFixed(4),
      subtitle:
          'Signal: ${signalLine.toStringAsFixed(4)}  Histogram: ${histogram > 0 ? '+' : ''}${histogram.toStringAsFixed(4)}',
      signal: isBullish ? 'Bullish' : 'Bearish',
      isBullish: isBullish,
    );
  }

  Widget _volumeCard(
      BuildContext context, double ratio, StockQuote quote) {
    final isHigh = ratio >= 1.5;
    final isLow = ratio <= 0.5;
    return _IndicatorCard(
      label: 'Volume vs Avg(20)',
      value: '${ratio.toStringAsFixed(2)}×',
      subtitle: isHigh
          ? 'Unusually high volume'
          : isLow
              ? 'Unusually low volume'
              : 'Normal volume',
      signal: isHigh ? 'High' : isLow ? 'Low' : 'Normal',
      isBullish: null,
    );
  }

  Widget _naCard(BuildContext context, String label, String reason) {
    return _IndicatorCard(
      label: label,
      value: 'N/A',
      subtitle: reason,
      signal: '—',
      isBullish: null,
    );
  }

  // ─── News Tab ───────────────────────────────────────────────────────────────

  Widget _buildNewsTab(BuildContext context, QuoteProvider provider) {
    final state = provider.getNewsState(widget.symbol);
    final news = provider.getNews(widget.symbol);

    if (state == QuoteState.idle || state == QuoteState.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state == QuoteState.error || news.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.newspaper_rounded,
                size: 48,
                color: Theme.of(context).colorScheme.outline.withAlpha(80)),
            const SizedBox(height: 12),
            Text(
              'No news available',
              style: TextStyle(
                  color: Theme.of(context).colorScheme.outline),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: news.length,
      separatorBuilder: (context, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) => _NewsCard(item: news[i]),
    );
  }

  // ─── Technical indicator calculations ───────────────────────────────────────

  // ─── Forecast Tab ─────────────────────────────────────────────────────────

  // Lookback options: label → lookbackDays (0 = max)
  static const _lookbackOptions = {
    '1Y': 252,
    '2Y': 504,
    '5Y': 1260,
    'Max': 0,
  };

  Widget _buildForecastTab(
      BuildContext context, List<ChartPoint> dailyPts, String cs) {
    if (dailyPts.length < 30) {
      return const Center(child: Text('Not enough history to simulate'));
    }

    // Kick off models if not yet started
    if (!_simLoading && _simResult == null) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) { if (mounted) _runGbm(dailyPts); });
    }
    if (!_arimaLoading && _arimaResult == null) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) { if (mounted) _runArima(dailyPts); });
    }
    if (!_garchArimaLoading && _garchArimaResult == null) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) { if (mounted) _runGarchArima(dailyPts); });
    }

    final hist = dailyPts
        .sublist((dailyPts.length - 30).clamp(0, dailyPts.length))
        .map((p) => p.close)
        .toList();

    String priceFmt(double p) =>
        '$cs${p.toStringAsFixed(p >= 1000 ? 1 : 2)}';
    String pct2Fmt(double p) => '${(p * 100).toStringAsFixed(1)}%';

    final lookbackLabel = _lookbackOptions.entries
        .firstWhere((e) => e.value == _lookbackDays,
            orElse: () => const MapEntry('1Y', 252))
        .key;
    final volLabel = _useEwma ? 'EWMA σ' : 'Hist σ';
    final gbmTitle =
        'Monte Carlo GBM  (10 000 paths, 7-day, $lookbackLabel, $volLabel)';
    final arimaTitle = 'ARIMA(1,1,1)  (7-day, $lookbackLabel, $volLabel)';
    final garchTitle = 'GARCH(1,1)-ARIMA(1,1,1)  (7-day, $lookbackLabel, $volLabel)';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [

        // ── Settings row ─────────────────────────────────────────────────
        Row(
          children: [
            // Lookback chips
            ..._lookbackOptions.entries.map((entry) {
              final selected = _lookbackDays == entry.value;
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(entry.key),
                  selected: selected,
                  visualDensity: VisualDensity.compact,
                  labelStyle: TextStyle(
                    fontSize: 12,
                    fontWeight:
                        selected ? FontWeight.w700 : FontWeight.normal,
                  ),
                  onSelected: (_) {
                    if (_lookbackDays != entry.value) {
                      setState(() => _lookbackDays = entry.value);
                      _resetAndRerunForecast(dailyPts);
                    }
                  },
                ),
              );
            }),
            const Spacer(),
            // EWMA toggle
            Text('EWMA σ',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(width: 4),
            Switch(
              value: _useEwma,
              onChanged: (v) {
                setState(() => _useEwma = v);
                _resetAndRerunForecast(dailyPts);
              },
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ],
        ),
        const SizedBox(height: 12),

        // ══ GBM Monte Carlo ═══════════════════════════════════════════════
        _sectionTitle(context, gbmTitle),
        const SizedBox(height: 10),
        if (_simLoading || _simResult == null)
          const SizedBox(
              height: 200,
              child: Center(child: CircularProgressIndicator()))
        else ...[
          SizedBox(
            height: 220,
            child: ForecastChart(
              historical: hist,
              p5: _simResult!.p5,
              p25: _simResult!.p25,
              p50: _simResult!.p50,
              p75: _simResult!.p75,
              p95: _simResult!.p95,
              currency: cs,
            ),
          ),
          _chartLegend(context),
          const SizedBox(height: 8),
          _ForecastCard(
            label: 'Probability of gain (7d)',
            value: pct2Fmt(_simResult!.probProfit),
            sub: 'fraction of paths ending above today',
            isBullish: _simResult!.probProfit >= 0.5,
          ),
          const SizedBox(height: 4),
          // Day-by-day table
          _DayTable(
            header: const ['Day', 'Bear (P5)', 'Base (P50)', 'Bull (P95)'],
            rows: List.generate(_horizonDays, (i) {
              final d = i + 1;
              final p5 = _simResult!.p5[d];
              final p50 = _simResult!.p50[d];
              final p95 = _simResult!.p95[d];
              return [
                '+${d}d',
                priceFmt(p5),
                priceFmt(p50),
                priceFmt(p95),
              ];
            }),
            pct: List.generate(_horizonDays, (i) {
              final d = i + 1;
              return _simResult!.p50[d] >= _simResult!.currentPrice;
            }),
          ),
        ],
        const SizedBox(height: 24),

        // ══ ARIMA(1,1,1) ══════════════════════════════════════════════════
        _sectionTitle(context, arimaTitle),
        const SizedBox(height: 10),
        if (_arimaLoading || _arimaResult == null)
          const SizedBox(
              height: 200,
              child: Center(child: CircularProgressIndicator()))
        else ...[
          SizedBox(
            height: 220,
            child: ForecastChart(
              historical: hist,
              p5: _arimaResult!.ci95Lower,
              p25: _arimaResult!.ci80Lower,
              p50: _arimaResult!.forecast,
              p75: _arimaResult!.ci80Upper,
              p95: _arimaResult!.ci95Upper,
              currency: cs,
            ),
          ),
          _chartLegend(context, inner: '80% CI', outer: '95% CI'),
          const SizedBox(height: 12),
          // Day-by-day table
          _DayTable(
            header: const ['Day', '95% Low', 'Forecast', '95% High'],
            rows: List.generate(_horizonDays, (i) {
              final d = i + 1;
              return [
                '+${d}d',
                priceFmt(_arimaResult!.ci95Lower[d]),
                priceFmt(_arimaResult!.forecast[d]),
                priceFmt(_arimaResult!.ci95Upper[d]),
              ];
            }),
            pct: List.generate(_horizonDays, (i) {
              final d = i + 1;
              return _arimaResult!.forecast[d] >= _arimaResult!.forecast[0];
            }),
          ),
          const SizedBox(height: 8),
          _ForecastCard(
            label: 'Probability of gain (7d)',
            value: pct2Fmt(_arimaResult!.probProfit),
            sub: 'P(price > today) from normal distribution',
            isBullish: _arimaResult!.probProfit >= 0.5,
          ),
          _ForecastCard(
            label: 'AR coefficient φ',
            value: _arimaResult!.phi.toStringAsFixed(4),
            sub: _arimaResult!.phi > 0
                ? 'positive autocorrelation (momentum)'
                : 'negative autocorrelation (mean-reversion)',
            isBullish: null,
          ),
          _ForecastCard(
            label: 'MA coefficient θ',
            value: _arimaResult!.theta.toStringAsFixed(4),
            sub: 'shock persistence in model',
            isBullish: null,
          ),
          _ForecastCard(
            label: 'Residual σ (daily)',
            value: pct2Fmt(_arimaResult!.sigma),
            sub: 'estimated daily log-return noise',
            isBullish: null,
          ),
        ],
        const SizedBox(height: 24),

        // ══ GARCH(1,1)-ARIMA(1,1,1) ═══════════════════════════════════════
        _sectionTitle(context, garchTitle),
        const SizedBox(height: 10),
        if (_garchArimaLoading || _garchArimaResult == null)
          const SizedBox(
              height: 200,
              child: Center(child: CircularProgressIndicator()))
        else ...[
          SizedBox(
            height: 220,
            child: ForecastChart(
              historical: hist,
              p5: _garchArimaResult!.ci95Lower,
              p25: _garchArimaResult!.ci80Lower,
              p50: _garchArimaResult!.forecast,
              p75: _garchArimaResult!.ci80Upper,
              p95: _garchArimaResult!.ci95Upper,
              currency: cs,
            ),
          ),
          _chartLegend(context, inner: '80% CI', outer: '95% CI'),
          const SizedBox(height: 12),
          _DayTable(
            header: const ['Day', '95% Low', 'Forecast', '95% High'],
            rows: List.generate(_horizonDays, (i) {
              final d = i + 1;
              return [
                '+${d}d',
                priceFmt(_garchArimaResult!.ci95Lower[d]),
                priceFmt(_garchArimaResult!.forecast[d]),
                priceFmt(_garchArimaResult!.ci95Upper[d]),
              ];
            }),
            pct: List.generate(_horizonDays, (i) {
              final d = i + 1;
              return _garchArimaResult!.forecast[d] >= _garchArimaResult!.forecast[0];
            }),
          ),
          const SizedBox(height: 8),
          _ForecastCard(
            label: 'Probability of gain (7d)',
            value: pct2Fmt(_garchArimaResult!.probProfit),
            sub: 'P(price > today) with GARCH variance',
            isBullish: _garchArimaResult!.probProfit >= 0.5,
          ),
          _ForecastCard(
            label: 'Cond. vol day+1 / day+7 (ann.)',
            value:
                '${pct2Fmt(_garchArimaResult!.condVol[0])} / ${pct2Fmt(_garchArimaResult!.condVol[_horizonDays - 1])}',
            sub: 'GARCH(1,1) forward volatility — converges to long-run mean',
            isBullish: null,
          ),
          _ForecastCard(
            label: 'AR φ  /  MA θ',
            value:
                '${_garchArimaResult!.phi.toStringAsFixed(3)} / ${_garchArimaResult!.theta.toStringAsFixed(3)}',
            sub: 'ARIMA(1,1,1) mean-equation parameters',
            isBullish: null,
          ),
          _ForecastCard(
            label: 'GARCH α / β  (α+β=${(_garchArimaResult!.alpha + _garchArimaResult!.beta).toStringAsFixed(3)})',
            value:
                '${_garchArimaResult!.alpha.toStringAsFixed(3)} / ${_garchArimaResult!.beta.toStringAsFixed(3)}',
            sub: 'α = shock weight, β = persistence. α+β < 1 → stationary',
            isBullish: (_garchArimaResult!.alpha + _garchArimaResult!.beta) < 0.98
                ? true
                : null,
          ),
        ],
        const SizedBox(height: 24),

        // ══ Risk metrics ══════════════════════════════════════════════════
        if (_simResult != null) ...[
          _sectionTitle(context, 'Risk Metrics'),
          const SizedBox(height: 8),
          _ForecastCard(
            label: 'Annualised Volatility',
            value: pct2Fmt(_simResult!.stats.annualizedVol),
            sub: 'daily σ × √252',
            isBullish: null,
          ),
          _ForecastCard(
            label: 'Sharpe Ratio',
            value: _simResult!.stats.sharpeRatio.toStringAsFixed(2),
            sub: 'vs 5% risk-free rate',
            isBullish: _simResult!.stats.sharpeRatio > 1
                ? true
                : _simResult!.stats.sharpeRatio < 0
                    ? false
                    : null,
          ),
          _ForecastCard(
            label: 'Sortino Ratio',
            value: _simResult!.stats.sortinoRatio.toStringAsFixed(2),
            sub: 'downside deviation only',
            isBullish: _simResult!.stats.sortinoRatio > 1
                ? true
                : _simResult!.stats.sortinoRatio < 0
                    ? false
                    : null,
          ),
          _ForecastCard(
            label: 'Max Drawdown',
            value: '-${pct2Fmt(_simResult!.stats.maxDrawdown)}',
            sub: 'worst peak-to-trough (full history)',
            isBullish: _simResult!.stats.maxDrawdown < 0.15
                ? true
                : _simResult!.stats.maxDrawdown > 0.4
                    ? false
                    : null,
          ),
          _ForecastCard(
            label: 'Current Drawdown',
            value: '-${pct2Fmt(_simResult!.stats.currentDrawdown)}',
            sub: 'from all-time high',
            isBullish: _simResult!.stats.currentDrawdown < 0.05
                ? true
                : _simResult!.stats.currentDrawdown > 0.2
                    ? false
                    : null,
          ),
          const SizedBox(height: 20),
          _sectionTitle(context, 'Value at Risk (1-day, historical)'),
          const SizedBox(height: 8),
          _ForecastCard(
            label: 'VaR 95%',
            value: '-${priceFmt(_simResult!.stats.var95)}',
            sub: '5% chance of exceeding this loss in a day',
            isBullish: false,
          ),
          _ForecastCard(
            label: 'VaR 99%',
            value: '-${priceFmt(_simResult!.stats.var99)}',
            sub: '1% tail loss threshold',
            isBullish: false,
          ),
          _ForecastCard(
            label: 'Expected Shortfall (CVaR 95%)',
            value: '-${priceFmt(_simResult!.stats.cvar95)}',
            sub: 'avg loss when VaR is breached',
            isBullish: false,
          ),
          const SizedBox(height: 20),
          _sectionTitle(context, 'Position Sizing'),
          const SizedBox(height: 8),
          _ForecastCard(
            label: 'Kelly Criterion (¼ Kelly)',
            value: pct2Fmt(_simResult!.stats.kellyFraction),
            sub: 'suggested portfolio allocation',
            isBullish: null,
          ),
          const SizedBox(height: 12),
        ],

        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '⚠  GBM assumes log-normal returns & constant volatility. '
            'ARIMA assumes linear autocorrelation in log-returns. '
            'GARCH-ARIMA models volatility clustering but assumes Gaussian errors. '
            'None account for jumps, fat tails, or regime changes. '
            'Not financial advice.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                  fontSize: 11,
                ),
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _chartLegend(BuildContext context,
      {String inner = 'P25–P75', String outer = 'P5–P95'}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        _Legend(
            color: Theme.of(context).colorScheme.primary.withAlpha(20),
            label: outer),
        const SizedBox(width: 12),
        _Legend(
            color: Theme.of(context).colorScheme.primary.withAlpha(50),
            label: inner),
        const SizedBox(width: 12),
        _Legend(
            color: Theme.of(context).colorScheme.primary,
            label: 'Forecast',
            line: true),
      ]),
    );
  }

  static double? _sma(List<ChartPoint> pts, int n) {
    if (pts.length < n) return null;
    final slice = pts.sublist(pts.length - n);
    return slice.map((p) => p.close).reduce((a, b) => a + b) / n;
  }

  static List<double> _ema(List<double> data, int period) {
    if (data.isEmpty) return [];
    final k = 2.0 / (period + 1);
    final result = <double>[data[0]];
    for (var i = 1; i < data.length; i++) {
      result.add(data[i] * k + result.last * (1 - k));
    }
    return result;
  }

  static double? _rsi(List<ChartPoint> pts, {int period = 14}) {
    if (pts.length < period + 1) return null;
    final recent = pts.sublist(pts.length - period - 1);
    double gains = 0, losses = 0;
    for (var i = 1; i < recent.length; i++) {
      final diff = recent[i].close - recent[i - 1].close;
      if (diff > 0) {
        gains += diff;
      } else {
        losses += diff.abs();
      }
    }
    if (losses == 0) return 100.0;
    return 100 - 100 / (1 + gains / losses);
  }

  static ({double? macdLine, double? signalLine, double? histogram}) _macd(
      List<ChartPoint> pts) {
    if (pts.length < 35) {
      return (macdLine: null, signalLine: null, histogram: null);
    }
    final closes = pts.map((p) => p.close).toList();
    final ema12 = _ema(closes, 12);
    final ema26 = _ema(closes, 26);
    final macdValues = List.generate(closes.length, (i) => ema12[i] - ema26[i]);
    final signalValues = _ema(macdValues, 9);
    final ml = macdValues.last;
    final sl = signalValues.last;
    return (macdLine: ml, signalLine: sl, histogram: ml - sl);
  }

  static double? _volumeRatio(List<ChartPoint> pts, {int period = 20}) {
    if (pts.length < period + 1) return null;
    final last = pts.last;
    if (last.volume == null) return null;
    final recent = pts.sublist(pts.length - period - 1, pts.length - 1);
    final vols = recent.map((p) => p.volume).whereType<double>().toList();
    if (vols.isEmpty) return null;
    final avgVol = vols.reduce((a, b) => a + b) / vols.length;
    if (avgVol == 0) return null;
    return last.volume! / avgVol;
  }
}

// ─── Reusable widgets ─────────────────────────────────────────────────────────

class _DayTable extends StatelessWidget {
  final List<String> header;
  final List<List<String>> rows;
  final List<bool> pct; // true = row base value is bullish

  const _DayTable(
      {required this.header, required this.rows, required this.pct});

  @override
  Widget build(BuildContext context) {
    final outline = Theme.of(context).colorScheme.outline;
    final surface = Theme.of(context).colorScheme.surfaceContainerHigh;
    final textStyle = Theme.of(context).textTheme.bodySmall;

    return Table(
      border: TableBorder.all(color: outline.withAlpha(30), width: 0.5,
          borderRadius: BorderRadius.circular(8)),
      columnWidths: const {0: IntrinsicColumnWidth()},
      children: [
        // Header
        TableRow(
          decoration: BoxDecoration(color: surface),
          children: header
              .map((h) => Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    child: Text(h,
                        style: textStyle?.copyWith(
                            fontWeight: FontWeight.w700, color: outline),
                        textAlign: TextAlign.right),
                  ))
              .toList(),
        ),
        // Data rows
        ...List.generate(rows.length, (i) {
          final row = rows[i];
          final isBull = pct[i];
          final valueColor =
              isBull ? const Color(0xFF00C853) : const Color(0xFFFF1744);
          return TableRow(
            children: List.generate(row.length, (j) {
              final isDay = j == 0;
              return Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 6),
                child: Text(
                  row[j],
                  style: textStyle?.copyWith(
                    color: isDay ? outline : (j == 2 ? valueColor : null),
                    fontWeight: j == 2 ? FontWeight.w600 : null,
                  ),
                  textAlign: TextAlign.right,
                ),
              );
            }),
          );
        }),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;
  final bool line;

  const _Legend({required this.color, required this.label, this.line = false});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (line)
        Container(width: 16, height: 2, color: color)
      else
        Container(
            width: 12,
            height: 12,
            decoration:
                BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
      const SizedBox(width: 4),
      Text(label,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.outline)),
    ]);
  }
}

class _ForecastCard extends StatelessWidget {
  final String label, value, sub;
  final bool? isBullish;

  const _ForecastCard(
      {required this.label,
      required this.value,
      required this.sub,
      required this.isBullish});

  @override
  Widget build(BuildContext context) {
    final Color color;
    if (isBullish == true) {
      color = const Color(0xFF00C853);
    } else if (isBullish == false) {
      color = const Color(0xFFFF1744);
    } else {
      color = Theme.of(context).colorScheme.outline;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline)),
                  const SizedBox(height: 2),
                  Text(sub,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontSize: 10,
                          color: Theme.of(context)
                              .colorScheme
                              .outline
                              .withAlpha(140))),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(value,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700, color: color)),
          ],
        ),
      ),
    );
  }
}

class _IndicatorCard extends StatelessWidget {
  final String label;
  final String value;
  final String subtitle;
  final String signal;
  final bool? isBullish; // null = neutral

  const _IndicatorCard({
    required this.label,
    required this.value,
    required this.subtitle,
    required this.signal,
    required this.isBullish,
  });

  @override
  Widget build(BuildContext context) {
    final Color signalColor;
    if (isBullish == true) {
      signalColor = const Color(0xFF00C853);
    } else if (isBullish == false) {
      signalColor = const Color(0xFFFF1744);
    } else {
      signalColor = Theme.of(context).colorScheme.outline;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color:
                              Theme.of(context).colorScheme.outline.withAlpha(160),
                          fontSize: 11,
                        ),
                  ),
                ],
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: signalColor.withAlpha(30),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: signalColor.withAlpha(80)),
              ),
              child: Text(
                signal,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: signalColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NewsCard extends StatelessWidget {
  final NewsItem item;

  const _NewsCard({required this.item});

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    return '${diff.inMinutes}m ago';
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        final uri = Uri.tryParse(item.link);
        if (uri != null && await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      },
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                          ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(
                          item.publisher,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                    fontWeight: FontWeight.w500,
                                  ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '·',
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.outline),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _timeAgo(item.publishTime),
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color:
                                        Theme.of(context).colorScheme.outline,
                                  ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (item.thumbnailUrl != null) ...[
                const SizedBox(width: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    item.thumbnailUrl!,
                    width: 72,
                    height: 72,
                    fit: BoxFit.cover,
                    errorBuilder: (context, e, s) => const SizedBox.shrink(),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
