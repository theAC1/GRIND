import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../links.dart';
import '../store.dart';
import '../theme.dart';

/// Zeigt ein in der App gespeichertes Bild.
class StoredImage extends StatelessWidget {
  const StoredImage(this.id, {super.key, this.fit = BoxFit.cover});

  final String id;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FutureBuilder<Uint8List?>(
      future: StoreScope.read(context).media.load(id),
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null) {
          final loading = snapshot.connectionState != ConnectionState.done;
          return ColoredBox(
            color: scheme.surfaceContainerHigh,
            child: Center(
              child: Icon(
                loading ? Icons.image_outlined : Icons.broken_image_outlined,
                color: scheme.outline,
              ),
            ),
          );
        }
        return Image.memory(
          bytes,
          fit: fit,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => ColoredBox(
            color: scheme.surfaceContainerHigh,
            child: Icon(Icons.broken_image_outlined, color: scheme.outline),
          ),
        );
      },
    );
  }
}

/// Vorschau eines Video-Links mit Play-Symbol. YouTube liefert ein
/// Vorschaubild; andere Plattformen bekommen eine neutrale Fläche.
class VideoThumb extends StatelessWidget {
  const VideoThumb(
    this.url, {
    super.key,
    this.compact = false,
    this.posterImageId,
  });

  final String url;

  /// Eigenes Bild als Hintergrund, wenn die Plattform keines liefert.
  final String? posterImageId;

  /// Ohne Beschriftung, für kleine Kacheln.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final platform = platformOf(url);
    final thumb = youtubeThumbnail(url);

    final placeholder = ColoredBox(
      color: colors.hero,
      child: compact
          ? null
          : Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  platform.label.toUpperCase(),
                  style: TextStyle(
                    fontFamily: headingFont,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    letterSpacing: 1.2,
                    color: colors.heroAccent,
                  ),
                ),
              ),
            ),
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        if (thumb == null)
          posterImageId == null ? placeholder : StoredImage(posterImageId!)
        else
          Image.network(
            thumb,
            fit: BoxFit.cover,
            webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
            errorBuilder: (_, _, _) => placeholder,
            loadingBuilder: (context, child, progress) =>
                progress == null ? child : placeholder,
          ),
        Center(
          child: Container(
            width: compact ? 28 : 52,
            height: compact ? 28 : 52,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.play_arrow,
              color: Colors.white,
              size: compact ? 20 : 34,
            ),
          ),
        ),
        if (!compact)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 18, 12, 8),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black87],
                ),
              ),
              child: Text(
                '${platform.label} · ${hostOf(url)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ),
      ],
    );
  }
}

Future<void> openVideo(BuildContext context, String url) async {
  final messenger = ScaffoldMessenger.of(context);
  final ok = await openLink(url);
  if (!ok) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Der Link konnte nicht geöffnet werden.')),
    );
  }
}

void showImageViewer(BuildContext context, String imageId) {
  Navigator.of(context).push(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
        ),
        body: InteractiveViewer(
          maxScale: 5,
          child: Center(child: StoredImage(imageId, fit: BoxFit.contain)),
        ),
      ),
    ),
  );
}

/// Videos und Bilder einer Übung zum Durchwischen. Videos öffnen in der
/// jeweiligen App, Bilder in der Vollansicht.
class MediaGallery extends StatelessWidget {
  const MediaGallery({
    super.key,
    required this.videoLinks,
    required this.imageIds,
    this.height = 190,
  });

  final List<String> videoLinks;
  final List<String> imageIds;
  final double height;

  @override
  Widget build(BuildContext context) {
    final tiles = <Widget>[
      for (final url in videoLinks)
        _GalleryTile(
          aspectRatio: 16 / 9,
          onTap: () => openVideo(context, url),
          child: VideoThumb(url),
        ),
      for (final id in imageIds)
        _GalleryTile(
          aspectRatio: 4 / 3,
          onTap: () => showImageViewer(context, id),
          child: StoredImage(id),
        ),
    ];
    if (tiles.isEmpty) return const SizedBox.shrink();
    if (tiles.length == 1) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: height + 30),
          child: tiles.single,
        ),
      );
    }
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: tiles.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (_, i) => tiles[i],
      ),
    );
  }
}

class _GalleryTile extends StatelessWidget {
  const _GalleryTile({
    required this.aspectRatio,
    required this.onTap,
    required this.child,
  });

  final double aspectRatio;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: aspectRatio,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          fit: StackFit.expand,
          children: [
            child,
            Material(
              type: MaterialType.transparency,
              child: InkWell(onTap: onTap),
            ),
          ],
        ),
      ),
    );
  }
}

/// Wählt Bilder aus Galerie oder Kamera, speichert sie verkleinert in der
/// App und liefert ihre IDs.
Future<List<String>> pickAndStoreImages(
  BuildContext context,
  ImageSource source,
) async {
  final store = StoreScope.read(context);
  final messenger = ScaffoldMessenger.of(context);
  final ids = <String>[];
  try {
    final picker = ImagePicker();
    final List<XFile> files;
    if (source == ImageSource.camera) {
      final shot = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1600,
        imageQuality: 82,
      );
      files = [?shot];
    } else {
      files = await picker.pickMultiImage(maxWidth: 1600, imageQuality: 82);
    }
    for (final f in files) {
      ids.add(await store.media.add(await f.readAsBytes()));
    }
  } catch (_) {
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Das Bild konnte nicht hinzugefügt werden.'),
      ),
    );
  }
  return ids;
}

/// Bildleiste zum Bearbeiten: vorhandene Bilder entfernen, neue hinzufügen.
class ImageStripEditor extends StatelessWidget {
  const ImageStripEditor({
    super.key,
    required this.ids,
    required this.onChanged,
    this.onAdded,
    this.addLabel = 'Bild',
  });

  final List<String> ids;
  final ValueChanged<List<String>> onChanged;

  /// Meldet neu gespeicherte Bilder, damit sie beim Abbrechen wieder
  /// freigegeben werden können.
  final ValueChanged<List<String>>? onAdded;
  final String addLabel;

  Future<void> _add(BuildContext context) async {
    var source = ImageSource.gallery;
    if (!kIsWeb) {
      final picked = await showModalBottomSheet<ImageSource>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Aus Galerie / Screenshots'),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Foto aufnehmen'),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
            ],
          ),
        ),
      );
      if (picked == null || !context.mounted) return;
      source = picked;
    }
    final added = await pickAndStoreImages(context, source);
    if (added.isEmpty) return;
    onAdded?.call(added);
    onChanged([...ids, ...added]);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 96,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final id in ids)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: 96,
                      height: 96,
                      child: GestureDetector(
                        onTap: () => showImageViewer(context, id),
                        child: StoredImage(id),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Material(
                      color: Colors.black.withValues(alpha: 0.6),
                      shape: const CircleBorder(),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () =>
                            onChanged(ids.where((i) => i != id).toList()),
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(
                            Icons.close,
                            size: 16,
                            color: Colors.white,
                            semanticLabel: 'Bild entfernen',
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Material(
            color: scheme.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: scheme.outline),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => _add(context),
              child: SizedBox(
                width: 96,
                height: 96,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.add_photo_alternate_outlined,
                      color: scheme.primary,
                    ),
                    const SizedBox(height: 4),
                    Text(addLabel, style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Dialog für einen Video-Link; liefert die bereinigte Adresse.
Future<String?> showLinkDialog(BuildContext context, {String initial = ''}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _LinkDialog(initial: initial),
  );
}

class _LinkDialog extends StatefulWidget {
  const _LinkDialog({required this.initial});

  final String initial;

  @override
  State<_LinkDialog> createState() => _LinkDialogState();
}

class _LinkDialogState extends State<_LinkDialog> {
  late final _controller = TextEditingController(text: widget.initial);
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isNotEmpty) setState(() => _controller.text = text);
  }

  void _submit() {
    final uri = parseHttpUrl(_controller.text);
    if (uri == null) {
      setState(() => _error = 'Bitte einen gültigen Link eingeben');
      return;
    }
    Navigator.pop(context, uri.toString());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Video-Link'),
      content: TextField(
        key: const Key('link_field'),
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.url,
        decoration: InputDecoration(
          hintText: 'YouTube, Instagram, TikTok …',
          errorText: _error,
          suffixIcon: IconButton(
            tooltip: 'Einfügen',
            icon: const Icon(Icons.content_paste),
            onPressed: _paste,
          ),
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Hinzufügen')),
      ],
    );
  }
}

/// Liste der Video-Links einer Übung zum Bearbeiten.
class LinkListEditor extends StatelessWidget {
  const LinkListEditor({
    super.key,
    required this.links,
    required this.onChanged,
  });

  final List<String> links;
  final ValueChanged<List<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final url in links)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                contentPadding: const EdgeInsets.only(left: 12, right: 4),
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 64,
                    height: 40,
                    child: VideoThumb(url, compact: true),
                  ),
                ),
                title: Text(platformOf(url).label),
                subtitle: Text(
                  url,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: IconButton(
                  tooltip: 'Link entfernen',
                  icon: const Icon(Icons.close),
                  onPressed: () =>
                      onChanged(links.where((l) => l != url).toList()),
                ),
                onTap: () => openVideo(context, url),
              ),
            ),
          ),
        OutlinedButton.icon(
          onPressed: () async {
            final url = await showLinkDialog(context);
            if (url != null && !links.contains(url)) {
              onChanged([...links, url]);
            }
          },
          icon: const Icon(Icons.add_link),
          label: const Text('Video-Link hinzufügen'),
        ),
      ],
    );
  }
}
