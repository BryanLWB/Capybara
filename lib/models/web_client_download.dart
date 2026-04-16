class WebClientDownloadItem {
  const WebClientDownloadItem({
    required this.platform,
    required this.label,
    required this.available,
    this.version,
    this.downloadUrl,
  });

  final String platform;
  final String label;
  final bool available;
  final String? version;
  final String? downloadUrl;

  factory WebClientDownloadItem.fromJson(Map<String, dynamic> json) {
    final url = json['download_url']?.toString().trim();
    return WebClientDownloadItem(
      platform: json['platform']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      version: json['version']?.toString(),
      downloadUrl: url == null || url.isEmpty ? null : url,
      available: _toBool(json['available']),
    );
  }
}

bool _toBool(Object? value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    return normalized == '1' ||
        normalized == 'true' ||
        normalized == 'yes' ||
        normalized == 'on';
  }
  return false;
}
