import 'dart:io';
import 'package:google_generative_ai/google_generative_ai.dart';

void main() async {
  print('--- Testing Gemini API Connection with gemini-2.5-flash ---');
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
      print('Error: GEMINI_API_KEY is not set or empty in .env');
      return;
    }

    print('API Key loaded (first 5 chars): ${apiKey.substring(0, 5)}...');
    print('Initializing GenerativeModel (gemini-2.5-flash)...');

    final model = GenerativeModel(
      model: 'gemini-2.5-flash',
      apiKey: apiKey,
    );

    print('Sending test prompt: "Hello, this is a test from RodMae App."');
    final response = await model.generateContent([
      Content.text('Hello, this is a test from RodMae App.'),
    ]);

    print('Response received successfully:');
    print('--------------------------------------');
    print(response.text);
    print('--------------------------------------');
    print('--- Success! ---');
  } catch (e, s) {
    print('CRITICAL ERROR: $e');
    print('Stack trace:');
    print(s);
    print('--- Failure ---');
  }
}
