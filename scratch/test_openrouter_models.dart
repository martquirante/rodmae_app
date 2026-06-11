import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

void main() async {
  print('=== Testing OpenRouter with openrouter/free ===\n');

  final envFile = File('.env');
  if (!await envFile.exists()) return;

  final lines = await envFile.readAsLines();
  String? apiKey;
  for (var line in lines) {
    line = line.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final parts = line.split('=');
    if (parts.length >= 2 && parts[0].trim() == 'OPENROUTER_API_KEY') {
      apiKey = parts.sublist(1).join('=').trim();
      if ((apiKey.startsWith("'") && apiKey.endsWith("'")) ||
          (apiKey.startsWith('"') && apiKey.endsWith('"'))) {
        apiKey = apiKey.substring(1, apiKey.length - 1);
      }
      break;
    }
  }

  if (apiKey == null || apiKey.isEmpty) return;

  final model = 'openrouter/free';
  print('Testing $model...');
  try {
    final response = await http.post(
      Uri.parse('https://openrouter.ai/api/v1/chat/completions'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
        'HTTP-Referer': 'https://github.com/martquirante/rodmae_app',
        'X-Title': 'RodMae App',
      },
      body: jsonEncode({
        'model': model,
        'max_tokens': 500,
        'messages': [
          {'role': 'user', 'content': 'Hello, this is a test.'}
        ],
      }),
    ).timeout(const Duration(seconds: 10));

    print('HTTP Status: ${response.statusCode}');
    final decoded = jsonDecode(response.body);
    if (response.statusCode == 200) {
      final text = decoded['choices']?[0]?['message']?['content'];
      print('SUCCESS! Response: $text');
    } else {
      print('FAILED: ${decoded['error']?['message']}');
    }
  } catch (e) {
    print('ERROR: $e');
  }
}
