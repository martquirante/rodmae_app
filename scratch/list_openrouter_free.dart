import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  print('--- Fetching all free models from OpenRouter ---');
  try {
    final response = await http.get(Uri.parse('https://openrouter.ai/api/v1/models'));
    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      final data = decoded['data'] as List?;
      if (data == null) return;
      print('Free models list:');
      for (var model in data) {
        final id = model['id'] as String;
        if (id.endsWith(':free') || id.contains('free')) {
          print('  - $id (${model['name']})');
        }
      }
    } else {
      print('Failed to load: ${response.statusCode}');
    }
  } catch (e) {
    print('Error: $e');
  }
}
