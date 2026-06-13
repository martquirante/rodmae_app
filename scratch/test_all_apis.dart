import 'dart:convert';
import 'dart:io';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:http/http.dart' as http;

void main() async {
  print('=== Diagnostic API Test (Updated Config) ===\n');

  final envFile = File('.env');
  if (!await envFile.exists()) {
    print('Error: .env file does not exist.');
    return;
  }

  final lines = await envFile.readAsLines();
  final Map<String, String> env = {};
  for (var line in lines) {
    line = line.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final parts = line.split('=');
    if (parts.length >= 2) {
      var key = parts[0].trim();
      var val = parts.sublist(1).join('=').trim();
      if ((val.startsWith("'") && val.endsWith("'")) ||
          (val.startsWith('"') && val.endsWith('"'))) {
        val = val.substring(1, val.length - 1);
      }
      env[key] = val;
    }
  }

  // 1. Test Google Gemini SDK
  await testGeminiSdk(env['GEMINI_API_KEY']);

  // 2. Test Groq API
  await testGroq(env['GROQ_API_KEY']);

  // 3. Test OpenRouter API
  await testOpenRouter(env['OPENROUTER_API_KEY']);

  // 4. Test Cohere API
  await testCohere(env['COHERE_API_KEY']);
}

Future<void> testGeminiSdk(String? apiKey) async {
  print('--------------------------------------------------');
  print('1. Testing Google Gemini SDK (gemini-2.5-flash)...');
  if (apiKey == null || apiKey.isEmpty) {
    print('Status: SKIP (Key not configured)');
    return;
  }
  print('Key starts with: ${apiKey.substring(0, min(5, apiKey.length))}...');

  try {
    final model = GenerativeModel(
      model: 'gemini-2.5-flash',
      apiKey: apiKey,
    );
    final response = await model.generateContent([
      Content.text('Hello, this is a test from RodMae App.'),
    ]).timeout(const Duration(seconds: 12));

    final text = response.text?.trim();
    if (text != null && text.isNotEmpty) {
      print('Status: SUCCESS! Response: $text');
    } else {
      print('Status: FAILED (Empty response)');
    }
  } catch (e) {
    print('Status: ERROR ($e)');
  }
}

Future<void> testGroq(String? apiKey) async {
  print('--------------------------------------------------');
  print('2. Testing Groq API (llama-3.1-8b-instant)...');
  if (apiKey == null || apiKey.isEmpty) {
    print('Status: SKIP (Key not configured)');
    return;
  }
  print('Key starts with: ${apiKey.substring(0, min(5, apiKey.length))}...');

  try {
    final response = await http.post(
      Uri.parse('https://api.groq.com/openai/v1/chat/completions'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode({
        'model': 'llama-3.1-8b-instant',
        'messages': [
          {'role': 'user', 'content': 'Hello, this is a test.'}
        ],
      }),
    ).timeout(const Duration(seconds: 12));

    print('HTTP Status: ${response.statusCode}');
    final decoded = jsonDecode(response.body);
    if (response.statusCode == 200) {
      final text = decoded['choices']?[0]?['message']?['content'];
      print('Status: SUCCESS! Response: $text');
    } else {
      print('Status: FAILED');
      print('Response: ${JsonEncoder.withIndent('  ').convert(decoded)}');
    }
  } catch (e) {
    print('Status: ERROR ($e)');
  }
}

Future<void> testOpenRouter(String? apiKey) async {
  print('--------------------------------------------------');
  print('3. Testing OpenRouter API (openrouter/free)...');
  if (apiKey == null || apiKey.isEmpty) {
    print('Status: SKIP (Key not configured)');
    return;
  }
  print('Key starts with: ${apiKey.substring(0, min(5, apiKey.length))}...');

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
        'model': 'openrouter/free',
        'max_tokens': 1000,
        'messages': [
          {'role': 'user', 'content': 'Hello, this is a test.'}
        ],
      }),
    ).timeout(const Duration(seconds: 12));

    print('HTTP Status: ${response.statusCode}');
    final decoded = jsonDecode(response.body);
    if (response.statusCode == 200) {
      final text = decoded['choices']?[0]?['message']?['content'];
      print('Status: SUCCESS! Response: $text');
    } else {
      print('Status: FAILED');
      print('Response: ${JsonEncoder.withIndent('  ').convert(decoded)}');
    }
  } catch (e) {
    print('Status: ERROR ($e)');
  }
}

Future<void> testCohere(String? apiKey) async {
  print('--------------------------------------------------');
  print('4. Testing Cohere API...');
  if (apiKey == null || apiKey.isEmpty) {
    print('Status: SKIP (Key not configured)');
    return;
  }
  print('Key starts with: ${apiKey.substring(0, min(5, apiKey.length))}...');

  try {
    final response = await http.post(
      Uri.parse('https://api.cohere.com/v1/chat'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode({
        'message': 'Hello, this is a test.',
      }),
    ).timeout(const Duration(seconds: 12));

    print('HTTP Status: ${response.statusCode}');
    final decoded = jsonDecode(response.body);
    if (response.statusCode == 200) {
      final text = decoded['text'];
      print('Status: SUCCESS! Response: $text');
    } else {
      print('Status: FAILED');
      print('Response: ${JsonEncoder.withIndent('  ').convert(decoded)}');
    }
  } catch (e) {
    print('Status: ERROR ($e)');
  }
}

int min(int a, int b) => a < b ? a : b;
