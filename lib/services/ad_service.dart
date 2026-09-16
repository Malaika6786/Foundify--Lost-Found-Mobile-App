// lib/services/ad_service.dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// AdMob ad unit ids and startup wiring (SDK init + UMP consent).
class AdService {
  AdService._();

  /// Home screen banner. Falls back to Google's official test unit in debug
  /// builds so ads still render during development without touching real
  /// inventory/impressions.
  static String get homeBannerAdUnitId {
    if (kDebugMode) {
      return 'ca-app-pub-3940256099942544/9214589741'; // Google test banner
    }
    return 'ca-app-pub-2502837360597894/4167480250'; // Foundify production
  }

  /// Full-screen interstitial. Not yet shown anywhere in the app — call
  /// [loadInterstitialAd] then [showInterstitialAdIfLoaded] wherever it
  /// should actually appear once that's decided.
  static String get interstitialAdUnitId {
    if (kDebugMode) {
      return 'ca-app-pub-3940256099942544/1033173712'; // Google test interstitial
    }
    return 'ca-app-pub-2502837360597894/7974863320'; // Foundify production
  }

  /// Opt-in rewarded ad. Not yet shown anywhere in the app — call
  /// [loadRewardedAd] then [showRewardedAdIfLoaded] wherever it should
  /// actually appear once that's decided.
  static String get rewardedAdUnitId {
    if (kDebugMode) {
      return 'ca-app-pub-3940256099942544/5224354917'; // Google test rewarded
    }
    return 'ca-app-pub-2502837360597894/2088111824'; // Foundify production
  }

  static InterstitialAd? _interstitialAd;
  static RewardedAd? _rewardedAd;

  /// Lets a caller check before showing whether a rewarded ad is actually
  /// ready, so it can tell the user "not ready yet" instead of the button
  /// silently doing nothing.
  static bool get hasRewardedAdReady => _rewardedAd != null;

  /// Loads an interstitial in the background so it's ready the instant
  /// [showInterstitialAdIfLoaded] is called — interstitials always need to
  /// be pre-loaded, they can't be requested and shown in the same instant.
  static void loadInterstitialAd() {
    InterstitialAd.load(
      adUnitId: interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) => _interstitialAd = ad,
        onAdFailedToLoad: (error) {
          debugPrint('Interstitial failed to load: $error');
          _interstitialAd = null;
        },
      ),
    );
  }

  /// Shows the interstitial if one finished loading, then immediately
  /// starts loading the next one so a later call has one ready again.
  /// Silently does nothing if none is loaded yet — callers don't need to
  /// check first.
  static void showInterstitialAdIfLoaded() {
    final ad = _interstitialAd;
    if (ad == null) return;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _interstitialAd = null;
        loadInterstitialAd();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _interstitialAd = null;
        loadInterstitialAd();
      },
    );
    ad.show();
  }

  /// Loads a rewarded ad in the background, same pre-load requirement as
  /// interstitials.
  static void loadRewardedAd() {
    RewardedAd.load(
      adUnitId: rewardedAdUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) => _rewardedAd = ad,
        onAdFailedToLoad: (error) {
          debugPrint('Rewarded ad failed to load: $error');
          _rewardedAd = null;
        },
      ),
    );
  }

  /// Shows the rewarded ad if one finished loading. [onUserEarnedReward] is
  /// only called if the user actually watches it through to completion —
  /// that's the callback to hook up whatever the reward unlocks, once
  /// that's decided. Silently does nothing if none is loaded yet.
  static void showRewardedAdIfLoaded({
    required void Function(AdWithoutView ad, RewardItem reward)
    onUserEarnedReward,
  }) {
    final ad = _rewardedAd;
    if (ad == null) return;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _rewardedAd = null;
        loadRewardedAd();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _rewardedAd = null;
        loadRewardedAd();
      },
    );
    ad.show(onUserEarnedReward: onUserEarnedReward);
  }

  /// Requests the user's consent (GDPR/UK/CCPA, where applicable) via
  /// Google's User Messaging Platform, then initializes the Mobile Ads SDK.
  /// Safe to call once at app startup — if consent isn't required for this
  /// user/region, the form step is a no-op and this resolves immediately.
  static Future<void> initialize() async {
    final params = ConsentRequestParameters();
    final completer = Completer<void>();

    ConsentInformation.instance.requestConsentInfoUpdate(
      params,
      () async {
        try {
          if (await ConsentInformation.instance.isConsentFormAvailable()) {
            await _loadAndShowConsentFormIfRequired();
          }
        } finally {
          if (!completer.isCompleted) completer.complete();
        }
      },
      (FormError error) {
        debugPrint('UMP consent info update failed: ${error.message}');
        if (!completer.isCompleted) completer.complete();
      },
    );

    await completer.future;
    await MobileAds.instance.initialize();
  }

  static Future<void> _loadAndShowConsentFormIfRequired() {
    final completer = Completer<void>();
    ConsentForm.loadConsentForm(
      (ConsentForm form) async {
        final status = await ConsentInformation.instance.getConsentStatus();
        if (status == ConsentStatus.required) {
          form.show((FormError? error) {
            if (error != null) {
              debugPrint('UMP consent form error: ${error.message}');
            }
            completer.complete();
          });
        } else {
          completer.complete();
        }
      },
      (FormError error) {
        debugPrint('UMP consent form failed to load: ${error.message}');
        completer.complete();
      },
    );
    return completer.future;
  }
}
