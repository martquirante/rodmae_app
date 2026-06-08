import 'dart:typed_data';
import 'package:google_generative_ai/google_generative_ai.dart';
import '../core/constants.dart';
import '../core/utils.dart';
import '../models/meal_plan.dart';

final class GeminiCompanionService {
  GeminiCompanionService._();

  static final GeminiCompanionService instance = GeminiCompanionService._();

  GenerativeModel get _model => GenerativeModel(
        model: 'gemini-1.5-flash',
        apiKey: AppConfig.geminiApiKey,
      );

  Future<ReceiptExtraction> scanReceipt(Uint8List imageBytes) async {
    const prompt =
        'Extract Total Amount, Store Name, and Category. Return valid JSON only.';
    final response = await _model.generateContent([
      Content.multi([
        TextPart(prompt),
        DataPart('image/jpeg', imageBytes),
      ]),
    ]);
    final json = JsonResponseParser.objectFromText(response.text ?? '{}');
    return ReceiptExtraction.fromJson(json);
  }

  Future<List<MealPlanDay>> generateMealPlan(String userPrompt) async {
    final response = await _model.generateContent([
      Content.text(
        '$userPrompt\n'
        'Return valid JSON only. Return an array of exactly 7 objects. '
        'Each object must have day, breakfast, lunch, dinner, and ingredients. '
        'ingredients must be an array of grocery item strings. Use practical '
        'budget-friendly Filipino meals for newlyweds.',
      ),
    ]);
    final rows = JsonResponseParser.arrayFromText(response.text ?? '[]');
    final plan = rows.map(MealPlanDay.fromJson).toList();
    if (plan.length != 7) {
      throw const FormatException('Gemini did not return exactly 7 meal days.');
    }
    return plan;
  }
}
