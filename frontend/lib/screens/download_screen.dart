import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/track.dart';
import '../providers/download_provider.dart';
import '../providers/server_provider.dart';
import '../widgets/server_status_badge.dart';

class DownloadScreen extends StatefulWidget {
  const DownloadScreen({super.key});

  @override
  State<DownloadScreen> createState() => _DownloadScreenState();
}

class _DownloadScreenState extends State<DownloadScreen> {
  final _urlCtrl = TextEditingController();
  final _serverCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _serverCtrl.text = context.read<ServerProvider>().serverUrl;
    });
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _serverCtrl.dispose();
    super.dispose();
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) {
      _urlCtrl.text = data!.text!.trim();
    }
  }

  void _startDownload() {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) return;

    final server = context.read<ServerProvider>();
    if (!server.isOnline) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Server is offline. Check your IP.')),
      );
      return;
    }

    context
        .read<DownloadProvider>()
        .enqueue(url, server.downloadUrl(url));

    _urlCtrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──────────────────────────────────────────────────
            Row(
              children: [
                Text('Download', style: tt.headlineMedium),
                const Spacer(),
                const ServerStatusBadge(),
              ],
            ),
            const SizedBox(height: 4),
            Text('Paste a YouTube video or playlist URL',
                style: tt.bodyMedium),

            const SizedBox(height: 20),

            // ── Server URL ───────────────────────────────────────────────
            Text('SERVER', style: tt.labelSmall),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _serverCtrl,
                    style: const TextStyle(fontSize: 13),
                    decoration: const InputDecoration(
                      hintText: 'http://192.168.1.100:8000',
                      prefixIcon: Icon(Icons.dns_outlined, size: 18),
                    ),
                    onSubmitted: (v) =>
                        context.read<ServerProvider>().setServerUrl(v),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: () {
                    context
                        .read<ServerProvider>()
                        .setServerUrl(_serverCtrl.text);
                  },
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // ── YouTube URL input ────────────────────────────────────────
            Text('YOUTUBE URL', style: tt.labelSmall),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _urlCtrl,
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'https://youtube.com/watch?v=…',
                      prefixIcon:
                          const Icon(Icons.link_outlined, size: 18),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.content_paste_outlined,
                            size: 18),
                        tooltip: 'Paste from clipboard',
                        onPressed: _pasteFromClipboard,
                      ),
                    ),
                    onSubmitted: (_) => _startDownload(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _startDownload,
                  icon: const Icon(Icons.download_outlined, size: 18),
                  label: const Text('Get'),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // ── Queue header ─────────────────────────────────────────────
            Row(
              children: [
                Text('QUEUE', style: tt.labelSmall),
                const Spacer(),
                TextButton(
                  onPressed:
                      context.read<DownloadProvider>().clearCompleted,
                  child: const Text('Clear done',
                      style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // ── Queue list ───────────────────────────────────────────────
            Expanded(
              child: Consumer<DownloadProvider>(
                builder: (ctx, dl, _) {
                  final jobs = dl.jobs;
                  if (jobs.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.queue_music_outlined,
                              size: 48,
                              color: cs.onSurface.withOpacity(0.2)),
                          const SizedBox(height: 12),
                          Text('No downloads yet',
                              style: tt.bodyMedium),
                        ],
                      ),
                    );
                  }
                  return ListView.separated(
                    itemCount: jobs.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1),
                    itemBuilder: (ctx, i) =>
                        _JobTile(job: jobs[i]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _JobTile extends StatelessWidget {
  final DownloadJob job;
  const _JobTile({required this.job});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final (icon, color) = switch (job.status) {
      DownloadStatus.queued      => (Icons.schedule, cs.onSurface),
      DownloadStatus.downloading => (Icons.downloading, cs.primary),
      DownloadStatus.converting  => (Icons.sync, cs.secondary),
      DownloadStatus.done        => (Icons.check_circle, Colors.green),
      DownloadStatus.error       => (Icons.error_outline, cs.error),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Text(job.title,
                    style: tt.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
              if (job.speed.isNotEmpty)
                Text(job.speed, style: tt.bodyMedium),
            ],
          ),
          if (job.status == DownloadStatus.downloading) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: job.progress,
              borderRadius: BorderRadius.circular(4),
              backgroundColor: cs.surface,
              valueColor: AlwaysStoppedAnimation(cs.primary),
            ),
            const SizedBox(height: 4),
            Text('${(job.progress * 100).toInt()}%',
                style: tt.labelSmall),
          ],
          if (job.status == DownloadStatus.error)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 28),
              child: Text(job.errorMessage ?? 'Error',
                  style: tt.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.error)),
            ),
        ],
      ),
    );
  }
}
