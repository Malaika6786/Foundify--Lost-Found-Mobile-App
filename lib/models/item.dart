class Item {
  final String id;
  final String title;
  final String description;
  final String status;

  // Images
  final String? imageUrl; // legacy single image
  final List<String>? imageUrls; // multiple images support

  // Location
  final double? latitude;
  final double? longitude;

  // User info
  final String? userId; // references profiles.id
  final String? avatarUrl; // from profiles.avatar_url
  final String? username; // from profiles.username

  // Extra fields
  final double? reward; // reward offered by owner
  bool returned; // whether item reached its owner
  final String? category; // e.g. Bags, Wallet, Keys (best-effort, may be null)
  final String? locationLabel; // human readable place name, if available

  final DateTime? createdAt;
  final DateTime? boostedUntil; // set by boost_item RPC, see migration 0022

  /// True while a "Boost this post" (rewarded ad) is still in effect.
  bool get isBoosted =>
      boostedUntil != null && boostedUntil!.isAfter(DateTime.now());

  Item({
    required this.id,
    required this.title,
    required this.description,
    required this.status,
    this.imageUrl,
    this.imageUrls,
    this.latitude,
    this.longitude,
    this.userId,
    this.avatarUrl,
    this.username,
    this.reward,
    this.returned = false,
    this.category,
    this.locationLabel,
    this.createdAt,
    this.boostedUntil,
  });

  factory Item.fromMap(Map<String, dynamic> m) {
    final profile = m['profiles'] ?? {}; // nested profile map if joined

    return Item(
      id: m['id'] as String,
      title: (m['title'] ?? '') as String,
      description: (m['description'] ?? '') as String,
      status: (m['status'] ?? 'lost') as String,

      // image
      imageUrl: m['image_url'] as String?,
      imageUrls: m['image_urls'] != null
          ? List<String>.from(m['image_urls'])
          : null,

      // location — DB columns are `lat`/`lng` (see supabase/migrations/0002),
      // not `latitude`/`longitude`.
      latitude: (m['lat'] as num?)?.toDouble(),
      longitude: (m['lng'] as num?)?.toDouble(),

      // user
      userId: m['user_id'] as String?,
      username:
          (m['username'] as String?) ??
          (profile['username'] as String?) ??
          'Unknown user',
      avatarUrl:
          (m['avatar_url'] as String?) ?? (profile['avatar_url'] as String?),

      // extra
      reward: m['reward'] != null ? (m['reward'] as num).toDouble() : null,
      returned: m['returned'] ?? false,
      category: m['category'] as String?,
      locationLabel: m['location_label'] as String?,

      createdAt: m['created_at'] != null
          ? DateTime.tryParse(m['created_at'])
          : null,
      boostedUntil: m['boosted_until'] != null
          ? DateTime.tryParse(m['boosted_until'])
          : null,
    );
  }
}
