// lib/services/supabase_service.dart

import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../models/item.dart';
import '../supabase_options.dart';

/// Per-item like/comment engagement, batch-fetched for a page of items.
class ItemEngagement {
  final bool liked;
  final int likeCount;
  final int commentCount;
  const ItemEngagement({
    required this.liked,
    required this.likeCount,
    required this.commentCount,
  });
}

/// Centralized Supabase service used across the app.
/// Maintains features: Auth, Storage, Items, Profiles, Alerts, Item Tags,
/// Notifications, Matches, Safe Meetup Spots, Claims, Chats, Search.
class SupabaseService {
  static SupabaseClient get supabase => Supabase.instance.client;
  static final client = Supabase.instance.client;

  // ---------------- AUTH ----------------
  /// The `profiles` row for this account is created server-side by the
  /// `handle_new_user` trigger (see
  /// supabase/migrations/0014_auto_create_profile_on_signup.sql), not by
  /// the client — a client-side upsert run right after signUp() used to be
  /// how this worked, but it silently failed whenever the project requires
  /// email confirmation (no session exists yet at that point, so RLS
  /// rejects the insert), leaving the account with no profile row at all.
  /// name/username/phone are passed as signup metadata instead, which the
  /// trigger reads from `raw_user_meta_data`.
  static Future<AuthResponse> signUp(
    String email,
    String password, {
    String? name,
    String? phone,
  }) {
    return supabase.auth.signUp(
      email: email,
      password: password,
      // Without this, the "Confirm your email" link falls back to
      // Supabase's default Site URL (often left as localhost from initial
      // project setup) — same class of bug already fixed for Google
      // Sign-In and password reset. This points it at the same callback
      // scheme already registered in AndroidManifest.xml, so confirming
      // opens the app directly instead of a browser tab that goes nowhere.
      emailRedirectTo: kIsWeb
          ? Uri.base.origin
          : 'io.supabase.flutter://login-callback/',
      data: {
        if (name != null && name.isNotEmpty) 'full_name': name,
        if (name != null && name.isNotEmpty) 'username': name,
        if (phone != null && phone.isNotEmpty) 'phone': phone,
      },
    );
  }

  static Future<AuthResponse> signIn(String email, String password) {
    return supabase.auth.signInWithPassword(email: email, password: password);
  }

  static Future<void> signOut() async {
    await supabase.auth.signOut();
  }

  static User? currentUser() => supabase.auth.currentUser;

  /// Signs in with Google. On Android/iOS this uses the native account
  /// picker (google_sign_in) rather than a browser-redirect OAuth flow —
  /// no deep link, no redirect URL allowlist to misconfigure, and no
  /// password ever asked, matching how "Sign in with Google" works in
  /// most other apps. Requires the Google provider to be enabled in
  /// Supabase Dashboard -> Authentication -> Providers, and
  /// SupabaseOptions.googleWebClientId to be set to the Web OAuth Client
  /// ID entered there.
  ///
  /// Returns true if a session was created, false if the user cancelled
  /// the account picker (not an error — just no-op back to the login
  /// screen).
  static Future<bool> signInWithGoogle() async {
    if (kIsWeb) {
      // Browser redirect is still the right approach on web — there's no
      // native account picker in a browser tab. Redirects back to
      // wherever this page actually is (not whatever Supabase's dashboard
      // "Site URL" happens to be set to — passing null falls back to
      // that, which broke redirects on any host other than the one
      // configured there).
      return supabase.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: Uri.base.origin,
      );
    }

    final googleUser = await GoogleSignIn(
      serverClientId: SupabaseOptions.googleWebClientId,
    ).signIn();
    if (googleUser == null) return false; // user dismissed the picker

    final googleAuth = await googleUser.authentication;
    final idToken = googleAuth.idToken;
    if (idToken == null) {
      throw const AuthException(
        'Google sign-in did not return an ID token.',
      );
    }

    final res = await supabase.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
      accessToken: googleAuth.accessToken,
    );
    return res.session != null;
  }

  /// Without `redirectTo`, Supabase falls back to whatever the project's
  /// dashboard "Site URL" happens to be (often a placeholder like
  /// localhost) — the reset link would send the user somewhere with
  /// nothing there, same class of bug fixed for Google Sign-In. This
  /// points it at the same callback scheme already registered in
  /// AndroidManifest.xml, which brings the user back into the app with a
  /// recovery session that main.dart routes to ResetPasswordScreen.
  static Future<void> sendPasswordResetEmail(String email) {
    return supabase.auth.resetPasswordForEmail(
      email,
      redirectTo: kIsWeb ? Uri.base.origin : 'io.supabase.flutter://login-callback/',
    );
  }

  /// Permanently deletes the current user's account and owned data via the
  /// `delete-account` Edge Function (needs the service-role key, which never
  /// ships to the client, so this must run server-side).
  static Future<void> deleteAccount() async {
    final session = supabase.auth.currentSession;
    if (session == null) throw Exception('Not logged in');

    final res = await supabase.functions.invoke(
      'delete-account',
      headers: {'Authorization': 'Bearer ${session.accessToken}'},
    );
    if (res.status != 200) {
      final err = (res.data is Map) ? res.data['error'] : res.data;
      throw Exception('Failed to delete account: $err');
    }
    await supabase.auth.signOut();
  }

  // ---------------- STORAGE ----------------
  /// Upload raw bytes to the `item-images` bucket and return public URL
  static Future<String?> uploadImage(Uint8List bytes, String filename) async {
    final user = supabase.auth.currentUser;
    if (user == null) throw Exception('Not logged in');

    final path = 'public/$filename';
    await supabase.storage
        .from('item-images')
        .uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: true),
        );

    return supabase.storage.from('item-images').getPublicUrl(path);
  }

  /// Convenience: upload multiple images (list of bytes) and return list of public URLs.
  /// Returns a List<String> of successful uploads (skips failures).
  static Future<List<String>> uploadMultipleImages(
    List<Uint8List> bytesList, {
    String? directoryPrefix,
  }) async {
    if (bytesList.isEmpty) return <String>[];
    final uploaded = <String>[];
    final uuid = const Uuid();

    for (final bytes in bytesList) {
      try {
        final filename = '${uuid.v4()}.jpg';

        // build path safely: 'public/<prefix>/<filename>' or 'public/<filename>'
        String path;
        if (directoryPrefix != null && directoryPrefix.trim().isNotEmpty) {
          final cleanPrefix = directoryPrefix.trim().replaceAll(
            RegExp(r'^/+|/+$'),
            '',
          );
          path = 'public/$cleanPrefix/$filename';
        } else {
          path = 'public/$filename';
        }

        await supabase.storage
            .from('item-images')
            .uploadBinary(
              path,
              bytes,
              fileOptions: const FileOptions(upsert: true),
            );

        final url = supabase.storage.from('item-images').getPublicUrl(path);
        uploaded.add(url);
      } catch (e) {
        // don't fail the whole batch — skip this image and continue.
        continue;
      }
    }
    return uploaded;
  }

  static Future<void> deleteImage(String filename) async {
    await supabase.storage.from('item-images').remove(['public/$filename']);
  }

  // ---------------- ITEMS ----------------
  /// Create an item (extended to support multiple images, reward, username & avatar snapshot).
  /// Backwards-compatible: existing callers that do not pass imageUrls/reward/username/avatarUrl will continue to work.
  static Future<String> createItem({
    required String title,
    required String description,
    required String status,
    String? imageUrl, // legacy single image
    List<String>? imageUrls, // new: multiple image URLs
    double? reward, // new: reward amount
    double? lat,
    double? lng,
    required String userId, // required FK
    String? username, // optional snapshot of poster's username
    String? avatarUrl, // optional snapshot of poster's avatar
    String? category, // best-effort: only persisted if the column exists
    String? locationLabel,
  }) async {
    final data = <String, dynamic>{
      'title': title,
      'description': description,
      'status': status,
      'image_url': imageUrl,
      'image_urls': imageUrls, // requires DB column (text[] or jsonb)
      'reward': reward,
      'lat': lat,
      'lng': lng,
      'user_id': userId,
      'username': username,
      'avatar_url': avatarUrl,
      'created_at': DateTime.now().toIso8601String(),
    };

    // remove null values to keep DB insert clean
    data.removeWhere((key, value) => value == null);

    // category/location_label are new optional columns — try to include them,
    // but degrade gracefully if the live schema doesn't have them yet.
    final withExtras = Map<String, dynamic>.from(data);
    if (category != null) withExtras['category'] = category;
    if (locationLabel != null) withExtras['location_label'] = locationLabel;

    try {
      final inserted = await client
          .from('items')
          .insert(withExtras)
          .select('id')
          .single();
      return inserted['id'] as String;
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST204' ||
          (e.message.contains('column') &&
              e.message.contains('does not exist'))) {
        final inserted = await client
            .from('items')
            .insert(data)
            .select('id')
            .single();
        return inserted['id'] as String;
      } else {
        rethrow;
      }
    }
  }

  /// Flexible item fetch used by Home/Search screens: optional status
  /// ("lost"/"found"), category and free-text title search.
  static const int defaultPageSize = 20;

  static Future<List<Item>> fetchItems({
    String? status,
    String? category,
    String? query,
    int? limit,
    int offset = 0,
  }) async {
    // No `profiles` join here: profiles RLS is owner-only (see
    // 0009_secure_profiles_contact.sql), so an embed by FK name would only
    // ever resolve for the current user's own items. Every item snapshots
    // the poster's username/avatar_url at creation time (createItem) as a
    // fallback, but attachLivePosterInfo below overrides that snapshot with
    // the poster's CURRENT profile data (same pattern as listComments) —
    // otherwise every old post keeps showing whatever name/photo the
    // poster had at the moment they posted, forever, even after they
    // update their profile.
    dynamic builder = supabase
        .from('items')
        .select('*')
        .isFilter('deleted_at', null);

    if (status != null) builder = builder.eq('status', status);
    if (category != null) builder = builder.eq('category', category);
    if (query != null && query.trim().isNotEmpty) {
      builder = builder.ilike('title', '%${query.trim()}%');
    }

    dynamic ordered = builder.order('created_at', ascending: false);
    if (limit != null) ordered = ordered.range(offset, offset + limit - 1);

    List data;
    try {
      data = await ordered;
    } on PostgrestException {
      // category column may not exist on the live schema yet — retry without it.
      if (category != null) {
        return fetchItems(
          status: status,
          query: query,
          limit: limit,
          offset: offset,
        );
      }
      rethrow;
    }

    final maps = data.map((m) => Map<String, dynamic>.from(m as Map)).toList();
    await attachLivePosterInfo(maps);
    final items = maps.map(Item.fromMap).toList();

    // Actively-boosted items ("Boost this post" — the reward behind the
    // rewarded ad, see migration 0022) surface higher in the feed. A
    // manual partition-and-concat instead of items.sort(...) so relative
    // order within each group is preserved exactly as the server returned
    // it (List.sort in Dart isn't guaranteed stable).
    final boosted = items.where((i) => i.isBoosted).toList();
    final rest = items.where((i) => !i.isBoosted).toList();
    return [...boosted, ...rest];
  }

  /// Overrides each item map's snapshotted `username`/`avatar_url` with the
  /// poster's current profile data, in place, via one batched
  /// `profiles_public` lookup — mirrors the fix already applied to
  /// listComments. Falls back to leaving the snapshot untouched for any
  /// poster whose profile can't be found (e.g. a deleted account), so a
  /// missing profile never makes a post show blank instead of its
  /// original snapshot.
  static Future<void> attachLivePosterInfo(
    List<Map<String, dynamic>> items,
  ) async {
    final userIds = items
        .map((m) => m['user_id'] as String?)
        .whereType<String>()
        .toSet()
        .toList();
    if (userIds.isEmpty) return;

    final profiles = await supabase
        .from('profiles_public')
        .select('id, username, avatar_url')
        .inFilter('id', userIds);
    final byId = {
      for (final p in (profiles as List))
        (p['id']).toString(): Map<String, dynamic>.from(p as Map),
    };

    for (final m in items) {
      final profile = byId[m['user_id']?.toString()];
      if (profile == null) continue;
      m['username'] = profile['username'] ?? m['username'];
      m['avatar_url'] = profile['avatar_url'] ?? m['avatar_url'];
    }
  }

  /// One item by id — used to open ItemDetailScreen from a notification
  /// (like/comment/match/resolved/new_post), which only stores the item id.
  static Future<Item?> getItemById(String itemId) async {
    final res = await supabase
        .from('items')
        .select('*')
        .eq('id', itemId)
        .maybeSingle();
    if (res == null) return null;
    final map = Map<String, dynamic>.from(res as Map);
    await attachLivePosterInfo([map]);
    return Item.fromMap(map);
  }

  /// Items belonging to one user — used by the Profile screen instead of
  /// pulling every item in the app and filtering client-side.
  static Future<List<Item>> fetchItemsByUser(String userId) async {
    final data = await supabase
        .from('items')
        .select('*')
        .eq('user_id', userId)
        .isFilter('deleted_at', null)
        .order('created_at', ascending: false);
    final maps = (data as List)
        .map((m) => Map<String, dynamic>.from(m as Map))
        .toList();
    await attachLivePosterInfo(maps);
    return maps.map(Item.fromMap).toList();
  }

  /// Total number of items ever marked resolved — shown as a social-proof
  /// stat on the Home feed.
  static Future<int> countReturnedItems() async {
    final res = await supabase
        .from('items')
        .select('id')
        .eq('returned', true)
        .isFilter('deleted_at', null)
        .count(CountOption.exact);
    return res.count;
  }

  // ---------------- LIKES ----------------
  static Future<void> toggleLike(String itemId) async {
    final user = supabase.auth.currentUser;
    if (user == null) throw Exception('Not logged in');

    final existing = await supabase
        .from('likes')
        .select('id')
        .eq('post_id', itemId)
        .eq('user_id', user.id)
        .maybeSingle();

    if (existing != null) {
      await supabase.from('likes').delete().eq('id', existing['id']);
    } else {
      await supabase.from('likes').insert({
        'post_id': itemId,
        'user_id': user.id,
      });
    }
  }

  static Future<int> countLikes(String itemId) async {
    final res = await supabase
        .from('likes')
        .select('id')
        .eq('post_id', itemId)
        .count(CountOption.exact);
    return res.count;
  }

  static Future<bool> hasUserLiked(String itemId) async {
    final user = supabase.auth.currentUser;
    if (user == null) return false;
    final rows = await supabase
        .from('likes')
        .select('id')
        .eq('post_id', itemId)
        .eq('user_id', user.id);
    return (rows as List).isNotEmpty;
  }

  // ---------------- COMMENTS ----------------
  static Future<List<Map<String, dynamic>>> listComments(String itemId) async {
    final data = await supabase
        .from('comments')
        .select('id, content, created_at, user_id')
        .eq('post_id', itemId)
        .order('created_at', ascending: false);
    final comments = (data as List)
        .map((m) => Map<String, dynamic>.from(m as Map))
        .toList();
    if (comments.isEmpty) return comments;

    // `profiles` RLS is owner-only, so a joined embed by FK name would
    // silently return null for every commenter but yourself. Batch-fetch
    // the safe public columns instead, via the `profiles_public` view.
    final userIds = comments
        .map((c) => c['user_id'] as String)
        .toSet()
        .toList();
    final profiles = await supabase
        .from('profiles_public')
        .select('id, username, avatar_url')
        .inFilter('id', userIds);
    final byId = {
      for (final p in (profiles as List))
        (p['id']).toString(): Map<String, dynamic>.from(p as Map),
    };
    for (final c in comments) {
      c['profiles'] = byId[c['user_id'].toString()];
    }
    return comments;
  }

  static Future<void> addComment(String itemId, String content) async {
    final user = supabase.auth.currentUser;
    if (user == null) throw Exception('Not logged in');
    await supabase.from('comments').insert({
      'post_id': itemId,
      'user_id': user.id,
      'content': content,
    });
  }

  /// Batched like/comment engagement for a whole page of items — used by the
  /// Home feed instead of each FeedPostCard firing 3 separate queries per
  /// post (was up to 3xN requests for N posts on screen).
  static Future<Map<String, ItemEngagement>> fetchEngagementForItems(
    List<String> itemIds,
  ) async {
    if (itemIds.isEmpty) return {};
    final user = supabase.auth.currentUser;

    final likesFuture = supabase
        .from('likes')
        .select('post_id, user_id')
        .inFilter('post_id', itemIds);
    final commentsFuture = supabase
        .from('comments')
        .select('post_id')
        .inFilter('post_id', itemIds);

    final results = await Future.wait([likesFuture, commentsFuture]);
    final likeRows = results[0] as List;
    final commentRows = results[1] as List;

    final likeCounts = <String, int>{};
    final likedByMe = <String>{};
    for (final row in likeRows) {
      final postId = row['post_id'].toString();
      likeCounts[postId] = (likeCounts[postId] ?? 0) + 1;
      if (user != null && row['user_id'] == user.id) likedByMe.add(postId);
    }

    final commentCounts = <String, int>{};
    for (final row in commentRows) {
      final postId = row['post_id'].toString();
      commentCounts[postId] = (commentCounts[postId] ?? 0) + 1;
    }

    return {
      for (final id in itemIds)
        id: ItemEngagement(
          liked: likedByMe.contains(id),
          likeCount: likeCounts[id] ?? 0,
          commentCount: commentCounts[id] ?? 0,
        ),
    };
  }

  static Future<int> countComments(String itemId) async {
    final res = await supabase
        .from('comments')
        .select('id')
        .eq('post_id', itemId)
        .count(CountOption.exact);
    return res.count;
  }

  // ---------------- PROFILES ----------------
  static Future<Map<String, dynamic>?> getProfile(String userId) async {
    final res = await supabase
        .from('profiles')
        .select()
        .eq('id', userId)
        .maybeSingle();
    if (res == null) return null;
    return Map<String, dynamic>.from(res as Map);
  }

  /// Safe public columns only (no phone/email) — for showing OTHER users'
  /// username/avatar (e.g. chat list, comments). `profiles` RLS is
  /// owner-only, so a plain `getProfile` call for someone else's id would
  /// return nothing.
  static Future<Map<String, dynamic>?> getPublicProfile(String userId) async {
    final res = await supabase
        .from('profiles_public')
        .select()
        .eq('id', userId)
        .maybeSingle();
    if (res == null) return null;
    return Map<String, dynamic>.from(res as Map);
  }

  /// Searches other users by username, for starting a new chat — used by
  /// the "New Message" search on the Chat List screen. Never returns the
  /// current user (can't start a chat with yourself) or phone/email (reads
  /// from `profiles_public`, which never carries those columns).
  static Future<List<Map<String, dynamic>>> searchUsersByUsername(
    String query,
  ) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];
    final me = supabase.auth.currentUser?.id;

    dynamic builder = supabase
        .from('profiles_public')
        .select('id, username, avatar_url')
        .ilike('username', '%$trimmed%');
    if (me != null) builder = builder.neq('id', me);

    final res = await builder.limit(20);
    return (res as List)
        .map((m) => Map<String, dynamic>.from(m as Map))
        .where((m) => m['username'] != null)
        .toList();
  }

  /// Phone/email of the reporter of one specific item, via a security
  /// definer RPC scoped to that item — used by the "Contact Reporter" sheet.
  /// Never queries the `profiles` table directly for another user's row
  /// (that's now blocked by RLS, by design — see
  /// supabase/migrations/0009_secure_profiles_contact.sql).
  static Future<Map<String, dynamic>?> getItemReporterContact(
    String itemId,
  ) async {
    final res = await supabase.rpc(
      'get_item_reporter_contact',
      params: {'p_item_id': itemId},
    );
    final rows = res as List?;
    if (rows == null || rows.isEmpty) return null;
    return Map<String, dynamic>.from(rows.first as Map);
  }

  static Future<void> updateProfile({
    String? fullName,
    String? username,
    String? avatarUrl,
    String? phone,
    bool? notificationsEnabled,
  }) async {
    final user = supabase.auth.currentUser;
    if (user == null) throw Exception('Not logged in');

    final updates = <String, dynamic>{};
    if (fullName != null) updates['full_name'] = fullName;
    if (username != null) updates['username'] = username;
    if (avatarUrl != null) updates['avatar_url'] = avatarUrl;
    if (phone != null) updates['phone'] = phone;
    if (notificationsEnabled != null) {
      updates['notifications_enabled'] = notificationsEnabled;
    }
    updates['updated_at'] = DateTime.now().toUtc().toIso8601String();

    // A real UPDATE, not upsert(): `.upsert()` builds an INSERT ... ON
    // CONFLICT DO UPDATE under the hood, and Postgres validates NOT NULL
    // columns (like `email`) against that INSERT's full candidate row
    // *before* it even checks whether the conflict path will be taken —
    // so any partial upsert that omits a NOT NULL column (this one never
    // includes `email`) fails outright, even though the row already
    // exists and only an update was ever intended. That was the actual
    // cause of "Something went wrong" on every profile/avatar save.
    final updated = await supabase
        .from('profiles')
        .update(updates)
        .eq('id', user.id)
        .select('id');

    if ((updated as List).isEmpty) {
      // Row genuinely doesn't exist (should be rare now that
      // handle_new_user creates it at signup — see migration 0014).
      // Insert a full row instead of silently doing nothing.
      await supabase.from('profiles').insert({
        'id': user.id,
        'email': user.email,
        ...updates,
      });
    }
  }

  // ---------------- ALERT PREFERENCES ----------------
  static Future<Map<String, dynamic>> getAlertPrefs() async {
    final user = supabase.auth.currentUser;
    if (user == null) throw Exception('Not logged in');

    final res = await supabase
        .from('alert_prefs')
        .select()
        .eq('user_id', user.id)
        .maybeSingle();
    if (res != null) return Map<String, dynamic>.from(res as Map);

    return {
      'radius_km': 3.0,
      'categories': <String>['Bags', 'Wallet'],
      'push_enabled': true,
      'ai_only': false,
    };
  }

  static Future<void> saveAlertPrefs({
    required double radiusKm,
    required List<String> categories,
    required bool pushEnabled,
    required bool aiOnly,
  }) async {
    final user = supabase.auth.currentUser;
    if (user == null) throw Exception('Not logged in');

    await supabase.from('alert_prefs').upsert({
      'user_id': user.id,
      'radius_km': radiusKm,
      'categories': categories,
      'push_enabled': pushEnabled,
      'ai_only': aiOnly,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  // ---------------- ITEM TAGS (QR) ----------------
  static Future<List<Map<String, dynamic>>> listItemTags() async {
    final user = supabase.auth.currentUser;
    if (user == null) return [];
    final res = await supabase
        .from('item_tags')
        .select()
        .eq('user_id', user.id)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(res as List);
  }

  static Future<void> createItemTag({
    required String label,
    String? itemId,
  }) async {
    final user = supabase.auth.currentUser;
    if (user == null) throw Exception('Not logged in');
    final code = 'FK-${(1000 + DateTime.now().millisecondsSinceEpoch % 9000)}';
    await supabase.from('item_tags').insert({
      'user_id': user.id,
      'label': label,
      'code': code,
      'item_id': itemId,
    });
  }

  static Future<void> setItemTagActive(String tagId, bool active) async {
    await supabase.from('item_tags').update({'active': active}).eq('id', tagId);
  }

  /// Public lookup used by the "scan a tag" landing page — no login required.
  /// Uses the `item_tags_public` view (id, code, label, active only) so an
  /// anonymous scanner can never see the tag owner's user_id.
  static Future<Map<String, dynamic>?> lookupItemTagByCode(String code) async {
    final res = await supabase
        .from('item_tags_public')
        .select()
        .eq('code', code)
        .maybeSingle();
    return res == null ? null : Map<String, dynamic>.from(res as Map);
  }

  /// Submits a message from an unauthenticated finder who scanned a tag.
  /// No login required — RLS allows this insert for any active tag.
  static Future<void> submitTagMessage({
    required String tagId,
    String? finderName,
    String? finderContact,
    required String message,
  }) async {
    await supabase.from('tag_messages').insert({
      'tag_id': tagId,
      'finder_name': finderName,
      'finder_contact': finderContact,
      'message': message,
    });
  }

  /// Messages left on one of the current user's tags (owner-only via RLS).
  static Future<List<Map<String, dynamic>>> listTagMessages(
    String tagId,
  ) async {
    final res = await supabase
        .from('tag_messages')
        .select()
        .eq('tag_id', tagId)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(res as List);
  }

  /// Deletes one message left on a tag the current user owns (RLS-enforced).
  static Future<void> deleteTagMessage(String messageId) async {
    await supabase.from('tag_messages').delete().eq('id', messageId);
  }

  // ---------------- PUSH NOTIFICATIONS (device tokens) ----------------
  static Future<void> registerDeviceToken(
    String token, {
    String platform = 'android',
  }) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    await supabase.from('device_tokens').upsert({
      'token': token,
      'user_id': user.id,
      'platform': platform,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  static Future<void> unregisterDeviceToken(String token) async {
    await supabase.from('device_tokens').delete().eq('token', token);
  }

  // ---------------- NOTIFICATIONS ----------------
  static Future<List<Map<String, dynamic>>> listNotifications() async {
    final user = supabase.auth.currentUser;
    if (user == null) return [];
    final res = await supabase
        .from('notifications')
        .select()
        .eq('user_id', user.id)
        .order('created_at', ascending: false)
        .limit(50);
    return List<Map<String, dynamic>>.from(res as List);
  }

  static Future<void> markNotificationRead(String id) async {
    await supabase.from('notifications').update({'read': true}).eq('id', id);
  }

  static Future<void> markAllNotificationsRead() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    await supabase
        .from('notifications')
        .update({'read': true})
        .eq('user_id', user.id)
        .eq('read', false);
  }

  /// Marks every message notification from one sender as read in one go —
  /// used when tapping a grouped "N messages from X" entry, matching how
  /// WhatsApp clears a whole conversation's unread badge on open.
  static Future<void> markMessageNotificationsReadForSender(
    String senderId,
  ) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    await supabase
        .from('notifications')
        .update({'read': true})
        .eq('user_id', user.id)
        .eq('type', 'message')
        .eq('related_user_id', senderId);
  }

  static Future<int> unreadNotificationCount() async {
    final user = supabase.auth.currentUser;
    if (user == null) return 0;
    final res = await supabase
        .from('notifications')
        .select('id')
        .eq('user_id', user.id)
        .eq('read', false);
    return (res as List).length;
  }

  // ---------------- MATCHES (server-scored, backs Possible Matches) ----------------
  static Future<List<Map<String, dynamic>>> listMatchesForLostItem(
    String lostItemId,
  ) async {
    final res = await supabase
        .from('item_matches')
        .select('*, found:items!item_matches_found_item_id_fkey(*)')
        .eq('lost_item_id', lostItemId)
        .eq('dismissed', false)
        .order('score', ascending: false);
    final rows = List<Map<String, dynamic>>.from(res as List);

    // Same stale-poster-info fix as fetchItems — the nested `found` item
    // still carries its creation-time username/avatar_url snapshot, so
    // override it with the poster's current profile before returning.
    // Indices are tracked explicitly (not a parallel filtered list) so a
    // row with no `found` match can never misalign the mapping back.
    final foundByRowIndex = <int, Map<String, dynamic>>{};
    for (var i = 0; i < rows.length; i++) {
      final found = rows[i]['found'];
      if (found is Map) {
        foundByRowIndex[i] = Map<String, dynamic>.from(found);
      }
    }
    await attachLivePosterInfo(foundByRowIndex.values.toList());
    foundByRowIndex.forEach((i, map) => rows[i]['found'] = map);
    return rows;
  }

  static Future<void> dismissMatch(String matchId) async {
    await supabase
        .from('item_matches')
        .update({'dismissed': true})
        .eq('id', matchId);
  }

  // ---------------- SAFE MEETUP SPOTS ----------------
  static Future<List<Map<String, dynamic>>> listSafeSpots() async {
    final res = await supabase
        .from('safe_spots')
        .select()
        .order('verified', ascending: false)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(res as List);
  }

  /// Adds a user-submitted meetup spot. Not pre-verified — real vetting
  /// (e.g. an admin marking it "verified") isn't built yet, so every
  /// custom spot starts as unverified and is clearly labeled as such.
  static Future<Map<String, dynamic>> createSafeSpot({
    required String name,
    required String description,
  }) async {
    final inserted = await supabase
        .from('safe_spots')
        .insert({'name': name, 'description': description, 'verified': false})
        .select()
        .single();
    return Map<String, dynamic>.from(inserted as Map);
  }

  static Future<void> proposeMeetup({
    required String itemId,
    required String safeSpotId,
  }) async {
    final user = supabase.auth.currentUser;
    if (user == null) throw Exception('Not logged in');
    await supabase.from('meetup_proposals').insert({
      'item_id': itemId,
      'proposed_by': user.id,
      'safe_spot_id': safeSpotId,
    });
  }

  // ---------------- CLAIMS (drop-off pickup flow) ----------------
  static Future<Map<String, dynamic>?> getExistingClaim(String itemId) async {
    final res = await supabase
        .from('claims')
        .select()
        .eq('item_id', itemId)
        .maybeSingle();
    return res == null ? null : Map<String, dynamic>.from(res as Map);
  }

  static Future<List<Map<String, dynamic>>> listInstitutionPartners() async {
    final res = await supabase
        .from('institution_partners')
        .select()
        .order('verified', ascending: false)
        .order('name');
    return List<Map<String, dynamic>>.from(res as List);
  }

  /// Adds a user-submitted drop-off partner (e.g. a mall security desk, a
  /// campus lost & found office). Not pre-verified — same "Unverified" label
  /// pattern as custom meetup spots, since there's no vetting step built yet.
  static Future<Map<String, dynamic>> createInstitutionPartner({
    required String name,
    required String address,
  }) async {
    final inserted = await supabase
        .from('institution_partners')
        .insert({'name': name, 'address': address, 'verified': false})
        .select()
        .single();
    return Map<String, dynamic>.from(inserted as Map);
  }

  /// Creates the claim for an item at an explicitly chosen partner — no more
  /// silently grabbing whichever partner happened to be first in the table.
  static Future<Map<String, dynamic>> createClaim({
    required String itemId,
    required String partnerId,
  }) async {
    final user = supabase.auth.currentUser;
    if (user == null) throw Exception('Not logged in');

    final code = (100000 + DateTime.now().millisecondsSinceEpoch % 900000)
        .toString();

    final inserted = await supabase
        .from('claims')
        .insert({
          'item_id': itemId,
          'claimant_id': user.id,
          'partner_id': partnerId,
          'pickup_code': code,
        })
        .select()
        .single();
    return Map<String, dynamic>.from(inserted as Map);
  }

  /// Confirming pickup is done by the CLAIMANT, not the item's owner — a
  /// direct client-side `items.update({returned:true})` used to silently
  /// match zero rows (no error) because `items` UPDATE RLS is owner-only,
  /// so the item never actually got marked resolved. This RPC validates
  /// the caller is really the claim's claimant server-side and updates
  /// both rows together — see
  /// supabase/migrations/0015_notifications_upgrade_and_claim_fix.sql.
  static Future<void> confirmPickup(String claimId, String itemId) async {
    await supabase.rpc('confirm_claim_pickup', params: {'p_claim_id': claimId});
  }

  // ---------------- CHATS & MESSAGES ----------------

  static Future<String> getOrCreateChat(String receiverId) =>
      getOrCreatePrivateChat(receiverId);

  /// [itemId], when given, is remembered on the chat row (only set once, at
  /// creation) so the item being discussed stays visible every time this
  /// chat is reopened — not just the first time, from the contact sheet.
  static Future<String> getOrCreatePrivateChat(
    String receiverId, {
    String? itemId,
  }) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('Not logged in');

    final existing1 = await supabase
        .from('chats')
        .select()
        .eq('user1', userId)
        .eq('user2', receiverId)
        .maybeSingle();

    if (existing1 != null) {
      return existing1['id'].toString();
    }

    final existing2 = await supabase
        .from('chats')
        .select()
        .eq('user1', receiverId)
        .eq('user2', userId)
        .maybeSingle();

    if (existing2 != null) {
      return existing2['id'].toString();
    }

    final insertRow = <String, dynamic>{'user1': userId, 'user2': receiverId};
    if (itemId != null) insertRow['related_item_id'] = itemId;

    final inserted = await supabase
        .from('chats')
        .insert(insertRow)
        .select()
        .single();

    return inserted['id'].toString();
  }

  /// The item a chat was started about, if any — used to show a persistent
  /// "you're talking about: <item>" banner regardless of how the chat was
  /// reopened (Messages list vs. an item's contact sheet).
  static Future<Item?> getChatRelatedItem(String chatId) async {
    final chat = await supabase
        .from('chats')
        .select('related_item_id')
        .eq('id', chatId)
        .maybeSingle();
    final itemId = chat?['related_item_id'] as String?;
    if (itemId == null) return null;
    return getItemById(itemId);
  }

  static Future<List<Map<String, dynamic>>> fetchMessages(String chatId) async {
    final res = await supabase
        .from('messages')
        .select()
        .eq('chat_id', chatId)
        .order('created_at', ascending: true);

    return List<Map<String, dynamic>>.from(res);
  }

  /// Emits the chat's full message list on every insert/update/delete —
  /// not just new messages. Previously this only ever handed back
  /// `event.last` (the single newest row), which meant an UPDATE to an
  /// older message — exactly what marking a message "read" is — never
  /// reached the UI at all unless that message happened to already be the
  /// last one in the chat. Returning the whole snapshot lets the caller
  /// simply replace its list each time, so both new messages and read-
  /// status changes on existing ones show up correctly.
  static Stream<List<Map<String, dynamic>>> messageStream(String chatId) {
    return supabase
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('chat_id', chatId)
        .order('created_at');
  }

  /// Marks every message from the other participant in [chatId] as read.
  /// Safe to call anytime (e.g. on opening the chat, and again whenever a
  /// new incoming message arrives while it's open) — a no-op if there's
  /// nothing unread.
  static Future<void> markMessagesRead(String chatId) async {
    await supabase.rpc('mark_messages_read', params: {'p_chat_id': chatId});
  }

  /// Marks every message sent TO the current user, across all their chats,
  /// as delivered — called when the chat list loads, since that already
  /// means this device has synced the data (same "delivered" semantics as
  /// most chat apps: as soon as the recipient's device is online, before
  /// they've necessarily opened that specific conversation).
  static Future<void> markAllMessagesDelivered() async {
    await supabase.rpc('mark_all_messages_delivered');
  }

  static Future<Map<String, dynamic>> sendMessage(
    String chatId,
    String text, {
    String? attachmentUrl,
  }) async {
    final user = supabase.auth.currentUser;
    if (user == null) throw Exception('Not logged in');

    final row = <String, dynamic>{
      'chat_id': chatId,
      'sender_id': user.id,
      'content': text,
      'created_at': DateTime.now().toIso8601String(), // add timestamp
    };
    if (attachmentUrl != null) row['attachment_url'] = attachmentUrl;

    return await supabase.from('messages').insert(row).select().single();
  }

  /// Uploads a chat image attachment and returns its public URL — used by
  /// the chat screen's attach button, which previously just showed a
  /// "coming soon" message and did nothing.
  static Future<String> uploadChatAttachment(
    Uint8List bytes,
    String chatId,
  ) async {
    final user = supabase.auth.currentUser;
    if (user == null) throw Exception('Not logged in');
    final filename = '${const Uuid().v4()}.jpg';
    final path = 'public/chat/$chatId/$filename';
    await supabase.storage
        .from('item-images')
        .uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: true),
        );
    return supabase.storage.from('item-images').getPublicUrl(path);
  }

  /// Throws on failure — callers must not remove the message from local
  /// state until this succeeds, or a rejected delete (e.g. blocked by RLS)
  /// silently reappears as "deleted" in the UI while still existing server
  /// side.
  static Future<void> deleteMessage(String messageId) async {
    await supabase.from('messages').delete().eq('id', messageId);
  }

  // ---------------- IMAGE PICK & AVATAR UPLOAD ----------------
  /// Pick an image from the gallery and return its raw bytes plus file
  /// extension, or null. Returns bytes (not a `dart:io File`) because
  /// `File` has no real filesystem backing on Flutter Web — constructing
  /// one from the picker's blob path compiles fine but throws as soon as
  /// anything tries to read it, which is exactly what was breaking avatar
  /// uploads in the web build. Bytes work identically on web, Android and
  /// iOS, matching the pattern already used for item-photo uploads.
  static Future<(Uint8List, String)?> pickImageFromGallery() async {
    final picker = ImagePicker();
    final XFile? picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 800,
      maxHeight: 800,
    );
    if (picked == null) return null;
    final bytes = await picked.readAsBytes();
    final ext = p.extension(picked.name).isNotEmpty
        ? p.extension(picked.name)
        : '.jpg';
    return (bytes, ext);
  }

  /// upload avatar bytes to storage bucket and return public URL
  static Future<String?> uploadAvatar(Uint8List bytes, String ext) async {
    final user = supabase.auth.currentUser;
    if (user == null) return null;
    final userId = user.id;
    final filePath = 'public/avatars/$userId$ext'; // path inside bucket

    await supabase.storage
        .from('avatars')
        .uploadBinary(
          filePath,
          bytes,
          fileOptions: const FileOptions(upsert: true),
        );

    // Every re-upload overwrites the same storage path (upsert: true), so
    // the public URL is byte-for-byte identical each time — without a
    // cache-busting suffix, Flutter's NetworkImage (and any CDN cache)
    // keeps showing the old photo under that same URL, making a
    // successful avatar change look like it silently did nothing.
    final publicUrl = supabase.storage.from('avatars').getPublicUrl(filePath);
    return '$publicUrl?v=${DateTime.now().millisecondsSinceEpoch}';
  }

  /// Soft-deletes the item (sets `deleted_at`) so the caller can offer a
  /// real "Undo" — see [restorePost]. Storage cleanup only happens once the
  /// undo window has passed and [purgeDeletedPostImages] is called.
  /// Same silent-RLS-failure fix as [deletePost] below — see that doc
  /// comment. This is what the item detail screen's "Mark as Resolved"
  /// button calls; a direct `.update({'returned': true})` used to appear
  /// to work but never actually persisted.
  static Future<void> markItemResolved(String itemId) async {
    await supabase.rpc('mark_item_resolved', params: {'p_item_id': itemId});
  }

  /// Marks the caller's own item boosted for 24h (see migration 0022) —
  /// called after a rewarded ad is watched through to completion. Only
  /// ever call this from the ad's onUserEarnedReward callback, not on tap,
  /// so the reward is actually earned before it's granted.
  static Future<void> boostItem(String itemId) async {
    await supabase.rpc('boost_item', params: {'p_item_id': itemId});
  }

  /// Uses a SECURITY DEFINER RPC (see
  /// supabase/migrations/0016_item_mutation_rpcs_and_chat_item_link.sql)
  /// rather than a plain client-side `.update()` — a direct update used to
  /// silently do nothing (no error, zero rows matched) whenever the
  /// `items` UPDATE RLS policy didn't cooperate, which is exactly why
  /// "Delete Post" appeared to work but the post was still there after a
  /// refresh.
  static Future<void> deletePost(String itemId) async {
    if (itemId.isEmpty) throw Exception('itemId required');
    await supabase.rpc('soft_delete_item', params: {'p_item_id': itemId});
  }

  /// Reverses [deletePost] — used by the "Undo" action on the post-delete
  /// snackbar.
  static Future<void> restorePost(String itemId) async {
    await supabase.rpc('restore_item', params: {'p_item_id': itemId});
  }

  /// Permanently removes a soft-deleted item's uploaded photos from Storage.
  /// Call once the undo window has definitely passed — never blocks or
  /// throws, since losing track of an orphaned file is far less bad than
  /// blocking on it.
  static Future<void> purgeDeletedPostImages(List<String> imageUrls) async {
    if (imageUrls.isEmpty) return;
    final paths = imageUrls
        .map(_storagePathFromPublicUrl)
        .whereType<String>()
        .toList();
    if (paths.isEmpty) return;
    try {
      await supabase.storage.from('item-images').remove(paths);
    } catch (e) {
      debugPrint('Failed to remove item images from storage: $e');
    }
  }

  /// Extracts the bucket-relative path (e.g. `public/items/<uid>/<file>.jpg`)
  /// out of a Supabase Storage public URL, or null if it doesn't match.
  static String? _storagePathFromPublicUrl(String url) {
    const marker = '/object/public/item-images/';
    final i = url.indexOf(marker);
    if (i == -1) return null;
    return url.substring(i + marker.length);
  }
}
