class CoupleSettings {
  final String id;
  final String coupleId;
  final String? coupleNickname;
  final bool notifLoveSignals;
  final bool notifSweetNotes;
  final bool notifChatMessages;
  final bool notifMilestones;
  final bool showOnlineStatus;
  final bool showLastSeen;
  final String? chatBubbleColor;  // hex string e.g. '#3B82F6'
  final DateTime updatedAt;

  const CoupleSettings({
    required this.id,
    required this.coupleId,
    this.coupleNickname,
    this.notifLoveSignals = true,
    this.notifSweetNotes = true,
    this.notifChatMessages = true,
    this.notifMilestones = true,
    this.showOnlineStatus = true,
    this.showLastSeen = true,
    this.chatBubbleColor,
    required this.updatedAt,
  });

  factory CoupleSettings.defaults() => CoupleSettings(
    id: '',
    coupleId: 'couple-rodel-marymae-2026',
    updatedAt: DateTime.now(),
  );

  factory CoupleSettings.fromMap(Map<String, dynamic> map) {
    return CoupleSettings(
      id: map['id']?.toString() ?? '',
      coupleId: map['couple_id']?.toString() ?? 'couple-rodel-marymae-2026',
      coupleNickname: map['couple_nickname']?.toString(),
      notifLoveSignals: map['notif_love_signals'] as bool? ?? true,
      notifSweetNotes: map['notif_sweet_notes'] as bool? ?? true,
      notifChatMessages: map['notif_chat_messages'] as bool? ?? true,
      notifMilestones: map['notif_milestones'] as bool? ?? true,
      showOnlineStatus: map['show_online_status'] as bool? ?? true,
      showLastSeen: map['show_last_seen'] as bool? ?? true,
      chatBubbleColor: map['chat_bubble_color']?.toString(),
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
    'couple_id': coupleId,
    if (coupleNickname != null) 'couple_nickname': coupleNickname,
    'notif_love_signals': notifLoveSignals,
    'notif_sweet_notes': notifSweetNotes,
    'notif_chat_messages': notifChatMessages,
    'notif_milestones': notifMilestones,
    'show_online_status': showOnlineStatus,
    'show_last_seen': showLastSeen,
    if (chatBubbleColor != null) 'chat_bubble_color': chatBubbleColor,
  };

  CoupleSettings copyWith({
    String? coupleNickname,
    bool? notifLoveSignals,
    bool? notifSweetNotes,
    bool? notifChatMessages,
    bool? notifMilestones,
    bool? showOnlineStatus,
    bool? showLastSeen,
    String? chatBubbleColor,
  }) {
    return CoupleSettings(
      id: id,
      coupleId: coupleId,
      coupleNickname: coupleNickname ?? this.coupleNickname,
      notifLoveSignals: notifLoveSignals ?? this.notifLoveSignals,
      notifSweetNotes: notifSweetNotes ?? this.notifSweetNotes,
      notifChatMessages: notifChatMessages ?? this.notifChatMessages,
      notifMilestones: notifMilestones ?? this.notifMilestones,
      showOnlineStatus: showOnlineStatus ?? this.showOnlineStatus,
      showLastSeen: showLastSeen ?? this.showLastSeen,
      chatBubbleColor: chatBubbleColor ?? this.chatBubbleColor,
      updatedAt: DateTime.now(),
    );
  }
}
