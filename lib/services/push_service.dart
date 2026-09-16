// lib/services/push_service.dart
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'supabase_service.dart';

/// Registers this device for push notifications and keeps its FCM token in
/// sync with the `device_tokens` table, which the `send-push` Edge Function
/// reads to deliver pushes (see supabase/migrations/0005_push_notifications.sql).
///
/// Safe to call even before Firebase has been set up (no
/// android/app/google-services.json yet) — every step is guarded so the rest
/// of the app keeps working either way; push simply stays inactive.
class PushService {
  PushService._();
  static bool _firebaseReady = false;

  static Future<void> init() async {
    if (!_firebaseReady) {
      try {
        await Firebase.initializeApp();
      } catch (e) {
        debugPrint(
          'Push notifications inactive (Firebase not configured yet): $e',
        );
        return;
      }
      _firebaseReady = true;

      // Set up exactly once per app process: onTokenRefresh always calls
      // _registerToken, which reads whichever user is signed in *at the
      // time it fires*, so one long-lived listener stays correct across
      // logout/login.
      FirebaseMessaging.instance.onTokenRefresh.listen(_registerToken);

      // Foreground messages don't show a system tray notification on
      // Android by default — the in-app Notifications screen already
      // reflects the new row via the real `notifications` table, so no
      // extra UI is needed here.
      FirebaseMessaging.onMessage.listen((message) {
        debugPrint(
          'Push received in foreground: ${message.notification?.title}',
        );
      });
    }

    // Runs on every call (i.e. every login), not just the first — this is
    // what actually re-associates this device's FCM token with whichever
    // account just logged in. Previously this whole method short-circuited
    // after the first call in a process (via a single `_initialized` flag),
    // so logging out and into a different account on the same device left
    // that device silently registered to nobody: registerDeviceToken()
    // never ran again, so the device_tokens row still pointed at the
    // previous account (or, if that account had logged out and its token
    // was unregistered, at no one at all) until the app was fully killed
    // and relaunched.
    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(alert: true, badge: true, sound: true);
    final token = await messaging.getToken();
    if (token != null) await _registerToken(token);
  }

  static Future<void> _registerToken(String token) async {
    try {
      await SupabaseService.registerDeviceToken(
        token,
        platform: (!kIsWeb && Platform.isIOS) ? 'ios' : 'android',
      );
    } catch (e) {
      debugPrint('Failed to register device token: $e');
    }
  }

  /// Call on sign-out so this device stops receiving pushes meant for the
  /// account that just logged out.
  static Future<void> unregisterCurrentDevice() async {
    if (!_firebaseReady) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await SupabaseService.unregisterDeviceToken(token);
    } catch (e) {
      debugPrint('Failed to unregister device token: $e');
    }
  }
}
