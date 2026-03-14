import 'package:flutter/material.dart';
import '../services/watchlist_service.dart';

class WatchlistProvider extends ChangeNotifier {
  final WatchlistService _service;

  WatchlistProvider(this._service) {
    _load();
  }

  List<String> _symbols = [];
  List<String> get symbols => List.unmodifiable(_symbols);

  bool contains(String symbol) => _symbols.contains(symbol.toUpperCase());

  Future<void> _load() async {
    _symbols = await _service.load();
    notifyListeners();
  }

  Future<void> add(String symbol) async {
    final s = symbol.toUpperCase();
    if (_symbols.contains(s)) return;
    _symbols = [..._symbols, s];
    notifyListeners();
    await _service.save(_symbols);
  }

  Future<void> remove(String symbol) async {
    final s = symbol.toUpperCase();
    _symbols = _symbols.where((e) => e != s).toList();
    notifyListeners();
    await _service.save(_symbols);
  }

  Future<void> toggle(String symbol) async {
    if (contains(symbol)) {
      await remove(symbol);
    } else {
      await add(symbol);
    }
  }
}
