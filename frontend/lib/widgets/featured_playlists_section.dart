import 'package:flutter/material.dart';

import '../models/featured_playlist.dart';
import '../screens/featured_playlist_screen.dart';

class FeaturedPlaylistsSection extends StatelessWidget {
  const FeaturedPlaylistsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
          child: Text('Featured Playlists', style: tt.titleMedium),
        ),
        SizedBox(
          height: 148,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            itemCount: kFeaturedPlaylists.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (ctx, i) =>
                _PlaylistCard(playlist: kFeaturedPlaylists[i]),
          ),
        ),
        const SizedBox(height: 8),
        const Divider(height: 1),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _PlaylistCard extends StatelessWidget {
  final FeaturedPlaylist playlist;
  const _PlaylistCard({required this.playlist});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => FeaturedPlaylistScreen(playlist: playlist),
        ),
      ),
      child: Container(
        width: 148,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: playlist.gradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: playlist.gradient.first.withOpacity(0.35),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Background pattern — subtle circles
            Positioned(
              right: -16,
              top: -16,
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.08),
                ),
              ),
            ),
            Positioned(
              right: 10,
              bottom: -20,
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.06),
                ),
              ),
            ),

            // Content
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Emoji
                  Text(playlist.emoji,
                      style: const TextStyle(fontSize: 28)),

                  const Spacer(),

                  // Title
                  Text(
                    playlist.title,
                    style: tt.titleMedium?.copyWith(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),

                  // Subtitle
                  Text(
                    playlist.subtitle,
                    style: tt.labelSmall?.copyWith(
                      color: Colors.white70,
                      fontSize: 10,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            // Play icon overlay (top right)
            Positioned(
              top: 10,
              right: 10,
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
