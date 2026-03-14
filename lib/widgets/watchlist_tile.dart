import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/quote_provider.dart';
import '../providers/watchlist_provider.dart';
import '../screens/stock_detail_screen.dart';
import 'change_badge.dart';

class WatchlistTile extends StatelessWidget {
  final String symbol;

  const WatchlistTile({super.key, required this.symbol});

  @override
  Widget build(BuildContext context) {
    return Consumer<QuoteProvider>(
      builder: (context, quoteProvider, _) {
        final quote = quoteProvider.getQuote(symbol);
        final state = quoteProvider.getState(symbol);

        return Dismissible(
          key: Key(symbol),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              color: Colors.red.shade700,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.delete_outline_rounded,
                color: Colors.white, size: 28),
          ),
          onDismissed: (_) {
            context.read<WatchlistProvider>().remove(symbol);
          },
          child: Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: CircleAvatar(
                backgroundColor:
                    Theme.of(context).colorScheme.primaryContainer,
                child: Text(
                  symbol.isNotEmpty ? symbol[0] : '?',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              title: Text(
                symbol,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: quote != null
                  ? Text(
                      quote.shortName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    )
                  : null,
              trailing: _buildTrailing(context, state, quote),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => StockDetailScreen(symbol: symbol),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildTrailing(BuildContext context, QuoteState state, quote) {
    if (state == QuoteState.loading) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (quote == null) return const SizedBox.shrink();
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          '\$${quote.price.toStringAsFixed(2)}',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
        const SizedBox(height: 4),
        ChangeBadge(
          change: quote.change,
          changePercent: quote.changePercent,
          compact: true,
        ),
      ],
    );
  }
}
