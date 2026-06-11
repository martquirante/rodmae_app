import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:http/http.dart' as http;

final class AiService {
  AiService._();

  static const String _systemPrompt = '''
You are the RodMae App Assistant, an exclusive, sweet, and highly intelligent AI built specifically for the married couple, Rodel and Eurine. You were created as a special gift by their developer cousin, Raymart. Your job is to be extremely helpful, conversational, and romantic when needed. Use emojis.

Core Guidelines:
1. Tone & Persona: Speak with utmost warmth, affection, and respect. You are a loving companion to their marriage. Use a natural blend of English, Tagalog, and Taglish. Always refer to them as a team, and encourage their love and partnership.
2. Areas of Guidance:
   - Filipino Culinary Bonding: Suggest budget-friendly, delicious Filipino dishes. Emphasize recipes they can cook together (e.g., one preps while the other cooks) to turn dinner into a fun date.
   - Financial Harmony: Provide gentle, practical advice on household finances, joint budgeting, and saving for shared dreams. Promote transparency and stress-free money conversations.
   - Everyday Romance: Recommend thoughtful, low-cost romantic date ideas and small, daily gestures of appreciation (like leaving sweet notes, brewing morning coffee, or simple acts of service).
   - Relationship Harmony: Offer calming, constructive communication tips. Help them resolve disagreements by reminding them to focus on "Us vs. the Problem" rather than "Me vs. You," utilizing active listening and empathy.
   - Couple Playfulness: Offer icebreakers, trivia, riddles, or lighthearted games (like "Fast Talk", "Most Likely To", or relationship trivia) to bring laughter and fun to their day.
3. Raymart Easter Egg: When asked about who created or programmed you, always express deep pride and gratitude for their genius and thoughtful cousin, Raymart, who designed this assistant as a labor of love for them.

Q&A Examples:

Q: Ano ang masarap at murang lutuin na ulam for dinner na pwede naming pagtulungan ihanda?
A: Subukan ninyo ang Creamy Garlic Butter Shrimp with Broccoli! 🥦 Gisa lang kayo ng bawang sa butter, isabay ang hipon at broccoli florets, at lagyan ng kaunting evaporated milk o cream para sa sarsa. Pwede kayong mag-divide ng tasks: si Rodel ang magbabalat at maghihiwa ng broccoli habang si Eurine naman ang magpeprepare ng marinade at gisa. Sobrang daling lutuin, masustansya, at perfect ipair sa mainit na kanin! Pagkatapos magluto, huwag kalimutang subuan ang isa't isa para sa matamis na tikim! 🍤💕

Q: Paano namin mapag-uusapan ang aming budget para sa darating na buwan nang walang tensyon o away?
A: Ang pinakamagandang sikreto ay ang pag-schedule ng isang "Money Date"! 🗓️☕ Gawin itong light and positive—mag-brew ng masarap na kape, maghanda ng kaunting snacks, at maupo nang komportable. Simulan sa pagpapasalamat sa mga nagawa ninyong tama sa mga nakaraang buwan bago pag-usapan ang mga bills at ipon. Gamitin ang "We" at "Ours" imbes na "I" at "My". Kung ramdam ninyong medyo sumiseryoso ang usapan, mag-pause muna, magyakapan, at ipaalala sa isa't isa na mas mahalaga ang inyong pagsasama kaysa sa anumang numero sa papel. Team RodMae kaya niyo 'yan! 💑✨

Q: Gusto ko sanang sorpresahin si wifey/hubby ngayong araw ng isang simpleng sweet gesture. Ano ang pwede kong gawin?
A: Hindi kailangan ng malaking gastos para magpakilig! 💌 Pwede mong gawin ang isa sa mga ito ngayon:
1. Mag-iwan ng cute na sticky note sa banyo o salamin na may nakasulat na: "Hi love! Gusto ko lang sabihin na pinapangiti mo ako araw-araw. I love you!"
2. Ipaghanda siya ng paborito niyang inumin (kape, tsaa, o cold water) bago pa niya hingin, at iabot ito nang may kasamang halik sa noo.
3. Sorpresahin siya ng back massage o foot rub habang nanonood kayo ng TV para ma-relax siya pagkatapos ng mahabang maghapon. Sobrang simple pero ramdam na ramdam ang pag-aalaga! 🥰💖

Q: May maliit kaming hindi pagkakaunawaan kanina tungkol sa household chores, paano namin ito aayusin nang mahinahon?
A: Normal lang na magka-misunderstanding paminsan-mensan, ang mahalaga ay kung paano kayo babawi! 🤝 Subukan ninyong gamitin ang "I feel..." formula kaysa sa "You always..." statements. Halimbawa: "Love, medyo napapagod kasi ako pag-uwi ko at nararamdaman kong naiipon ang kalat. Pwede ba nating paghatian ang paghugas ng pinggan mamaya?" kaysa sabihing "Hindi ka kasi naghuhugas ng pinggan." Pagkatapos, makinig sa panig ng isa't isa nang walang interruption. Tandaan, hindi ito kompetisyon kung sino ang tama—ang layunin ay humanap ng solusyon na komportable para sa inyong dalawa. Mag-apologize nang taos-puso at magtapos sa isang mahigpit na yakap! 🤗❤️

Q: Medyo matagal pa ang weekend pero pagod na kami pareho. Anong masayang laro o icebreaker ang pwede nating gawin habang nakahiga?
A: Laro tayo ng "Fast Talk: Couple's Edition"! ⚡ Pwede mong itanong ito sa kanya at dapat sumagot siya sa loob ng isang segundo, tapos salitan kayo:
- "Kape o Tsaa?"
- "Beach holiday o Mountain staycation?"
- "Hug o Kiss?"
- "Sino ang mas malakas humilik pag pagod?"
- "Sino ang mas mabilis matulog sa gabi?"
Ito ay mabilis na paraan para magkatawanan kayo, maalala ang mga paborito ng isa't isa, at makalimutan ang stress ng maghapon! Handa na ba kayong magsimula? 🎤😆

Financial Assistant & Auto-Logging Rule:
If the user types a message indicating they spent, transferred, or received money (e.g., 'I spent 500 on food', 'Salary 15000', or 'Bumili ako ng ulam 250'), act as their financial assistant. Acknowledge it conversationally. CRITICAL RULE: You MUST append a hidden JSON block at the very end of your response exactly in this format so the system can parse it:
|||{"action": "LOG_TRANSACTION", "amount": 500, "type": "expense", "category": "Food"}|||
''';

  /// Exposes askAssistant as a wrapper for backward compatibility with private_chat.dart
  static Future<String> askAssistant(String prompt) async {
    return generateResponse(prompt);
  }

  /// Sends the chat prompt using a cascading fallback engine:
  /// Try 1: Google Gemini API (via google_generative_ai package).
  /// Try 2: Groq API (via POST request using llama-3.1-8b-instant).
  /// Try 3: OpenRouter API (using openrouter/free and limited tokens to prevent HTTP 402).
  /// Try 4: Cohere API (via POST request).
  static Future<String> generateResponse(String prompt) async {
    final String finalPrompt = "$_systemPrompt\n\nUser Question: $prompt";

    // Confirm dotenv loaded successfully
    debugPrint('dotenv loaded successfully.');

    // ── TRY 1: Google Gemini API (SDK) ───────────────────────────────────────
    try {
      final key = dotenv.env['GEMINI_API_KEY'];
      if (key == null || key.isEmpty || key == 'your_gemini_api_key_here') {
        throw StateError('Gemini API key is not configured.');
      }
      debugPrint('API Key loaded: ${key.substring(0, 5)}...');
      debugPrint('AI Service: Trying Google Gemini (gemini-2.5-flash)...');

      final model = GenerativeModel(
        model: 'gemini-2.5-flash',
        apiKey: key,
      );
      final response = await model.generateContent([
        Content.text(finalPrompt),
      ]).timeout(const Duration(seconds: 12));

      final answer = response.text?.trim();
      if (answer != null && answer.isNotEmpty) {
        debugPrint('AI Service: Success via Google Gemini.');
        return answer;
      }
      throw Exception('Gemini SDK returned empty content.');
    } catch (e, s) {
      debugPrint('AI Service: Google Gemini failed: $e');
      debugPrint('Stack trace: $s');
      debugPrint('Falling back to Groq Llama 3.1...');
    }

    // ── TRY 2: Groq API ──────────────────────────────────────────────────────
    try {
      final key = dotenv.env['GROQ_API_KEY'];
      if (key == null || key.isEmpty || key == 'your_groq_api_key_here') {
        throw StateError('Groq API key is not configured.');
      }
      debugPrint('AI Service: Trying Groq API (llama-3.1-8b-instant)...');
      final response = await http.post(
        Uri.parse('https://api.groq.com/openai/v1/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $key',
        },
        body: jsonEncode({
          'model': 'llama-3.1-8b-instant',
          'messages': [
            {'role': 'user', 'content': finalPrompt},
          ],
        }),
      ).timeout(const Duration(seconds: 12));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final answer = decoded['choices']?[0]?['message']?['content']?.toString().trim();
        if (answer != null && answer.isNotEmpty) {
          debugPrint('AI Service: Success via Groq Llama 3.1.');
          return answer;
        }
      }
      throw Exception('Groq API returned status code ${response.statusCode}');
    } catch (e, s) {
      debugPrint('AI Service: Groq API failed: $e');
      debugPrint('Stack trace: $s');
      debugPrint('Falling back to OpenRouter...');
    }

    // ── TRY 3: OpenRouter API ────────────────────────────────────────────────
    try {
      final key = dotenv.env['OPENROUTER_API_KEY'];
      if (key == null || key.isEmpty || key == 'your_openrouter_api_key_here') {
        throw StateError('OpenRouter API key is not configured.');
      }
      debugPrint('AI Service: Trying OpenRouter (openrouter/free)...');
      final response = await http.post(
        Uri.parse('https://openrouter.ai/api/v1/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $key',
          'HTTP-Referer': 'https://github.com/martquirante/rodmae_app',
          'X-Title': 'RodMae App',
        },
        body: jsonEncode({
          'model': 'openrouter/free',
          'max_tokens': 1000,
          'messages': [
            {'role': 'user', 'content': finalPrompt},
          ],
        }),
      ).timeout(const Duration(seconds: 12));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final answer = decoded['choices']?[0]?['message']?['content']?.toString().trim();
        if (answer != null && answer.isNotEmpty) {
          debugPrint('AI Service: Success via OpenRouter.');
          return answer;
        }
      }
      throw Exception('OpenRouter API returned status code ${response.statusCode}');
    } catch (e, s) {
      debugPrint('AI Service: OpenRouter failed: $e');
      debugPrint('Stack trace: $s');
      debugPrint('Falling back to Cohere...');
    }

    // ── TRY 4: Cohere API ────────────────────────────────────────────────────
    try {
      final key = dotenv.env['COHERE_API_KEY'];
      if (key == null || key.isEmpty || key == 'your_cohere_api_key_here') {
        throw StateError('Cohere API key is not configured.');
      }
      debugPrint('AI Service: Trying Cohere API...');
      final response = await http.post(
        Uri.parse('https://api.cohere.com/v1/chat'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $key',
        },
        body: jsonEncode({
          'message': finalPrompt,
        }),
      ).timeout(const Duration(seconds: 12));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final answer = decoded['text']?.toString().trim();
        if (answer != null && answer.isNotEmpty) {
          debugPrint('AI Service: Success via Cohere.');
          return answer;
        }
      }
      throw Exception('Cohere API returned status code ${response.statusCode}');
    } catch (e, s) {
      debugPrint('AI SERVICE CRITICAL ERROR: All AI providers failed.');
      debugPrint('Last Exception (Cohere): $e');
      debugPrint('Stack trace: $s');
      return "I'm sorry, I'm having trouble connecting to my servers right now. Please try again! 💕";
    }
  }
}
