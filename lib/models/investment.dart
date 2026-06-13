import '../core/utils.dart';

enum AssetType {
  crypto,
  stock;

  String get dbValue => name;

  static AssetType from(dynamic value) {
    final val = '$value'.toLowerCase();
    if (val.contains('crypto')) {
      return AssetType.crypto;
    }
    return AssetType.stock;
  }
}

final class Investment {
  final String id;
  final String coupleId;
  final String? ownerUid;
  final AssetType assetType;
  final String symbol;
  final double holdings;
  final double averageBuyPrice;
  final DateTime createdAt;

  // Derived convenience getter for total market value evaluation helper
  double get totalCostBasis => holdings * averageBuyPrice;

  const Investment({
    required this.id,
    required this.coupleId,
    this.ownerUid,
    required this.assetType,
    required this.symbol,
    required this.holdings,
    required this.averageBuyPrice,
    required this.createdAt,
  });

  factory Investment.fromMap(Map<String, dynamic> row) {
    return Investment(
      id: row['id']?.toString() ?? '',
      coupleId: row['couple_id']?.toString() ?? '',
      ownerUid: row['owner_uid']?.toString(),
      assetType: AssetType.from(row['asset_type'] ?? 'stock'),
      symbol: row['symbol']?.toString() ?? '',
      holdings: Formatters.asDouble(row['holdings'] ?? 0.0),
      averageBuyPrice: Formatters.asDouble(row['average_buy_price'] ?? 0.0),
      createdAt: Formatters.asDate(row['created_at']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'couple_id': coupleId,
      if (ownerUid != null) 'owner_uid': ownerUid,
      'asset_type': assetType.dbValue,
      'symbol': symbol,
      'holdings': holdings,
      'average_buy_price': averageBuyPrice,
      'created_at': createdAt.toIso8601String(),
    };
  }

  Investment copyWith({
    String? id,
    String? coupleId,
    String? ownerUid,
    AssetType? assetType,
    String? symbol,
    double? holdings,
    double? averageBuyPrice,
    DateTime? createdAt,
  }) {
    return Investment(
      id: id ?? this.id,
      coupleId: coupleId ?? this.coupleId,
      ownerUid: ownerUid ?? this.ownerUid,
      assetType: assetType ?? this.assetType,
      symbol: symbol ?? this.symbol,
      holdings: holdings ?? this.holdings,
      averageBuyPrice: averageBuyPrice ?? this.averageBuyPrice,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
