import 'dart:convert';
import 'package:http/http.dart' as http;

Future<void> main() async {
  final url = Uri.parse('https://axqbpjafmlwvqnhodtph.supabase.co/functions/v1/send_fcm_notification');
  final anonKey = 'sb_publishable_gxjk9pVdgbZdDv-aeMJMbQ__N4BGZj6';
  
  final body = {
    'type': 'INSERT',
    'table': 'chat_history',
    'record': {
      'id': 1,
      'couple_id': 'couple-rodel-marymae-2026',
      'sender': 'Rodel',
      'message': 'Test Message from Antigravity CLI',
      'topic': 'couple-rodel-marymae-2026-Eurine'
    },
    'client_fallback': true,
    'notification': {
      'title': 'Rodel 💬',
      'body': 'Test Message from Antigravity CLI'
    }
  };

  print('Calling Edge Function...');
  try {
    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $anonKey',
      },
      body: jsonEncode(body),
    );

    print('Status Code: ${response.statusCode}');
    print('Response Body: ${response.body}');
  } catch (e) {
    print('Error: $e');
  }
}
