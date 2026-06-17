import 'package:flutter/material.dart';
import '../core/utils.dart';


enum WalletType {
  personal,
  shared;

  String get dbValue => name;

  static WalletType from(dynamic value) {
    final val = '$value'.toLowerCase();
    if (val.contains('shared')) return WalletType.shared;
    return WalletType.personal;
  }
}

final class Wallet {
  final String id;
  final String householdId;
  final String? ownerUserId; // NULL = Shared Wallet, NOT NULL = Personal Pocket
  final WalletType type;
  final double monthlyLimit;
  final double balance;       // Manually entered balance stored in DB
  final String? brandKey;     // e.g. 'gcash', 'bpi', 'cash'
  final String? colorHex;     // Brand primary color
  final String? walletName;   // User-defined name override

  // Backward compat
  String get coupleId => householdId;
  String? get ownerUid => ownerUserId;
  WalletType get walletType => type;

  String get name {
    if (walletName != null && walletName!.isNotEmpty) return walletName!;
    if (brandKey != null && brandKey!.isNotEmpty) {
      return WalletBrand.forKey(brandKey!).displayName;
    }
    if (isShared) return 'Shared Vault';
    if (ownerUserId?.toLowerCase().contains('rodel') == true) return "Rodel's Pocket";
    if (ownerUserId?.toLowerCase().contains('eurine') == true ||
        ownerUserId?.toLowerCase().contains('marymae') == true) return "Mae's Pocket";
    return 'Personal Pocket';
  }

  const Wallet({
    required this.id,
    required this.householdId,
    this.ownerUserId,
    required this.type,
    required this.monthlyLimit,
    this.balance = 0.0,
    this.brandKey,
    this.colorHex,
    this.walletName,
  });

  bool get isShared => ownerUserId == null || type == WalletType.shared;
  bool get isPersonal => ownerUserId != null && type == WalletType.personal;

  factory Wallet.fromJson(Map<String, dynamic> json) {
    return Wallet(
      id: json['id']?.toString() ?? '',
      householdId: json['household_id']?.toString() ?? json['couple_id']?.toString() ?? '',
      ownerUserId: json['owner_user_id']?.toString() ?? json['owner_uid']?.toString(),
      type: WalletType.from(json['type'] ?? json['wallet_type'] ?? 'personal'),
      monthlyLimit: Formatters.asDouble(json['monthly_limit'] ?? 0.0),
      balance: Formatters.asDouble(json['balance'] ?? 0.0),
      brandKey: json['brand_key']?.toString(),
      colorHex: json['color_hex']?.toString(),
      walletName: json['name']?.toString(),
    );
  }

  factory Wallet.fromMap(Map<String, dynamic> map) => Wallet.fromJson(map);

  Map<String, dynamic> toJson() => {
        'id': id,
        'household_id': householdId,
        'owner_user_id': ownerUserId,
        'type': type.dbValue,
        'monthly_limit': monthlyLimit,
        'balance': balance,
        'brand_key': brandKey,
        'color_hex': colorHex,
        'name': walletName,
      };

  Map<String, dynamic> toInsertMap() => {
        'household_id': householdId,
        'owner_user_id': ownerUserId,
        'type': type.dbValue,
        'monthly_limit': monthlyLimit,
        'balance': balance,
        'brand_key': brandKey,
        'color_hex': colorHex,
        'name': walletName,
      };

  Map<String, dynamic> toMap() => toJson();

  Wallet copyWith({
    String? id,
    String? householdId,
    String? ownerUserId,
    WalletType? type,
    double? monthlyLimit,
    double? balance,
    String? brandKey,
    String? colorHex,
    String? walletName,
  }) =>
      Wallet(
        id: id ?? this.id,
        householdId: householdId ?? this.householdId,
        ownerUserId: ownerUserId ?? this.ownerUserId,
        type: type ?? this.type,
        monthlyLimit: monthlyLimit ?? this.monthlyLimit,
        balance: balance ?? this.balance,
        brandKey: brandKey ?? this.brandKey,
        colorHex: colorHex ?? this.colorHex,
        walletName: walletName ?? this.walletName,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Brand definitions for all Philippine E-Money, Banks, and Cash
// ─────────────────────────────────────────────────────────────────────────────
class WalletBrand {
  final String key;
  final String displayName;
  final Color primaryColor;
  final Color secondaryColor;
  final String emoji;
  final String category; // 'emoney' | 'bank' | 'cash'

  const WalletBrand({
    required this.key,
    required this.displayName,
    required this.primaryColor,
    required this.secondaryColor,
    required this.emoji,
    required this.category,
  });

  String get name => displayName;
  String get logoText => emoji;

  static const List<WalletBrand> all = [
    // ── E-Money ──────────────────────────────────────────────────────────
    WalletBrand(key: 'gcash',     displayName: 'GCash',        primaryColor: Color(0xFF007DFE), secondaryColor: Color(0xFF005BC4), emoji: 'G',  category: 'emoney'),
    WalletBrand(key: 'maya',      displayName: 'Maya',         primaryColor: Color(0xFF00D47D), secondaryColor: Color(0xFF009955), emoji: 'M',  category: 'emoney'),
    WalletBrand(key: 'grabpay',   displayName: 'GrabPay',      primaryColor: Color(0xFF00B159), secondaryColor: Color(0xFF008A44), emoji: 'GP', category: 'emoney'),
    WalletBrand(key: 'shopeepay', displayName: 'ShopeePay',    primaryColor: Color(0xFFEE4D2D), secondaryColor: Color(0xFFCC2200), emoji: 'SP', category: 'emoney'),
    WalletBrand(key: 'coinsph',   displayName: 'Coins.ph',     primaryColor: Color(0xFF6C3FC5), secondaryColor: Color(0xFF4A1E9E), emoji: 'C',  category: 'emoney'),
    WalletBrand(key: 'seapay',    displayName: 'SeaMoney',     primaryColor: Color(0xFF2196F3), secondaryColor: Color(0xFF1565C0), emoji: 'SM', category: 'emoney'),
    WalletBrand(key: 'lazpay',    displayName: 'LazPay',       primaryColor: Color(0xFFF57C00), secondaryColor: Color(0xFFE65100), emoji: 'LP', category: 'emoney'),
    WalletBrand(key: 'payconneqt',displayName: 'PayConnEQt',   primaryColor: Color(0xFF0097A7), secondaryColor: Color(0xFF006064), emoji: 'PC', category: 'emoney'),
    // ── Banks ─────────────────────────────────────────────────────────────
    WalletBrand(key: 'bdo',       displayName: 'BDO',          primaryColor: Color(0xFF0038A8), secondaryColor: Color(0xFF002070), emoji: 'BDO',category: 'bank'),
    WalletBrand(key: 'bpi',       displayName: 'BPI',          primaryColor: Color(0xFFB91C1C), secondaryColor: Color(0xFF7F1D1D), emoji: 'BPI',category: 'bank'),
    WalletBrand(key: 'metrobank', displayName: 'Metrobank',    primaryColor: Color(0xFF1D4ED8), secondaryColor: Color(0xFF1E3A8A), emoji: 'MB', category: 'bank'),
    WalletBrand(key: 'landbank',  displayName: 'Landbank',     primaryColor: Color(0xFF15803D), secondaryColor: Color(0xFF14532D), emoji: 'LB', category: 'bank'),
    WalletBrand(key: 'rcbc',      displayName: 'RCBC',         primaryColor: Color(0xFF0891B2), secondaryColor: Color(0xFF0E7490), emoji: 'RCBC',category:'bank'),
    WalletBrand(key: 'secbank',   displayName: 'Security Bank',primaryColor: Color(0xFF2563EB), secondaryColor: Color(0xFF1D4ED8), emoji: 'SB', category: 'bank'),
    WalletBrand(key: 'unionbank', displayName: 'UnionBank',    primaryColor: Color(0xFFEA580C), secondaryColor: Color(0xFFC2410C), emoji: 'UB', category: 'bank'),
    WalletBrand(key: 'eastwest',  displayName: 'EastWest',     primaryColor: Color(0xFF0F766E), secondaryColor: Color(0xFF115E59), emoji: 'EW', category: 'bank'),
    WalletBrand(key: 'pnb',       displayName: 'PNB',          primaryColor: Color(0xFF7C3AED), secondaryColor: Color(0xFF6D28D9), emoji: 'PNB',category: 'bank'),
    WalletBrand(key: 'chinabank', displayName: 'China Bank',   primaryColor: Color(0xFF991B1B), secondaryColor: Color(0xFF7F1D1D), emoji: 'CB', category: 'bank'),
    WalletBrand(key: 'psbank',    displayName: 'PS Bank',      primaryColor: Color(0xFF1E40AF), secondaryColor: Color(0xFF1E3A8A), emoji: 'PSB',category: 'bank'),
    WalletBrand(key: 'dbp',       displayName: 'DBP',          primaryColor: Color(0xFF065F46), secondaryColor: Color(0xFF064E3B), emoji: 'DBP',category: 'bank'),
    // ── Cash ──────────────────────────────────────────────────────────────
    WalletBrand(key: 'cash',      displayName: 'Physical Cash',primaryColor: Color(0xFFCA8A04), secondaryColor: Color(0xFF92400E), emoji: '₱',  category: 'cash'),
  ];

  static WalletBrand forKey(String key) =>
      all.firstWhere((b) => b.key == key,
          orElse: () => const WalletBrand(
                key: 'other',
                displayName: 'Other',
                primaryColor: Color(0xFF475569),
                secondaryColor: Color(0xFF334155),
                emoji: '💳',
                category: 'other',
              ));

  static List<WalletBrand> get eMoney => all.where((b) => b.category == 'emoney').toList();
  static List<WalletBrand> get banks  => all.where((b) => b.category == 'bank').toList();
  static List<WalletBrand> get cash   => all.where((b) => b.category == 'cash').toList();
}
