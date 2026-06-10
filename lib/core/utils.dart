import 'dart:convert';

final class Formatters {
  Formatters._();

  static String money(num value) {
    final fixed = value.toStringAsFixed(2);
    final parts = fixed.split('.');
    final reversed = parts.first.split('').reversed.toList();
    final grouped = <String>[];
    for (var i = 0; i < reversed.length; i++) {
      if (i != 0 && i % 3 == 0) {
        grouped.add(',');
      }
      grouped.add(reversed[i]);
    }
    return 'PHP ${grouped.reversed.join()}.${parts.last}';
  }

  static String compactMoney(num value) {
    return money(value).replaceAll('.00', '');
  }

  static String date(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static String time(DateTime date) {
    final hour = date.hour == 0
        ? 12
        : date.hour > 12
            ? date.hour - 12
            : date.hour;
    final minute = date.minute.toString().padLeft(2, '0');
    final suffix = date.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $suffix';
  }

  /// Returns a human-readable "Jun 9 • 4:23 PM" style stamp.
  static String dateTime(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final month = months[dt.month - 1];
    final day = dt.day;
    return '$month $day • ${time(dt)}';
  }

  static double asDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    final text = '$value'.replaceAll(RegExp(r'[^0-9.\-]'), '');
    return double.tryParse(text) ?? 0;
  }

  static DateTime asDate(dynamic value) {
    if (value is DateTime) {
      return value;
    }
    return DateTime.tryParse('$value') ?? DateTime.now();
  }
}

final class JsonResponseParser {
  JsonResponseParser._();

  static Map<String, dynamic> objectFromText(String text) {
    final cleaned = _stripMarkdown(text);
    final direct = jsonDecode(cleaned);
    if (direct is Map<String, dynamic>) {
      return direct;
    }
    throw const FormatException('Gemini response was not a JSON object.');
  }

  static List<Map<String, dynamic>> arrayFromText(String text) {
    final cleaned = _stripMarkdown(text);
    final decoded = jsonDecode(cleaned);
    if (decoded is List) {
      return decoded
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }
    throw const FormatException('Gemini response was not a JSON array.');
  }

  static String _stripMarkdown(String text) {
    var cleaned = text.trim();
    cleaned = cleaned.replaceAll(RegExp(r'^```(?:json)?', multiLine: true), '');
    cleaned = cleaned.replaceAll(RegExp(r'```$', multiLine: true), '');
    cleaned = cleaned.trim();
    final objectStart = cleaned.indexOf('{');
    final objectEnd = cleaned.lastIndexOf('}');
    final arrayStart = cleaned.indexOf('[');
    final arrayEnd = cleaned.lastIndexOf(']');

    if (arrayStart >= 0 &&
        arrayEnd > arrayStart &&
        (objectStart == -1 || arrayStart < objectStart)) {
      return cleaned.substring(arrayStart, arrayEnd + 1);
    }
    if (objectStart >= 0 && objectEnd > objectStart) {
      return cleaned.substring(objectStart, objectEnd + 1);
    }
    return cleaned;
  }
}
