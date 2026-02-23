import 'dart:convert';
import 'package:http/http.dart' as http;

/// Service for Hugging Face Inference API (free tier).
/// Get your API token at: https://huggingface.co/settings/tokens
class HuggingFaceService {
  static const String _baseUrl = 'https://api-inference.huggingface.co/models';
  static const String _chatModel = 'microsoft/DialoGPT-medium';
  static const String _textModel = 'google/flan-t5-base';

  final String apiToken;
  final http.Client _client = http.Client();

  HuggingFaceService({required this.apiToken});

  /// Chat completion for chatbot - uses conversational model
  Future<String?> chat(String userMessage, {List<Map<String, String>>? conversationHistory}) async {
    try {
      final prompt = _buildChatPrompt(userMessage, conversationHistory);
      final response = await _client.post(
        Uri.parse('$_baseUrl/$_chatModel'),
        headers: {
          'Authorization': 'Bearer $apiToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'inputs': prompt,
          'parameters': {
            'max_new_tokens': 150,
            'temperature': 0.7,
            'do_sample': true,
          },
        }),
      );

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        String? fullText;
        if (decoded is List && decoded.isNotEmpty) {
          fullText = decoded[0]['generated_text']?.toString().trim();
        } else if (decoded is Map && decoded['generated_text'] != null) {
          fullText = decoded['generated_text'].toString().trim();
        }
        if (fullText != null) {
          // DialoGPT returns prompt + response; strip the prompt
          final promptEnd = 'Assistant:';
          final idx = fullText.lastIndexOf(promptEnd);
          if (idx >= 0) {
            return fullText.substring(idx + promptEnd.length).trim();
          }
          return fullText;
        }
      } else if (response.statusCode == 503) {
        return 'Model is loading. Please try again in a few seconds.';
      } else {
        final err = jsonDecode(response.body);
        return 'Error: ${err['error'] ?? response.statusCode}';
      }
    } catch (e) {
      return 'Failed to get response: $e';
    }
    return null;
  }

  String _buildChatPrompt(String userMessage, List<Map<String, String>>? history) {
    final buffer = StringBuffer();
    if (history != null && history.isNotEmpty) {
      for (final m in history) {
        final role = m['role'] ?? '';
        final content = m['content'] ?? '';
        buffer.writeln(role == 'user' ? 'User: $content' : 'Assistant: $content');
      }
    }
    buffer.writeln('User: $userMessage');
    buffer.write('Assistant:');
    return buffer.toString();
  }

  /// Text generation for event description
  Future<String?> generateEventDescription({
    required String eventName,
    String? eventType,
    String? location,
    List<String>? lookingFor,
  }) async {
    try {
      final lookingForStr = lookingFor?.isNotEmpty == true
          ? ' looking for: ${lookingFor!.join(", ")}'
          : '';
      final prompt = 'Write a short engaging event description for: $eventName. '
          'Type: ${eventType ?? "event"}. '
          '${location != null ? "Location: $location. " : ""}'
          '$lookingForStr. '
          'Keep it under 100 words.';

      final response = await _client.post(
        Uri.parse('$_baseUrl/$_textModel'),
        headers: {
          'Authorization': 'Bearer $apiToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'inputs': prompt,
          'parameters': {
            'max_new_tokens': 120,
            'temperature': 0.8,
          },
        }),
      );

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is List && decoded.isNotEmpty) {
          return decoded[0]['generated_text']?.toString().trim();
        }
        if (decoded is Map && decoded['generated_text'] != null) {
          return decoded['generated_text'].toString().trim();
        }
      } else if (response.statusCode == 503) {
        return null; // Model loading - caller can show retry
      }
    } catch (_) {}
    return null;
  }

  /// Generate event recommendations based on user preferences
  Future<String?> getEventRecommendations({
    required List<Map<String, dynamic>> availableEvents,
    String? userPreference,
    String? userRole,
  }) async {
    if (availableEvents.isEmpty) return null;

    try {
      final eventsSummary = availableEvents.take(15).map((e) {
        final name = e['name'] ?? 'Unknown';
        final type = e['type'] ?? '';
        final loc = e['location'] ?? (type == 'online' ? 'Online' : '');
        final descRaw = (e['description'] ?? '').toString();
        final desc = descRaw.length > 80 ? '${descRaw.substring(0, 80)}...' : descRaw;
        return '- $name ($type${loc.isNotEmpty ? ", $loc" : ""}): $desc';
      }).join('\n');

      final prompt = 'Given these events:\n$eventsSummary\n\n'
          '${userPreference != null && userPreference.isNotEmpty ? "User preference: $userPreference. " : ""}'
          '${userRole != null && userRole.isNotEmpty ? "User role: $userRole. " : ""}'
          'Recommend top 3-5 events that would be most relevant. '
          'Reply with a short list of event names and one line why each is recommended.';

      final response = await _client.post(
        Uri.parse('$_baseUrl/$_textModel'),
        headers: {
          'Authorization': 'Bearer $apiToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'inputs': prompt,
          'parameters': {
            'max_new_tokens': 200,
            'temperature': 0.7,
          },
        }),
      );

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is List && decoded.isNotEmpty) {
          return decoded[0]['generated_text']?.toString().trim();
        }
        if (decoded is Map && decoded['generated_text'] != null) {
          return decoded['generated_text'].toString().trim();
        }
      } else if (response.statusCode == 503) {
        return null;
      }
    } catch (_) {}
    return null;
  }

  void dispose() {
    _client.close();
  }
}
