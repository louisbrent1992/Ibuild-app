import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

/// iBuild Pro: a one-time unlock ($4.99), entitlement `pro` in the RevenueCat
/// project "iBuild". Free covers demo mode and one real project; Pro adds
/// unlimited projects, committing codemagic.yaml and TestFlight tester tools.
const freeProjectLimit = 1;

/// Whether one more real project fits. Demo projects never count.
bool fitsFreeTier({required bool isPro, required bool demoMode, required int projects}) =>
    isPro || demoMode || projects < freeProjectLimit;

/// What Pro unlocks, used for the paywall copy and the gates.
enum ProFeature {
  projects('Unlimited projects'),
  commitConfig('Commit codemagic.yaml to your repository'),
  testers('TestFlight tester groups and public links');

  const ProFeature(this.label);
  final String label;
}

class PurchaseCancelled implements Exception {
  const PurchaseCancelled();
}

class ProException implements Exception {
  const ProException(this.message);
  final String message;
  @override
  String toString() => message;
}

abstract class ProService {
  bool get isPro;
  Stream<bool> changes();

  /// Localised price of the unlock, e.g. "$4.99", or null if the store has
  /// not returned it (offline, or the product is not live yet).
  Future<String?> price();
  Future<void> purchase();
  Future<void> restore();

  /// Ties purchases to the signed-in account so Pro follows the user to any
  /// device, or back to an anonymous ID when they sign out.
  Future<void> identify(String? uid);
}

class RevenueCatPro implements ProService {
  // Public SDK keys: safe in the binary.
  static const _appleKey = 'appl_ekdXTbrVUDVrqeBeOoHWcAaHBbd';
  static const _googleKey = 'goog_nKIxskAGMSedeJcDEsmprWhOKWH';
  static const _entitlement = 'pro';

  final _changes = StreamController<bool>.broadcast();
  bool _isPro = false;

  /// Returns null when RevenueCat cannot start, so the app runs without Pro.
  static Future<RevenueCatPro?> start() async {
    try {
      final key = defaultTargetPlatform == TargetPlatform.iOS ? _appleKey : _googleKey;
      await Purchases.configure(PurchasesConfiguration(key));
      final pro = RevenueCatPro();
      Purchases.addCustomerInfoUpdateListener(pro._apply);
      pro._apply(await Purchases.getCustomerInfo());
      return pro;
    } catch (e) {
      debugPrint('Purchases unavailable: $e');
      return null;
    }
  }

  void _apply(CustomerInfo info) {
    final next = info.entitlements.active.containsKey(_entitlement);
    if (next == _isPro) return;
    _isPro = next;
    _changes.add(next);
  }

  @override
  bool get isPro => _isPro;
  @override
  Stream<bool> changes() => _changes.stream;

  Future<Package?> _package() async =>
      (await Purchases.getOfferings()).current?.lifetime;

  @override
  Future<String?> price() async {
    try {
      return (await _package())?.storeProduct.priceString;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> purchase() async {
    final package = await _package();
    if (package == null) {
      throw const ProException('iBuild Pro is not available in the store yet. Try again later.');
    }
    try {
      _apply((await Purchases.purchase(PurchaseParams.package(package))).customerInfo);
    } on PlatformException catch (e) {
      final code = PurchasesErrorHelper.getErrorCode(e);
      if (code == PurchasesErrorCode.purchaseCancelledError) throw const PurchaseCancelled();
      throw ProException(e.message ?? 'The purchase did not go through.');
    }
  }

  @override
  Future<void> restore() async {
    try {
      _apply(await Purchases.restorePurchases());
    } on PlatformException catch (e) {
      throw ProException(e.message ?? 'Could not restore purchases.');
    }
    if (!_isPro) throw const ProException('No iBuild Pro purchase was found for this account.');
  }

  @override
  Future<void> identify(String? uid) async {
    try {
      final info = uid == null
          ? (await Purchases.isAnonymous ? null : await Purchases.logOut())
          : (await Purchases.logIn(uid)).customerInfo;
      if (info != null) _apply(info);
    } catch (e) {
      debugPrint('Could not link purchases to the account: $e');
    }
  }
}

/// Where the stores are unavailable (tests, Linux): no Pro, no purchases.
class NoPro implements ProService {
  const NoPro();
  @override
  bool get isPro => false;
  @override
  Stream<bool> changes() => const Stream.empty();
  @override
  Future<String?> price() async => null;
  @override
  Future<void> purchase() async =>
      throw const ProException('Purchases are not available on this device.');
  @override
  Future<void> restore() async =>
      throw const ProException('Purchases are not available on this device.');
  @override
  Future<void> identify(String? uid) async {}
}
