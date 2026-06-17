// wallet_constants.dart
// Re-exports WalletBrand from wallet.dart and provides
// the PhilippineWalletConstants helper for backward compatibility.
export 'wallet.dart' show WalletBrand;

import 'wallet.dart';

class PhilippineWalletConstants {
  /// Returns the WalletBrand matching the wallet name or brand key.
  /// Falls back gracefully if no match is found.
  static WalletBrand getBrand(String nameOrKey) {
    final key = nameOrKey.toLowerCase().replaceAll(' ', '');
    return WalletBrand.forKey(key);
  }
}
