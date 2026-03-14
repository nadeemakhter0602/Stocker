import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/news_item.dart';
import '../models/search_result.dart';
import '../models/stock_quote.dart';
import '../models/chart_data.dart';

class YahooFinanceService {
  static const _headers = {
    'User-Agent':
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept': 'application/json',
  };

  Future<List<SearchResult>> search(String query) async {
    if (query.trim().isEmpty) return [];
    final uri = Uri.parse(
      'https://query1.finance.yahoo.com/v1/finance/search'
      '?q=${Uri.encodeComponent(query)}&lang=en-US&region=US&quotesCount=15',
    );
    final response = await http.get(uri, headers: _headers);
    if (response.statusCode != 200) return [];
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final quotes = data['quotes'] as List<dynamic>? ?? [];
    return quotes
        .whereType<Map<String, dynamic>>()
        .where((q) =>
            q['quoteType'] == 'EQUITY' ||
            q['quoteType'] == 'ETF' ||
            q['quoteType'] == 'MUTUALFUND')
        .map(SearchResult.fromJson)
        .toList();
  }

  Future<({StockQuote quote, List<ChartPoint> chart})> fetchQuoteAndChart(
      String symbol, {String interval = '1d', String range = '5d'}) async {
    final uri = Uri.parse(
      'https://query1.finance.yahoo.com/v8/finance/chart/$symbol'
      '?interval=$interval&range=$range&includePrePost=false',
    );
    final response = await http.get(uri, headers: _headers);
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode} for $symbol');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final result = data['chart']?['result'] as List<dynamic>?;
    if (result == null || result.isEmpty) {
      throw Exception('No data for $symbol');
    }
    final item = result[0] as Map<String, dynamic>;
    final meta = item['meta'] as Map<String, dynamic>;
    final quote = StockQuote.fromChartMeta(meta, symbol);

    final timestamps = item['timestamp'] as List<dynamic>? ?? [];
    final quoteIndicator = (item['indicators']?['quote'] as List<dynamic>?)
        ?.firstOrNull as Map<String, dynamic>?;
    final opens = quoteIndicator?['open'] as List<dynamic>? ?? [];
    final highs = quoteIndicator?['high'] as List<dynamic>? ?? [];
    final lows = quoteIndicator?['low'] as List<dynamic>? ?? [];
    final closes = quoteIndicator?['close'] as List<dynamic>? ?? [];
    final volumes = quoteIndicator?['volume'] as List<dynamic>? ?? [];

    final chartPoints = <ChartPoint>[];
    for (var i = 0; i < timestamps.length; i++) {
      final ts = timestamps[i] as int?;
      final open = i < opens.length ? (opens[i] as num?)?.toDouble() : null;
      final high = i < highs.length ? (highs[i] as num?)?.toDouble() : null;
      final low = i < lows.length ? (lows[i] as num?)?.toDouble() : null;
      final close = i < closes.length ? (closes[i] as num?)?.toDouble() : null;
      if (ts != null &&
          open != null &&
          high != null &&
          low != null &&
          close != null) {
        chartPoints.add(ChartPoint(
          date: DateTime.fromMillisecondsSinceEpoch(ts * 1000),
          open: open,
          high: high,
          low: low,
          close: close,
          volume: i < volumes.length ? (volumes[i] as num?)?.toDouble() : null,
        ));
      }
    }

    return (quote: quote, chart: chartPoints);
  }

  Future<List<NewsItem>> fetchNews(String symbol, {String? name}) async {
    // Build a search query: prefer company name, else strip exchange suffix
    final baseSymbol = symbol.replaceAll(RegExp(r'\.[A-Z]+$'), '');
    final query = name != null && name.isNotEmpty ? name : '$baseSymbol stock';

    // Primary: Google News RSS — works for all markets globally
    try {
      final rssUri = Uri.parse(
        'https://news.google.com/rss/search'
        '?q=${Uri.encodeComponent(query)}&hl=en-US&gl=US&ceid=US:en',
      );
      final rssResp = await http.get(rssUri, headers: {
        'User-Agent': _headers['User-Agent']!,
        'Accept': 'application/rss+xml, application/xml, text/xml',
      });
      if (rssResp.statusCode == 200) {
        final items = _parseRss(rssResp.body);
        if (items.isNotEmpty) return items;
      }
    } catch (_) {}

    // Fallback: Yahoo Finance search without region, filter by relatedTickers
    final searchUri = Uri.parse(
      'https://query1.finance.yahoo.com/v1/finance/search'
      '?q=${Uri.encodeComponent(symbol)}'
      '&quotesCount=0&newsCount=20&enableFuzzyQuery=false',
    );
    final fb = await http.get(searchUri, headers: _headers);
    if (fb.statusCode != 200) return [];
    final data = jsonDecode(fb.body) as Map<String, dynamic>;
    final news = data['news'] as List<dynamic>? ?? [];
    final all = news
        .whereType<Map<String, dynamic>>()
        .map(NewsItem.fromJson)
        .where((n) => n.title.isNotEmpty)
        .toList();
    final sym = symbol.toUpperCase();
    final filtered = all
        .where((n) => n.relatedTickers.any((t) => t.toUpperCase() == sym))
        .toList();
    return filtered.isNotEmpty ? filtered : all;
  }

  static List<NewsItem> _parseRss(String xml) {
    final items = <NewsItem>[];
    final itemRe = RegExp(r'<item>([\s\S]*?)</item>');
    final titleRe = RegExp(r'<title>(?:<!\[CDATA\[)?([\s\S]*?)(?:\]\]>)?</title>');
    final linkRe = RegExp(r'<link>(https?://[^\s<]+)</link>');
    final pubRe = RegExp(r'<pubDate>([\s\S]*?)</pubDate>');
    final srcRe = RegExp(r'<source[^>]*>([\s\S]*?)</source>');

    for (final m in itemRe.allMatches(xml)) {
      final chunk = m.group(1)!;
      final title = titleRe.firstMatch(chunk)?.group(1)?.trim() ?? '';
      final link = linkRe.firstMatch(chunk)?.group(1)?.trim() ?? '';
      if (title.isEmpty || link.isEmpty) continue;
      final pubStr = pubRe.firstMatch(chunk)?.group(1)?.trim() ?? '';
      final publisher = srcRe.firstMatch(chunk)?.group(1)?.trim() ?? 'Yahoo Finance';
      items.add(NewsItem(
        title: title,
        link: link,
        publisher: publisher,
        publishTime: _parseRssDate(pubStr),
        thumbnailUrl: null,
        relatedTickers: const [],
      ));
    }
    return items;
  }

  static DateTime _parseRssDate(String s) {
    try {
      return DateTime.parse(s);
    } catch (_) {}
    // RFC 822: "Thu, 13 Mar 2026 10:00:00 +0000"
    try {
      const months = {
        'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4, 'May': 5, 'Jun': 6,
        'Jul': 7, 'Aug': 8, 'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12,
      };
      final re = RegExp(
          r'\w+, (\d+) (\w+) (\d+) (\d+):(\d+):(\d+)');
      final m = re.firstMatch(s);
      if (m != null) {
        final day = int.parse(m.group(1)!);
        final mon = months[m.group(2)!] ?? 1;
        final year = int.parse(m.group(3)!);
        final h = int.parse(m.group(4)!);
        final min = int.parse(m.group(5)!);
        final sec = int.parse(m.group(6)!);
        return DateTime.utc(year, mon, day, h, min, sec);
      }
    } catch (_) {}
    return DateTime.now();
  }
}
