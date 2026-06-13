import 'package:flutter/material.dart';

class WalletBrand {
  final String name;
  final Color primaryColor;
  final Color secondaryColor;
  final IconData icon;
  final String logoText;

  const WalletBrand({
    required this.name,
    required this.primaryColor,
    required this.secondaryColor,
    required this.icon,
    required this.logoText,
  });
}

class PhilippineWalletConstants {
  static const Map<String, WalletBrand> brands = {
    'gcash': WalletBrand(
      name: 'GCash',
      primaryColor: Color(0xFF007DFE), // Sky Blue
      secondaryColor: Color(0xFFE0F2FE),
      icon: Icons.account_balance_wallet_rounded,
      logoText: 'G',
    ),
    'maya': WalletBrand(
      name: 'Maya',
      primaryColor: Color(0xFF00FF88), // Green
      secondaryColor: Color(0xFF1E293B), // Black
      icon: Icons.wallet_rounded,
      logoText: 'M',
    ),
    'grabpay': WalletBrand(
      name: 'GrabPay',
      primaryColor: Color(0xFF00B159), // Light Green
      secondaryColor: Color(0xFFDCFCE7),
      icon: Icons.directions_car_rounded,
      logoText: 'GP',
    ),
    'bdo': WalletBrand(
      name: 'BDO',
      primaryColor: Color(0xFF0038A8), // Blue
      secondaryColor: Color(0xFFFEF08A), // Yellow
      icon: Icons.account_balance_rounded,
      logoText: 'BDO',
    ),
    'bpi': WalletBrand(
      name: 'BPI',
      primaryColor: Color(0xFFB91C1C), // Red
      secondaryColor: Color(0xFFFEF08A), // Gold
      icon: Icons.account_balance_rounded,
      logoText: 'BPI',
    ),
    'metrobank': WalletBrand(
      name: 'Metrobank',
      primaryColor: Color(0xFF1D4ED8), // Deep Blue
      secondaryColor: Color(0xFFDBEAFE),
      icon: Icons.account_balance_rounded,
      logoText: 'MB',
    ),
    'landbank': WalletBrand(
      name: 'Landbank',
      primaryColor: Color(0xFF15803D), // Dark Green
      secondaryColor: Color(0xFFDCFCE7),
      icon: Icons.account_balance_rounded,
      logoText: 'LB',
    ),
    'rcbc': WalletBrand(
      name: 'RCBC',
      primaryColor: Color(0xFF0891B2), // Blue/Cyan
      secondaryColor: Color(0xFFECFDF5),
      icon: Icons.account_balance_rounded,
      logoText: 'RCBC',
    ),
    'security bank': WalletBrand(
      name: 'Security Bank',
      primaryColor: Color(0xFF2563EB), // Bright Blue
      secondaryColor: Color(0xFFEFF6FF),
      icon: Icons.account_balance_rounded,
      logoText: 'SB',
    ),
    'unionbank': WalletBrand(
      name: 'UnionBank',
      primaryColor: Color(0xFFEA580C), // Orange
      secondaryColor: Color(0xFFFFEDD5),
      icon: Icons.account_balance_rounded,
      logoText: 'UB',
    ),
    'cash': WalletBrand(
      name: 'Physical Cash',
      primaryColor: Color(0xFFCA8A04), // Gold
      secondaryColor: Color(0xFF0F172A), // Navy
      icon: Icons.money_rounded,
      logoText: '₱',
    ),
  };

  static WalletBrand getBrand(String walletName) {
    final name = walletName.toLowerCase();
    for (final entry in brands.entries) {
      if (name.contains(entry.key)) {
        return entry.value;
      }
    }
    // Specific defaults for standard personal/shared wallets
    if (name.contains('rodel')) {
      return const WalletBrand(
        name: "Rodel's Account",
        primaryColor: Color(0xFF2563EB),
        secondaryColor: Color(0xFF1D4ED8),
        icon: Icons.account_balance_rounded,
        logoText: 'R',
      );
    }
    if (name.contains('eurine') || name.contains('marymae')) {
      return const WalletBrand(
        name: "Eurine's Account",
        primaryColor: Color(0xFF059669),
        secondaryColor: Color(0xFF047857),
        icon: Icons.wallet_giftcard_rounded,
        logoText: 'E',
      );
    }
    if (name.contains('shared') || name.contains('vault')) {
      return const WalletBrand(
        name: "Shared Vault",
        primaryColor: Color(0xFF1E293B),
        secondaryColor: Color(0xFF0F172A),
        icon: Icons.vpn_key_rounded,
        logoText: 'SV',
      );
    }
    return brands['cash']!;
  }
}
