import 'package:shared_preferences/shared_preferences.dart';

class WatchlistService {
  static const _key = 'watchlist_symbols';

  Future<List<String>> load() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_key) ?? [];
  }

  Future<void> save(List<String> symbols) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, symbols);
  }
}
