import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/quote_provider.dart';
import 'providers/watchlist_provider.dart';
import 'screens/home_screen.dart';
import 'services/watchlist_service.dart';
import 'services/yahoo_finance_service.dart';
import 'theme/app_theme.dart';
import 'theme/theme_provider.dart';

void main() {
  runApp(const StockerApp());
}

class StockerApp extends StatelessWidget {
  const StockerApp({super.key});

  @override
  Widget build(BuildContext context) {
    final yahooService = YahooFinanceService();
    final watchlistService = WatchlistService();

    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        Provider<YahooFinanceService>.value(value: yahooService),
        ChangeNotifierProvider(
          create: (_) => QuoteProvider(yahooService),
        ),
        ChangeNotifierProvider(
          create: (_) => WatchlistProvider(watchlistService),
        ),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) => MaterialApp(
          title: 'Stocker',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: themeProvider.themeMode,
          home: const HomeScreen(),
        ),
      ),
    );
  }
}
