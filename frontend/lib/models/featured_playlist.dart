import 'package:flutter/material.dart';

class FeaturedPlaylist {
  final String id;
  final String title;
  final String subtitle;
  final String searchQuery;
  final int limit;
  final List<Color> gradient;
  final IconData icon;
  final String emoji;

  const FeaturedPlaylist({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.searchQuery,
    required this.gradient,
    required this.icon,
    required this.emoji,
    this.limit = 25,
  });
}

/// Original curated playlists
const kFeaturedPlaylists = [
  FeaturedPlaylist(
    id: 'bollywood_top50',
    title: 'Top 50 Bollywood',
    subtitle: 'Hottest Hindi hits',
    searchQuery: 'top bollywood songs 2025 hits',
    gradient: [Color(0xFFFF6B6B), Color(0xFFFF8E53)],
    icon: Icons.local_fire_department_rounded,
    emoji: '🎬',
  ),
  FeaturedPlaylist(
    id: 'english_top50',
    title: 'Top 50 English',
    subtitle: 'Global chart toppers',
    searchQuery: 'top english pop hits 2025',
    gradient: [Color(0xFF6C63FF), Color(0xFF3B82F6)],
    icon: Icons.music_note_rounded,
    emoji: '🌍',
  ),
  FeaturedPlaylist(
    id: 'bengali_top50',
    title: 'Top 50 Bengali',
    subtitle: 'Best of Bangla music',
    searchQuery: 'top bengali songs 2025 hits',
    gradient: [Color(0xFF11998E), Color(0xFF38EF7D)],
    icon: Icons.queue_music_rounded,
    emoji: '🎶',
  ),
  FeaturedPlaylist(
    id: 'arijit_hits',
    title: 'Arijit Singh Hits',
    subtitle: 'The king of melody',
    searchQuery: 'arijit singh best songs hits',
    gradient: [Color(0xFFFC5C7D), Color(0xFF6A3093)],
    icon: Icons.mic_rounded,
    emoji: '🎤',
  ),
  FeaturedPlaylist(
    id: 'saregama_pa',
    title: 'Sa Re Ga Ma Pa',
    subtitle: 'All time classics',
    searchQuery: 'sa re ga ma pa all time hits best songs',
    gradient: [Color(0xFFF7971E), Color(0xFFFFD200)],
    icon: Icons.star_rounded,
    emoji: '⭐',
  ),
  FeaturedPlaylist(
    id: '90s_bollywood',
    title: '90s Bollywood',
    subtitle: 'Nostalgia overloaded',
    searchQuery: '90s bollywood classic hits evergreen',
    gradient: [Color(0xFF42275A), Color(0xFF734B6D)],
    icon: Icons.history_rounded,
    emoji: '📼',
  ),
  FeaturedPlaylist(
    id: 'hindi_romantic',
    title: 'Hindi Romantic',
    subtitle: 'Love songs collection',
    searchQuery: 'best hindi romantic love songs',
    gradient: [Color(0xFFED213A), Color(0xFF93291E)],
    icon: Icons.favorite_rounded,
    emoji: '❤️',
  ),
  FeaturedPlaylist(
    id: 'international_pop',
    title: 'International Pop',
    subtitle: 'World\'s biggest pop hits',
    searchQuery: 'international pop hits 2024 2025 best',
    gradient: [Color(0xFF00B4DB), Color(0xFF0083B0)],
    icon: Icons.public_rounded,
    emoji: '🌟',
  ),
];

/// Mood playlists — shown in a dedicated "Moods" section
const kMoodPlaylists = [
  FeaturedPlaylist(
    id: 'mood_workout',
    title: 'Workout',
    subtitle: 'High energy, push harder',
    searchQuery: 'workout gym high energy music 2025',
    gradient: [Color(0xFFFF416C), Color(0xFFFF4B2B)],
    icon: Icons.fitness_center_rounded,
    emoji: '💪',
    limit: 20,
  ),
  FeaturedPlaylist(
    id: 'mood_chill',
    title: 'Chill',
    subtitle: 'Relax and unwind',
    searchQuery: 'chill lofi relaxing music mix',
    gradient: [Color(0xFF4776E6), Color(0xFF8E54E9)],
    icon: Icons.self_improvement_rounded,
    emoji: '😌',
    limit: 20,
  ),
  FeaturedPlaylist(
    id: 'mood_party',
    title: 'Party',
    subtitle: 'Turn it up loud',
    searchQuery: 'party dance hits 2025 club music',
    gradient: [Color(0xFFf953c6), Color(0xFFb91d73)],
    icon: Icons.celebration_rounded,
    emoji: '🎉',
    limit: 20,
  ),
  FeaturedPlaylist(
    id: 'mood_focus',
    title: 'Focus',
    subtitle: 'Deep work, zero distraction',
    searchQuery: 'focus study concentration instrumental music',
    gradient: [Color(0xFF134E5E), Color(0xFF71B280)],
    icon: Icons.center_focus_strong_rounded,
    emoji: '🧠',
    limit: 20,
  ),
];

/// Trending Now — treated as a single special playlist.
/// The section widget handles daily-refresh caching separately.
const kTrendingPlaylist = FeaturedPlaylist(
  id: 'trending_now',
  title: 'Trending Now',
  subtitle: 'What the world is playing today',
  searchQuery: 'trending songs right now 2025 viral hits',
  gradient: [Color(0xFFFF6B6B), Color(0xFFFFD93D)],
  icon: Icons.trending_up_rounded,
  emoji: '🔥',
  limit: 25,
);
