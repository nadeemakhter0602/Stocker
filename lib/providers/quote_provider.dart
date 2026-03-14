import 'package:flutter/material.dart';
import '../models/news_item.dart';
import '../models/stock_quote.dart';
import '../models/chart_data.dart';
import '../services/yahoo_finance_service.dart';

enum QuoteState { idle, loading, success, error }

class QuoteProvider extends ChangeNotifier {
  final YahooFinanceService _service;

  QuoteProvider(this._service);

  final Map<String, StockQuote> _quotes = {};
  final Map<String, List<ChartPoint>> _charts = {};
  final Map<String, QuoteState> _quoteStates = {};
  final Map<String, QuoteState> _chartStates = {};
  final Map<String, String> _errors = {};

  final Map<String, List<NewsItem>> _news = {};
  final Map<String, QuoteState> _newsStates = {};

  StockQuote? getQuote(String symbol) => _quotes[symbol];

  List<ChartPoint> getChart(String symbol, [String interval = '1d']) =>
      _charts['${symbol}_$interval'] ?? [];

  QuoteState getState(String symbol) =>
      _quoteStates[symbol] ?? QuoteState.idle;

  QuoteState getChartState(String symbol, String interval) =>
      _chartStates['${symbol}_$interval'] ?? QuoteState.idle;

  String getError(String symbol) => _errors[symbol] ?? '';

  List<NewsItem> getNews(String symbol) => _news[symbol] ?? [];
  QuoteState getNewsState(String symbol) =>
      _newsStates[symbol] ?? QuoteState.idle;

  Future<void> fetchQuote(String symbol,
      {String interval = '1d', String range = 'max'}) async {
    final chartKey = '${symbol}_$interval';
    if (_chartStates[chartKey] == QuoteState.loading) return;
    if (_quotes[symbol] == null) {
      _quoteStates[symbol] = QuoteState.loading;
    }
    _chartStates[chartKey] = QuoteState.loading;
    notifyListeners();
    try {
      final result = await _service.fetchQuoteAndChart(symbol,
          interval: interval, range: range);
      _quotes[symbol] = result.quote;
      _charts[chartKey] = result.chart;
      _quoteStates[symbol] = QuoteState.success;
      _chartStates[chartKey] = QuoteState.success;
    } catch (e) {
      _errors[symbol] = e.toString();
      _quoteStates[symbol] = QuoteState.error;
      _chartStates[chartKey] = QuoteState.error;
    }
    notifyListeners();
  }

  Future<void> fetchNews(String symbol,
      {bool forceRefresh = false, String? name}) async {
    if (_newsStates[symbol] == QuoteState.loading) return;
    if (_news[symbol] != null && !forceRefresh) return; // already fetched
    _newsStates[symbol] = QuoteState.loading;
    notifyListeners();
    try {
      _news[symbol] = await _service.fetchNews(symbol, name: name);
      _newsStates[symbol] = QuoteState.success;
    } catch (_) {
      _newsStates[symbol] = QuoteState.error;
    }
    notifyListeners();
  }

  Future<void> fetchWatchlistQuotes(List<String> symbols) async {
    await Future.wait(symbols.map((s) => fetchQuote(s, range: '5d')));
  }
}
