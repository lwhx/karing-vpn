import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart' as google;
import 'package:karing/app/modules/app_lifecycle_state_notify_manager.dart';
import 'package:karing/app/private/ads_private.dart';
import 'package:karing/app/utils/sentry_utils.dart';

class AdsBannerWidget extends StatefulWidget {
  static int adHeight = google.AdSize.banner.height;
  final bool fixedHeight;
  final double adWidth;
  final String bannerName;
  const AdsBannerWidget({
    super.key,
    required this.fixedHeight,
    required this.adWidth,
    this.bannerName = "",
  });
  static double getRealHeight(bool fixedHeight, bool showAd, int adHeight) {
    double height = 0;
    if (Platform.isAndroid || Platform.isIOS) {
      if (fixedHeight || showAd) {
        height = adHeight.toDouble() + 4.0;
      }
    } else {
      height = 20;
    }
    return height;
  }

  @override
  State<AdsBannerWidget> createState() => _AdsBannerWidgetState();
}

class _AdsBannerWidgetState extends State<AdsBannerWidget> {
  late google.AdSize adSize;

  bool _googleBannerAdIsLoading = false;
  bool _googleBannerAdIsLoaded = false;
  google.BannerAd? _googleBannerAd;

  @override
  void initState() {
    adSize = google.AdSize(
        height: AdsBannerWidget.adHeight, width: widget.adWidth.toInt());
    AppLifecycleStateNofityManager.onStateResumed(hashCode, () async {
      if (AdsPrivate.getEnable()) {
        _loadGoogleBannerAd(false);
      } else {
        _disposeGoogleBannerAd();
        setState(() {});
      }
    });
    super.initState();
  }

  @override
  void dispose() {
    AppLifecycleStateNofityManager.onStateResumed(hashCode, null);
    _disposeGoogleBannerAd();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    bool googleAd = isGoogleAdReady();

    double height = AdsBannerWidget.getRealHeight(
        widget.fixedHeight, googleAd, adSize.height);

    return Container(
        height: height,
        alignment: Alignment.center,
        child: AdsPrivate.getEnable()
            ? Stack(
                children: [
                  Visibility(
                      visible: googleAd,
                      child: Positioned(
                          child: googleAd
                              ? google.AdWidget(ad: _googleBannerAd!)
                              : const SizedBox.shrink())),
                ],
              )
            : null);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AdsPrivate.getEnable()) {
      _loadGoogleBannerAd(true);
    }
  }

  bool isGoogleAdReady() {
    return _googleBannerAdIsLoaded && _googleBannerAd != null;
  }

  void _disposeGoogleBannerAd() {
    _googleBannerAd?.dispose();
    _googleBannerAd = null;
    _googleBannerAdIsLoaded = false;
    _googleBannerAdIsLoading = false;
  }

  Future<void> _loadGoogleBannerAd(bool forceReload) async {
    if (!mounted) {
      return;
    }

    try {
      if (_googleBannerAdIsLoading) {
        return;
      }
      if (!forceReload) {
        if (_googleBannerAd != null) {
          return;
        }
      }
      _googleBannerAd?.dispose();
      _googleBannerAd = null;
      _googleBannerAdIsLoaded = false;
      _googleBannerAdIsLoading = true;

      setState(() {});
      var adUnitId =
          AdsPrivate.getAdID(AdType.googleBannerAd, name: widget.bannerName);
      var googleBannerAd = google.BannerAd(
        adUnitId: adUnitId,
        size: adSize,
        request: const google.AdRequest(),
        listener: google.BannerAdListener(
          onAdLoaded: (google.Ad ad) {
            if (!mounted) {
              ad.dispose();
              return;
            }

            _googleBannerAd = ad as google.BannerAd;
            _googleBannerAdIsLoaded = true;
            _googleBannerAdIsLoading = false;
            setState(() {});
          },
          onAdFailedToLoad: (google.Ad ad, google.LoadAdError error) {
            ad.dispose();
            if (!mounted) {
              return;
            }
            _googleBannerAdIsLoaded = false;
            _googleBannerAdIsLoading = false;
            setState(() {});
          },
          onAdClicked: (ad) {
            if (!mounted) {
              return;
            }

            _disposeGoogleBannerAd();
            setState(() {});
          },
        ),
      );
      await googleBannerAd.load();
    } catch (err, stacktrace) {
      SentryUtils.captureException(
          'AdsRewardWidget._loadGoogleBannerAd.exception', [], err, stacktrace);
    }
  }
}

class AdsRewardError {
  final int code;
  final String message;
  AdsRewardError(this.code, this.message);
  @override
  String toString() {
    return 'code: $code, message: $message';
  }
}

class AdsRewardWidget {
  static void loadGoogleRewardedAd(Function(AdsRewardError? err) callback) {
    try {
      var adUnitId = AdsPrivate.getAdID(AdType.googleRewardedAd);
      google.RewardedAd.load(
          adUnitId: adUnitId,
          request: const google.AdRequest(),
          rewardedAdLoadCallback: google.RewardedAdLoadCallback(
            onAdLoaded: (ad) {
              ad.fullScreenContentCallback = google.FullScreenContentCallback(
                onAdShowedFullScreenContent: (ad) {},
                onAdImpression: (ad) {},
                onAdFailedToShowFullScreenContent: (ad, err) {
                  ad.dispose();
                  callback(AdsRewardError(err.code, err.message));
                },
                onAdDismissedFullScreenContent: (ad) {
                  ad.dispose();
                },
                onAdClicked: (ad) {},
              );

              ad.show(onUserEarnedReward: (google.AdWithoutView ad,
                  google.RewardItem rewardItem) async {
                ad.dispose();
                callback(null);
              });
            },
            onAdFailedToLoad: (google.LoadAdError error) {
              callback(AdsRewardError(error.code, error.message));
            },
          ));
    } catch (err, stacktrace) {
      callback(AdsRewardError(-1, err.toString()));
      SentryUtils.captureException(
          'AdsRewardWidget.loadGoogleRewardedAd.exception',
          [],
          err,
          stacktrace);
    }
  }
}