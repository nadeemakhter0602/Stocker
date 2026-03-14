import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/update_service.dart';
import '../theme/app_theme.dart';
import '../theme/theme_provider.dart';
import 'search_screen.dart';
import 'watchlist_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  ({String version, String downloadUrl, String releaseUrl})? _update;
  bool _checkingUpdate = false;
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    _checkUpdate();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) setState(() => _appVersion = info.version);
  }

  Future<void> _checkUpdate() async {
    final update = await UpdateService.checkForUpdate();
    if (update != null && mounted) {
      setState(() => _update = update);
    }
  }

  static const _titles = ['Search', 'Watchlist'];

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();

    return Scaffold(
      drawer: _buildDrawer(context, themeProvider),
      appBar: AppBar(
        title: Text(
          _titles[_selectedIndex],
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            icon: Icon(themeProvider.icon),
            tooltip: 'Toggle theme',
            onPressed: themeProvider.cycle,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          if (_update != null) _UpdateBanner(update: _update!, onDismiss: () => setState(() => _update = null)),
          Expanded(
            child: IndexedStack(
              index: _selectedIndex,
              children: const [
                SearchScreen(),
                WatchlistScreen(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (i) => setState(() => _selectedIndex = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.search_outlined),
            selectedIcon: Icon(Icons.search_rounded),
            label: 'Search',
          ),
          NavigationDestination(
            icon: Icon(Icons.bookmark_border_rounded),
            selectedIcon: Icon(Icons.bookmark_rounded),
            label: 'Watchlist',
          ),
        ],
      ),
    );
  }

  Widget _buildDrawer(BuildContext context, ThemeProvider themeProvider) {
    return Drawer(
      child: Column(
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(color: AppTheme.seedColor),
            child: Row(
              children: [
                const Icon(
                  Icons.candlestick_chart_rounded,
                  color: Colors.white,
                  size: 36,
                ),
                const SizedBox(width: 12),
                Text(
                  'Stocker',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ],
            ),
          ),
          ListTile(
            leading: Icon(themeProvider.icon),
            title: const Text('Toggle Theme'),
            onTap: () {
              Navigator.pop(context);
              themeProvider.cycle();
            },
          ),
          ListTile(
            leading: _checkingUpdate
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.system_update_rounded),
            title: const Text('Check for Updates'),
            onTap: _checkingUpdate
                ? null
                : () async {
                    final messenger = ScaffoldMessenger.of(context);
                    Navigator.pop(context);
                    setState(() => _checkingUpdate = true);
                    final update = await UpdateService.checkForUpdate();
                    if (!mounted) return;
                    setState(() {
                      _checkingUpdate = false;
                      if (update != null) _update = update;
                    });
                    if (update == null) {
                      messenger.showSnackBar(
                        const SnackBar(content: Text('Already up to date')),
                      );
                    }
                  },
          ),
          ListTile(
            leading: const Icon(Icons.info_outline_rounded),
            title: const Text('About'),
            onTap: () {
              Navigator.pop(context);
              showAboutDialog(
                context: context,
                applicationName: 'Stocker',
                applicationVersion: _appVersion,
                applicationIcon: const Icon(
                  Icons.candlestick_chart_rounded,
                  size: 48,
                  color: AppTheme.seedColor,
                ),
                children: [
                  const Text(
                    'A stock & ETF tracker powered by Yahoo Finance. '
                    'Search US, India, and global markets.',
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: () => launchUrl(
                      Uri.parse('https://github.com/nadeemakhter0602/stocker'),
                      mode: LaunchMode.externalApplication,
                    ),
                    child: const Text(
                      'github.com/nadeemakhter0602/stocker',
                      style: TextStyle(
                        color: AppTheme.seedColor,
                        decoration: TextDecoration.underline,
                        decorationColor: AppTheme.seedColor,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _UpdateBanner extends StatelessWidget {
  final ({String version, String downloadUrl, String releaseUrl}) update;
  final VoidCallback onDismiss;

  const _UpdateBanner({required this.update, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return MaterialBanner(
      backgroundColor: AppTheme.seedColor.withAlpha(30),
      leading: const Icon(Icons.system_update_rounded, color: AppTheme.seedColor),
      content: Text(
        'v${update.version} available',
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      actions: [
        TextButton(
          onPressed: onDismiss,
          child: const Text('Later'),
        ),
        if (update.releaseUrl.isNotEmpty)
          TextButton(
            onPressed: () {
              onDismiss();
              launchUrl(Uri.parse(update.releaseUrl), mode: LaunchMode.externalApplication);
            },
            child: const Text('GitHub'),
          ),
        if (update.downloadUrl.isNotEmpty)
          TextButton(
            onPressed: () {
              onDismiss();
              UpdateService.downloadAndInstall(context, update.downloadUrl, update.version);
            },
            child: const Text('Update'),
          )
        else
          TextButton(
            onPressed: () {
              onDismiss();
              launchUrl(Uri.parse(update.releaseUrl), mode: LaunchMode.externalApplication);
            },
            child: const Text('View release'),
          ),
      ],
    );
  }
}
