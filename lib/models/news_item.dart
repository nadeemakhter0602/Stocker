class NewsItem {
  final String title;
  final String link;
  final String publisher;
  final DateTime publishTime;
  final String? thumbnailUrl;
  final List<String> relatedTickers;

  const NewsItem({
    required this.title,
    required this.link,
    required this.publisher,
    required this.publishTime,
    this.thumbnailUrl,
    this.relatedTickers = const [],
  });

  factory NewsItem.fromJson(Map<String, dynamic> json) {
    final resolutions =
        (json['thumbnail']?['resolutions'] as List<dynamic>?)
            ?.whereType<Map<String, dynamic>>()
            .toList();
    final thumb = resolutions?.isNotEmpty == true ? resolutions!.last : null;
    final link = json['link'] as String? ?? json['url'] as String? ?? '';
    final publisher =
        json['publisher'] as String? ?? json['source'] as String? ?? '';
    final ts = json['providerPublishTime'] as int? ??
        json['pubDate'] as int? ??
        0;
    final tickers = (json['relatedTickers'] as List<dynamic>?)
            ?.whereType<String>()
            .toList() ??
        const [];
    return NewsItem(
      title: json['title'] as String? ?? '',
      link: link,
      publisher: publisher,
      publishTime: DateTime.fromMillisecondsSinceEpoch(ts * 1000),
      thumbnailUrl: thumb?['url'] as String?,
      relatedTickers: tickers,
    );
  }
}
