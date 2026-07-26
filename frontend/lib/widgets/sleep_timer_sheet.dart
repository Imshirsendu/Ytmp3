// Add this class to player_screen.dart (below _EqSheet) or import separately.
// Also add this button to the player_screen.dart AppBar actions list:
//
//   Consumer<PlayerProvider>(
//     builder: (ctx, player, _) => IconButton(
//       icon: Icon(
//         Icons.bedtime_outlined,
//         color: player.sleepTimerActive ? cs.primary : null,
//       ),
//       tooltip: 'Sleep timer',
//       onPressed: () => _SleepTimerSheet.show(context),
//     ),
//   ),

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/player_provider.dart';

class SleepTimerSheet extends StatelessWidget {
  const SleepTimerSheet();

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => ChangeNotifierProvider.value(
        value: context.read<PlayerProvider>(),
        child: const SleepTimerSheet(),
      ),
    );
  }

  static const _presets = [
    (label: '15 min',  duration: Duration(minutes: 15)),
    (label: '30 min',  duration: Duration(minutes: 30)),
    (label: '45 min',  duration: Duration(minutes: 45)),
    (label: '60 min',  duration: Duration(minutes: 60)),
  ];

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
          // Handle
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
              const Text('🌙', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Text('Sleep Timer', style: tt.titleMedium),
              const Spacer(),
              if (player.sleepTimerActive) ...[
                _CountdownChip(remaining: player.sleepRemaining),
                const SizedBox(width: 8),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            player.sleepTimerActive
                ? 'Playback will pause when the timer ends.'
                : 'Pause playback after a set time.',
            style: tt.labelSmall,
          ),
          const SizedBox(height: 20),

          // Preset grid
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 3.2,
            children: _presets.map((p) {
              final isActive = player.sleepTimerActive &&
                  player.sleepRemaining != null &&
                  // close enough — active preset whose remaining ≈ this bucket
                  (player.sleepRemaining!.inMinutes <=
                      p.duration.inMinutes);
              return GestureDetector(
                onTap: () {
                  player.setSleepTimer(p.duration);
                  Navigator.pop(context);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  decoration: BoxDecoration(
                    color: isActive
                        ? cs.primary
                        : cs.onSurface.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isActive
                          ? cs.primary
                          : cs.onSurface.withOpacity(0.12),
                    ),
                  ),
                  child: Center(
                    child: Text(
                      p.label,
                      style: tt.bodyMedium?.copyWith(
                        color: isActive
                            ? cs.onPrimary
                            : cs.onSurface.withOpacity(0.85),
                        fontWeight: isActive
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),

          if (player.sleepTimerActive) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  player.cancelSleepTimer();
                  Navigator.pop(context);
                },
                icon: const Icon(Icons.cancel_outlined, size: 18),
                label: const Text('Cancel Timer'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: cs.error,
                  side: BorderSide(color: cs.error.withOpacity(0.5)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CountdownChip extends StatelessWidget {
  final Duration? remaining;
  const _CountdownChip({this.remaining});

  String get _label {
    final r = remaining;
    if (r == null) return '';
    final m = r.inMinutes.remainder(60);
    return r.inHours > 0 ? '${r.inHours}h ${m}m left' : '${m}m left';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: cs.primary.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.primary.withOpacity(0.3)),
      ),
      child: Text(
        _label,
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: cs.primary),
      ),
    );
  }
}
