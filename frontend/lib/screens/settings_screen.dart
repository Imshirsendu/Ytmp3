import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/player_provider.dart';
import '../providers/settings_provider.dart';
import '../screens/player_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static Future<void> show(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('Settings', style: tt.titleLarge),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Consumer<SettingsProvider>(
        builder: (ctx, settings, _) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
            children: [
              // ── Download Quality ───────────────────────────────────────
              _SectionHeader(label: 'Download Quality'),
              _Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Bitrate', style: tt.titleMedium),
                          const SizedBox(height: 2),
                          Text(
                            'Applied to new downloads. Existing files are not affected.',
                            style: tt.labelSmall?.copyWith(
                                color: cs.onSurface.withOpacity(0.5)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    ...AudioBitrate.values.map((b) {
                      final selected = settings.bitrate == b;
                      return RadioListTile<AudioBitrate>(
                        value: b,
                        groupValue: settings.bitrate,
                        onChanged: (val) {
                          if (val != null) settings.setBitrate(val);
                        },
                        title: Text(b.label,
                            style: tt.bodyMedium?.copyWith(
                              color: selected
                                  ? cs.primary
                                  : cs.onSurface,
                              fontWeight: selected
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            )),
                        subtitle: Text(b.description,
                            style: tt.labelSmall?.copyWith(
                                color: cs.onSurface.withOpacity(0.5))),
                        activeColor: cs.primary,
                        dense: true,
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 16),
                      );
                    }),
                    const SizedBox(height: 8),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // ── Audio ──────────────────────────────────────────────────
              _SectionHeader(label: 'Audio'),
              _Card(
                child: Consumer<PlayerProvider>(
                  builder: (ctx, player, _) {
                    return ListTile(
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: cs.primary.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.equalizer_rounded,
                            color: cs.primary, size: 22),
                      ),
                      title: Text('Equalizer', style: tt.titleMedium),
                      subtitle: Text(
                        player.eqReady
                            ? 'Current preset: ${player.eqPreset.label}'
                            : 'Android only',
                        style: tt.labelSmall?.copyWith(
                            color: player.eqReady
                                ? cs.primary.withOpacity(0.8)
                                : cs.onSurface.withOpacity(0.4)),
                      ),
                      trailing: Icon(Icons.chevron_right_rounded,
                          color: cs.onSurface.withOpacity(0.3)),
                      onTap: () {
                        // Open EQ by pushing a temporary player screen if
                        // nothing is playing, or show the sheet directly.
                        if (player.current != null) {
                          PlayerScreen.show(context);
                        } else {
                          _EqOnlySheet.show(context);
                        }
                      },
                    );
                  },
                ),
              ),

              const SizedBox(height: 24),

              // ── About ──────────────────────────────────────────────────
              _SectionHeader(label: 'About'),
              _Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: cs.onSurface.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.music_note_rounded,
                            color: cs.onSurface.withOpacity(0.5), size: 22),
                      ),
                      title: Text('ytmp3', style: tt.titleMedium),
                      subtitle: Text('Self-hosted YouTube → MP3',
                          style: tt.labelSmall),
                      trailing: Text('v1.0.0',
                          style: tt.labelSmall?.copyWith(
                              color: cs.onSurface.withOpacity(0.4))),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: cs.primary,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Standalone EQ sheet (when no track is playing)
// ─────────────────────────────────────────────────────────────────────────────

class _EqOnlySheet extends StatelessWidget {
  const _EqOnlySheet();

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => ChangeNotifierProvider.value(
        value: context.read<PlayerProvider>(),
        child: const _EqOnlySheet(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs     = Theme.of(context).colorScheme;
    final tt     = Theme.of(context).textTheme;
    final player = context.watch<PlayerProvider>();

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: cs.onSurface.withOpacity(0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text('⚡', style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Text('Equalizer', style: tt.titleMedium),
            ],
          ),
          const SizedBox(height: 4),
          Text('Preset will be applied to the next track.',
              style: tt.labelSmall),
          const SizedBox(height: 20),
          Row(
            children: EqPreset.values.map((preset) {
              final active = player.eqPreset == preset;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: GestureDetector(
                    onTap: () => player.setEqPreset(preset),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: active
                            ? cs.primary
                            : cs.onSurface.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: active
                              ? cs.primary
                              : cs.onSurface.withOpacity(0.12),
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(preset.emoji,
                              style: const TextStyle(fontSize: 20)),
                          const SizedBox(height: 6),
                          Text(
                            preset.label,
                            style: tt.labelSmall?.copyWith(
                              color: active
                                  ? cs.onPrimary
                                  : cs.onSurface.withOpacity(0.7),
                              fontWeight: active
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          if (!player.eqReady) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.onSurface.withOpacity(0.05),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded,
                      size: 16, color: cs.onSurface.withOpacity(0.4)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Equalizer requires Android. Preset selection is saved.',
                      style: tt.labelSmall,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
