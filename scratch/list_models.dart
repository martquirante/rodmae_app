import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

void main() async {
  print('--- Listing available models for this API key ---');
  try {
    final envFile = File('.env');
    if (!await envFile.exists()) {
      print('Error: .env file does not exist.');
      return;
    }

    final lines = await envFile.readAsLines();
    String? apiKey;
    for (var line in lines) {
      line = line.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final parts = line.split('=');
      if (parts.length >= 2 && parts[0].trim() == 'GEMINI_API_KEY') {
        apiKey = parts.sublist(1).join('=').trim();
        if ((apiKey.startsWith("'") && apiKey.endsWith("'")) ||
            (apiKey.startsWith('"') && apiKey.endsWith('"'))) {
          apiKey = apiKey.substring(1, apiKey.length - 1);
        }
        break;
      }
    }

    if (apiKey == null || apiKey.isEmpty) {
      print('Error: GEMINI_API_KEY not found.');
      return;
    }

    // Call Google's model list API
    final url = 'https://generativelanguage.googleapis.com/v1beta/models?key=$apiKey';
    print('Sending request to: https://generativelanguage.googleapis.com/v1beta/models?key=...');
    
    final response = await http.get(Uri.parse(url));
    print('Response status: ${response.statusCode}');
    
    final body = jsonDecode(response.body);
    if (response.statusCode == 200) {
      final models = body['models'] as List?;
      if (models == null || models.isEmpty) {
        print('No models found.');
      } else {
        print('Available models for this key:');
        for (var m in models) {
          print('  - ${m['name']} (supportedMethods: ${m['supportedMethods']})');
        }
      }
    } else {
      print('Failed to list models:');
      print(JsonEncoder.withIndent('  ').convert(body));
    }
  } catch (e, s) {
    print('Error listing models: $e');
    print(s);
  }
}
