import 'package:flutter/material.dart';
import '../models/search_result.dart';
import 'quote_type_badge.dart';

class SearchResultTile extends StatelessWidget {
  final SearchResult result;
  final VoidCallback onTap;
  final String? exchangeLabel;

  const SearchResultTile({
    super.key,
    required this.result,
    required this.onTap,
    this.exchangeLabel,
  });

  @override
  Widget build(BuildContext context) {
    final subtitle = exchangeLabel != null
        ? '${result.shortname}  ·  $exchangeLabel'
        : result.shortname;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        child: Text(
          result.symbol.isNotEmpty ? result.symbol[0] : '?',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onPrimaryContainer,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ),
      title: Row(
        children: [
          Text(
            result.symbol,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 8),
          QuoteTypeBadge(quoteType: result.quoteType),
        ],
      ),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: Theme.of(context).colorScheme.outline,
          fontSize: 13,
        ),
      ),
      trailing: Text(
        result.exchange,
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.outline,
        ),
      ),
      onTap: onTap,
    );
  }
}
