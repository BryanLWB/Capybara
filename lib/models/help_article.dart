class HelpCategory {
  HelpCategory({
    required this.name,
    required this.articles,
  });

  final String name;
  final List<HelpArticleSummary> articles;

  factory HelpCategory.fromMap(Map<String, dynamic> map) {
    final rawArticles = map['articles'];
    final articles = rawArticles is List
        ? rawArticles
            .whereType<Map>()
            .map((item) => HelpArticleSummary.fromMap(
                  Map<String, dynamic>.from(item),
                ))
            .where((item) => item.id > 0)
            .toList()
        : <HelpArticleSummary>[];

    return HelpCategory(
      name: map['name']?.toString() ?? '',
      articles: articles,
    );
  }
}

class HelpArticleSummary {
  HelpArticleSummary({
    required this.id,
    required this.category,
    required this.title,
    required this.updatedAt,
  });

  final int id;
  final String category;
  final String title;
  final int updatedAt;

  factory HelpArticleSummary.fromMap(Map<String, dynamic> map) {
    return HelpArticleSummary(
      id: _toInt(map['article_id']),
      category: map['category']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      updatedAt: _toInt(map['updated_at']),
    );
  }
}

class HelpArticleDetail {
  HelpArticleDetail({
    required this.id,
    required this.category,
    required this.title,
    required this.updatedAt,
    required this.bodyHtml,
  });

  final int id;
  final String category;
  final String title;
  final int updatedAt;
  final String bodyHtml;

  factory HelpArticleDetail.fromMap(Map<String, dynamic> map) {
    return HelpArticleDetail(
      id: _toInt(map['article_id']),
      category: map['category']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      updatedAt: _toInt(map['updated_at']),
      bodyHtml: map['body_html']?.toString() ?? '',
    );
  }
}

int _toInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}
