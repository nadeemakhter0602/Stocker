import 'dart:async';
import 'package:flutter/material.dart';
import '../models/search_result.dart';
import '../services/yahoo_finance_service.dart';

enum SearchState { idle, loading, success, error }

class SearchProvider extends ChangeNotifier {
  final YahooFinanceService _service;

  SearchProvider(this._service);

  SearchState _state = SearchState.idle;
  List<SearchResult> _results = [];
  String _error = '';
  Timer? _debounce;

  SearchState get state => _state;
  List<SearchResult> get results => _results;
  String get error => _error;

  void search(String query) {
    _debounce?.cancel();
    if (query.trim().isEmpty) {
      _state = SearchState.idle;
      _results = [];
      notifyListeners();
      return;
    }
    _state = SearchState.loading;
    notifyListeners();
    _debounce = Timer(const Duration(milliseconds: 400), () => _fetch(query));
  }

  Future<void> _fetch(String query) async {
    try {
      final results = await _service.search(query);
      _results = results;
      _state = SearchState.success;
    } catch (e) {
      _error = e.toString();
      _state = SearchState.error;
    }
    notifyListeners();
  }

  void clear() {
    _debounce?.cancel();
    _state = SearchState.idle;
    _results = [];
    notifyListeners();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}
