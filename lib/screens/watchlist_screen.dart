import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/quote_provider.dart';
import '../providers/watchlist_provider.dart';
import '../widgets/watchlist_tile.dart';

class WatchlistScreen extends StatefulWidget {
  const WatchlistScreen({super.key});

  @override
  State<WatchlistScreen> createState() => _WatchlistScreenState();
}

class _WatchlistScreenState extends State<WatchlistScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Consumer<WatchlistProvider>(
      builder: (context, watchlistProvider, _) {
        final symbols = watchlistProvider.symbols;

        if (symbols.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            context.read<QuoteProvider>().fetchWatchlistQuotes(symbols.toList());
          });
        }

        if (symbols.isEmpty) {
          return _buildEmptyState(context);
        }

        return RefreshIndicator(
          onRefresh: () => context
              .read<QuoteProvider>()
              .fetchWatchlistQuotes(symbols.toList()),
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: symbols.length,
            itemBuilder: (_, i) => WatchlistTile(symbol: symbols[i]),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.bookmark_border_rounded,
              size: 64,
              color: Theme.of(context).colorScheme.primaryContainer,
            ),
            const SizedBox(height: 16),
            Text(
              'Your watchlist is empty',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Search for stocks and tap the bookmark\nicon to add them here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
          ],
        ),
      ),
    );
  }
}
