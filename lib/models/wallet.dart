import '../core/utils.dart';

enum WalletType {
  personal,
  shared;

  String get dbValue => name;

  static WalletType from(dynamic value) {
    final val = '$value'.toLowerCase();
    if (val.contains('shared')) {
      return WalletType.shared;
    }
    return WalletType.personal;
  }
}

final class Wallet {
  final String id;
  final String householdId;
  final String? ownerUserId; // NULL means it is the Shared Wallet, NOT NULL means it is a Personal Pocket
  final WalletType type;
  final double monthlyLimit;

  // Backward compatibility properties for UI/Reposity matching
  String get coupleId => householdId;
  String? get ownerUid => ownerUserId;
  WalletType get walletType => type;
  
  String get name {
    if (isShared) return "Shared Wallet";
    if (ownerUserId?.toLowerCase().contains('rodel') == true) return "Rodel's Pocket";
    if (ownerUserId?.toLowerCase().contains('eurine') == true || ownerUserId?.toLowerCase().contains('marymae') == true) return "Eurine's Pocket";
    return "Personal Pocket";
  }
  
  double get balance => 0.0; // Dynamic balance calculated from transactions

  const Wallet({
    required this.id,
    required this.householdId,
    this.ownerUserId,
    required this.type,
    required this.monthlyLimit,
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
    );
  }

  factory Wallet.fromMap(Map<String, dynamic> map) => Wallet.fromJson(map);

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'household_id': householdId,
      'owner_user_id': ownerUserId,
      'type': type.dbValue,
      'monthly_limit': monthlyLimit,
    };
  }

  Map<String, dynamic> toMap() => toJson();

  Wallet copyWith({
    String? id,
    String? householdId,
    String? ownerUserId,
    WalletType? type,
    double? monthlyLimit,
  }) {
    return Wallet(
      id: id ?? this.id,
      householdId: householdId ?? this.householdId,
      ownerUserId: ownerUserId ?? this.ownerUserId,
      type: type ?? this.type,
      monthlyLimit: monthlyLimit ?? this.monthlyLimit,
    );
  }
}
