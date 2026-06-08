class UserProfile {
  final String id;
  final String coupleId;
  final String partner;       // 'Rodel' or 'Mary Mae'
  final String? displayName;
  final String? bio;
  final String? avatarUrl;    // Public Supabase Storage URL
  final DateTime updatedAt;

  const UserProfile({
    required this.id,
    required this.coupleId,
    required this.partner,
    this.displayName,
    this.bio,
    this.avatarUrl,
    required this.updatedAt,
  });

  factory UserProfile.fromMap(Map<String, dynamic> map) {
    return UserProfile(
      id: map['id']?.toString() ?? '',
      coupleId: map['couple_id']?.toString() ?? '',
      partner: map['partner']?.toString() ?? '',
      displayName: map['display_name']?.toString(),
      bio: map['bio']?.toString(),
      avatarUrl: map['avatar_url']?.toString(),
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
    'couple_id': coupleId,
    'partner': partner,
    if (displayName != null) 'display_name': displayName,
    if (bio != null) 'bio': bio,
    if (avatarUrl != null) 'avatar_url': avatarUrl,
    'updated_at': updatedAt.toIso8601String(),
  };

  UserProfile copyWith({
    String? displayName,
    String? bio,
    String? avatarUrl,
  }) {
    return UserProfile(
      id: id,
      coupleId: coupleId,
      partner: partner,
      displayName: displayName ?? this.displayName,
      bio: bio ?? this.bio,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      updatedAt: DateTime.now(),
    );
  }
}
