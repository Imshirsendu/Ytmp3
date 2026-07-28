import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs       = Theme.of(context).colorScheme;
    final tt       = Theme.of(context).textTheme;
    final settings = context.watch<SettingsProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        children: [
          Text('Download Quality',
              style: tt.titleSmall?.copyWith(
                  color: cs.primary, letterSpacing: 1)),
          const SizedBox(height: 4),
          Text(
            'Applies to all future downloads. Higher bitrate = larger files.',
            style: tt.bodySmall?.copyWith(
                color: cs.onSurface.withOpacity(0.5)),
          ),
          const SizedBox(height: 16),

          ...AudioBitrate.values.map((bitrate) {
            final selected = settings.bitrate == bitrate;
            return GestureDetector(
              onTap: () => settings.setBitrate(bitrate),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: selected
                      ? cs.primary.withOpacity(0.12)
                      : cs.onSurface.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selected
                        ? cs.primary
                        : cs.onSurface.withOpacity(0.1),
                    width: selected ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      selected
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_off_rounded,
                      color: selected
                          ? cs.primary
                          : cs.onSurface.withOpacity(0.4),
                      size: 20,
                    ),
                    const SizedBox(width: 14),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          bitrate.label,
                          style: tt.bodyMedium?.copyWith(
                            fontWeight: selected
                                ? FontWeight.w600
                                : FontWeight.normal,
                            color: selected
                                ? cs.primary
                                : cs.onSurface,
                          ),
                        ),
                        Text(
                          bitrate.description,
                          style: tt.labelSmall?.copyWith(
                              color: cs.onSurface.withOpacity(0.5)),
                        ),
                      ],
                    ),
                    const Spacer(),
                    if (bitrate == AudioBitrate.kbps192)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: cs.secondary.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'DEFAULT',
                          style: tt.labelSmall?.copyWith(
                            color: cs.secondary,
                            fontSize: 9,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
