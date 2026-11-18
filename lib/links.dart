import 'package:url_launcher/url_launcher.dart';

enum LinkPlatform {
  youtube('YouTube'),
  instagram('Instagram'),
  tiktok('TikTok'),
  other('Link');

  const LinkPlatform(this.label);
  final String label;
}

/// Macht aus einer Eingabe eine http(s)-Adresse; ergänzt "https://".
/// Liefert `null`, wenn die Eingabe keine brauchbare Adresse ist.
Uri? parseHttpUrl(String input) {
  var s = input.trim();
  if (s.isEmpty || s.contains(RegExp(r'\s'))) return null;
  if (!s.contains('://')) s = 'https://$s';
  final uri = Uri.tryParse(s);
  if (uri == null) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  if (!uri.host.contains('.')) return null;
  return uri;
}

String _host(String url) =>
    (parseHttpUrl(url)?.host ?? '').toLowerCase().replaceFirst('www.', '');

/// Kurzform für die Anzeige, z. B. "instagram.com".
String hostOf(String url) => _host(url);

LinkPlatform platformOf(String url) {
  final h = _host(url);
  bool isOn(String domain) => h == domain || h.endsWith('.$domain');
  if (isOn('youtube.com') || isOn('youtu.be') || isOn('youtube-nocookie.com')) {
    return LinkPlatform.youtube;
  }
  if (isOn('instagram.com')) return LinkPlatform.instagram;
  if (isOn('tiktok.com')) return LinkPlatform.tiktok;
  return LinkPlatform.other;
}

/// Video-ID aus watch?v=, youtu.be/, /shorts/, /embed/ und /live/.
String? youtubeId(String url) {
  final uri = parseHttpUrl(url);
  if (uri == null || platformOf(url) != LinkPlatform.youtube) return null;
  String? id;
  final host = uri.host.toLowerCase().replaceFirst('www.', '');
  final seg = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (host == 'youtu.be') {
    id = seg.isEmpty ? null : seg.first;
  } else if (uri.queryParameters['v'] != null) {
    id = uri.queryParameters['v'];
  } else if (seg.length >= 2 &&
      const {'shorts', 'embed', 'live', 'v'}.contains(seg.first)) {
    id = seg[1];
  }
  if (id == null || !RegExp(r'^[A-Za-z0-9_-]{6,20}$').hasMatch(id)) return null;
  return id;
}

/// Vorschaubild-Adresse für YouTube-Links; für andere Plattformen gibt es
/// ohne deren API keine.
String? youtubeThumbnail(String url) {
  final id = youtubeId(url);
  return id == null ? null : 'https://img.youtube.com/vi/$id/hqdefault.jpg';
}

/// Öffnet den Link in der zugehörigen App bzw. im Browser.
Future<bool> openLink(String url) async {
  final uri = parseHttpUrl(url);
  if (uri == null) return false;
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}
