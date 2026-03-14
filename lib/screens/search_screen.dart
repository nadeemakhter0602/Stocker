import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/search_provider.dart';
import '../widgets/search_result_tile.dart';
import '../widgets/error_view.dart';
import 'stock_detail_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen>
    with AutomaticKeepAliveClientMixin {
  late final TextEditingController _controller;
  late final SearchProvider _provider;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _provider = SearchProvider(context.read());
  }

  @override
  void dispose() {
    _controller.dispose();
    _provider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ChangeNotifierProvider.value(
      value: _provider,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _controller,
              autofocus: false,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search stocks & ETFs (AAPL, RELIANCE, SPY…)',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _controller,
                  builder: (context, val, _) => val.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded),
                          onPressed: () {
                            _controller.clear();
                            _provider.clear();
                          },
                        )
                      : const SizedBox.shrink(),
                ),
              ),
              onChanged: _provider.search,
            ),
          ),
          Expanded(child: _buildResults()),
        ],
      ),
    );
  }

  String _mapExchange(String exchange) {
    switch (exchange.toUpperCase()) {
      case 'NSI':
        return 'NSE';
      case 'BOM':
        return 'BSE';
      default:
        return exchange.isEmpty ? '' : exchange;
    }
  }

  Widget _buildResults() {
    return Consumer<SearchProvider>(
      builder: (context, provider, _) {
        switch (provider.state) {
          case SearchState.idle:
            return _buildEmptyState(context);
          case SearchState.loading:
            return const Center(child: CircularProgressIndicator());
          case SearchState.error:
            return ErrorView(message: provider.error);
          case SearchState.success:
            if (provider.results.isEmpty) {
              return Center(
                child: Text(
                  'No results found',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.only(bottom: 16),
              itemCount: provider.results.length,
              separatorBuilder: (context, _) => Divider(
                height: 1,
                indent: 72,
                color: Theme.of(context).colorScheme.outlineVariant.withAlpha(80),
              ),
              itemBuilder: (context, index) {
                final result = provider.results[index];
                return SearchResultTile(
                  result: result,
                  exchangeLabel: _mapExchange(result.exchange),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => StockDetailScreen(symbol: result.symbol),
                    ),
                  ),
                );
              },
            );
        }
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
              Icons.candlestick_chart_rounded,
              size: 64,
              color: Theme.of(context).colorScheme.primaryContainer,
            ),
            const SizedBox(height: 16),
            Text(
              'Search Any Market',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Try AAPL, RELIANCE, TCS, SPY, QQQ…',
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
          ],
        ),
      ),
    );
  }
}
