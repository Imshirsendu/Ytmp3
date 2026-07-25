class SearchResult {
  final String id;
  final String title;
  final String uploader;
  final int? duration; // seconds
  final String? thumbnail;
  final String url;

  const SearchResult({
    required this.id,
    required this.title,
    required this.uploader,
    this.duration,
    this.thumbnail,
    required this.url,
  });

  factory SearchResult.fromJson(Map<String, dynamic> j) => SearchResult(
        id:        j['id'] as String? ?? '',
        title:     j['title'] as String? ?? 'Unknown',
        uploader:  j['uploader'] as String? ?? '',
        duration:  (j['duration'] as num?)?.toInt(),
        thumbnail: j['thumbnail'] as String?,
        url:       j['url'] as String? ?? '',
      );

  String get durationLabel {
    if (duration == null) return '';
    final d = Duration(seconds: duration!);
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  }
}
