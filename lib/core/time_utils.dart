import 'dart:async';
import 'package:ntp/ntp.dart';
import 'package:intl/intl.dart';

final class TimeUtils {
  TimeUtils._();

  /// Formats the chat time from a UTC ISO string, converting it to local time first.
  static String formatChatTime(String isoString) {
    try {
      final dt = DateTime.parse(isoString).toLocal();
      return DateFormat('h:mm a').format(dt);
    } catch (_) {
      return '';
    }
  }

  /// Formats the chat date separator from a UTC ISO string, converting it to local time first.
  static String formatDateSeparator(String isoString) {
    try {
      final dt = DateTime.parse(isoString).toLocal();
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final yesterday = today.subtract(const Duration(days: 1));
      final messageDate = DateTime(dt.year, dt.month, dt.day);

      final timeStr = DateFormat('h:mm a').format(dt);

      if (messageDate == today) {
        return 'Today • $timeStr';
      } else if (messageDate == yesterday) {
        return 'Yesterday • $timeStr';
      } else {
        final weekday = DateFormat('E').format(dt); // Mon, Tue, etc.
        final month = DateFormat('MMM').format(dt); // Jan, Feb, etc.
        if (dt.year == now.year) {
          return '$weekday, $month ${dt.day} • $timeStr';
        } else {
          return '$weekday, $month ${dt.day}, ${dt.year} • $timeStr';
        }
      }
    } catch (_) {
      return '';
    }
  }

  /// Formats a full date-time string (e.g. Jun 9 • 4:23 PM) from a UTC ISO string.
  static String formatDateTime(String isoString) {
    try {
      final dt = DateTime.parse(isoString).toLocal();
      final month = DateFormat('MMM').format(dt);
      final timeStr = DateFormat('h:mm a').format(dt);
      return '$month ${dt.day} • $timeStr';
    } catch (_) {
      return '';
    }
  }

  /// Exposes formatting directly from a DateTime object for convenience.
  static String formatChatTimeFromDateTime(DateTime dt) {
    return DateFormat('h:mm a').format(dt.toLocal());
  }

  static String formatDateSeparatorFromDateTime(DateTime dt) {
    final localDt = dt.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final messageDate = DateTime(localDt.year, localDt.month, localDt.day);
    final timeStr = DateFormat('h:mm a').format(localDt);

    if (messageDate == today) {
      return 'Today • $timeStr';
    } else if (messageDate == yesterday) {
      return 'Yesterday • $timeStr';
    } else {
      final weekday = DateFormat('E').format(localDt);
      final month = DateFormat('MMM').format(localDt);
      if (localDt.year == now.year) {
        return '$weekday, $month ${localDt.day} • $timeStr';
      } else {
        return '$weekday, $month ${localDt.day}, ${localDt.year} • $timeStr';
      }
    }
  }

  static String formatDateTimeFromDateTime(DateTime dt) {
    final localDt = dt.toLocal();
    final month = DateFormat('MMM').format(localDt);
    final timeStr = DateFormat('h:mm a').format(localDt);
    return '$month ${localDt.day} • $timeStr';
  }

  /// Fetches true network time using NTP with a fallback to local system time.
  static Future<DateTime> getTrueTime() async {
    try {
      return await NTP.now(timeout: const Duration(seconds: 3));
    } catch (_) {
      return DateTime.now();
    }
  }

  /// Calculates a tamper-proof relationship duration using network time.
  static Future<Duration> getRelationshipDuration(DateTime anniversaryDate) async {
    final trueTime = await getTrueTime();
    return trueTime.difference(anniversaryDate);
  }
}
