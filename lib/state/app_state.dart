import 'package:flutter/foundation.dart';
import '../services/supabase_service.dart';

/// Small app-wide state shared via Provider for data used across more than
/// one screen (the current user's profile, unread notification count) —
/// avoids each screen independently re-fetching and reloading the same
/// thing with its own ad-hoc logic. Most screens still own their own local
/// UI state (loading flags, form fields, etc.) — this only holds what's
/// genuinely shared.
class AppState extends ChangeNotifier {
  Map<String, dynamic>? _profile;
  Map<String, dynamic>? get profile => _profile;

  int _unreadNotifications = 0;
  int get unreadNotifications => _unreadNotifications;

  Future<void> loadProfile(String userId) async {
    _profile = await SupabaseService.getProfile(userId);
    notifyListeners();
  }

  void setProfile(Map<String, dynamic>? profile) {
    _profile = profile;
    notifyListeners();
  }

  Future<void> refreshUnreadCount() async {
    _unreadNotifications = await SupabaseService.unreadNotificationCount();
    notifyListeners();
  }

  /// Set directly from a live Realtime stream (see HomeScreen) so the bell
  /// badge updates the instant a new notification arrives, instead of only
  /// on app start / after visiting the Notifications screen — Home stays
  /// mounted in the bottom nav's IndexedStack, so its initState (where
  /// refreshUnreadCount used to be the only trigger) never runs again.
  void setUnreadCount(int count) {
    _unreadNotifications = count;
    notifyListeners();
  }

  /// Called on sign-out / account deletion so the next login doesn't
  /// briefly show the previous user's cached data.
  void clear() {
    _profile = null;
    _unreadNotifications = 0;
    notifyListeners();
  }
}
