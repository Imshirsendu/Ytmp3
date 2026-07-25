import 'dart:typed_data';
import 'package:flutter/material.dart';

/// Displays embedded APIC cover art bytes, or a placeholder if not available.
class CoverArt extends StatelessWidget {
  final Uint8List? coverArtBytes;
  final double size;

  const CoverArt({
    super.key,
    required this.coverArtBytes,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (coverArtBytes != null && coverArtBytes!.isNotEmpty) {
      return SizedBox(
        width: size,
        height: size,
        child: Image.memory(
          coverArtBytes!,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _placeholder(cs),
        ),
      );
    }

    return _placeholder(cs, size: size);
  }

  Widget _placeholder(ColorScheme cs, {double? size}) {
    return Container(
      width: size ?? this.size,
      height: size ?? this.size,
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Icon(
        Icons.music_note_rounded,
        size: (size ?? this.size) * 0.45,
        color: cs.primary.withOpacity(0.5),
      ),
    );
  }
}
