class StockQuote {
  final String symbol;
  final String shortName;
  final String quoteType;
  final double price;
  final double change;
  final double changePercent;
  final double? previousClose;
  final double? open;
  final double? dayHigh;
  final double? dayLow;
  final double? fiftyTwoWeekHigh;
  final double? fiftyTwoWeekLow;
  final double? volume;
  final double? marketCap;
  final double? trailingPE;
  final String currency;

  const StockQuote({
    required this.symbol,
    required this.shortName,
    required this.quoteType,
    required this.price,
    required this.change,
    required this.changePercent,
    this.previousClose,
    this.open,
    this.dayHigh,
    this.dayLow,
    this.fiftyTwoWeekHigh,
    this.fiftyTwoWeekLow,
    this.volume,
    this.marketCap,
    this.trailingPE,
    this.currency = 'USD',
  });

  bool get isPositive => change >= 0;

  factory StockQuote.fromChartMeta(Map<String, dynamic> meta, String symbol) {
    final price = (meta['regularMarketPrice'] as num?)?.toDouble() ?? 0.0;
    final previousClose = (meta['chartPreviousClose'] as num?)?.toDouble() ??
        (meta['previousClose'] as num?)?.toDouble();
    final change = previousClose != null ? price - previousClose : 0.0;
    final changePercent = (previousClose != null && previousClose != 0)
        ? (change / previousClose) * 100
        : 0.0;

    return StockQuote(
      symbol: meta['symbol'] as String? ?? symbol,
      shortName: meta['shortName'] as String? ??
          meta['longName'] as String? ??
          symbol,
      quoteType: meta['instrumentType'] as String? ?? 'EQUITY',
      price: price,
      change: change,
      changePercent: changePercent,
      previousClose: previousClose,
      open: (meta['regularMarketDayOpen'] as num?)?.toDouble(),
      dayHigh: (meta['regularMarketDayHigh'] as num?)?.toDouble(),
      dayLow: (meta['regularMarketDayLow'] as num?)?.toDouble(),
      fiftyTwoWeekHigh: (meta['fiftyTwoWeekHigh'] as num?)?.toDouble(),
      fiftyTwoWeekLow: (meta['fiftyTwoWeekLow'] as num?)?.toDouble(),
      volume: (meta['regularMarketVolume'] as num?)?.toDouble(),
      marketCap: (meta['marketCap'] as num?)?.toDouble(),
      trailingPE: (meta['trailingPE'] as num?)?.toDouble(),
      currency: meta['currency'] as String? ?? 'USD',
    );
  }
}
