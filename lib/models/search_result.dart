class SearchResult {
  final String symbol;
  final String shortname;
  final String quoteType;
  final String exchange;

  const SearchResult({
    required this.symbol,
    required this.shortname,
    required this.quoteType,
    required this.exchange,
  });

  factory SearchResult.fromJson(Map<String, dynamic> json) {
    return SearchResult(
      symbol: json['symbol'] as String? ?? '',
      shortname: json['shortname'] as String? ?? json['longname'] as String? ?? json['symbol'] as String? ?? '',
      quoteType: json['quoteType'] as String? ?? 'EQUITY',
      exchange: json['exchange'] as String? ?? '',
    );
  }
}
