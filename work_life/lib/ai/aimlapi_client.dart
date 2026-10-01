import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'ai_proposals.dart';

class AiSuggestionResult {
  const AiSuggestionResult({required this.text, required this.model});
  final String text;
  final String model;
}

class AiServiceException implements Exception {
  const AiServiceException(
    this.message, {
    this.statusCode,
    this.diagnosticMessage,
  });
  final String message;
  final int? statusCode;
  final String? diagnosticMessage;

  @override
  String toString() => message;
}

class AimlApiClient {
  static bool get environmentConfigured {
    const proxy = String.fromEnvironment('WORK_LIFE_AI_PROXY_URL');
    const key = String.fromEnvironment('AIMLAPI_KEY');
    const local = bool.fromEnvironment('ALLOW_INSECURE_LOCAL_AI');
    return proxy.trim().isNotEmpty ||
        (!kReleaseMode &&
            local &&
            key.trim().isNotEmpty &&
            key != 'replace_with_your_key');
  }

  AimlApiClient({
    http.Client? client,
    String? apiKey,
    String? model,
    String? baseUrl,
    String? proxyUrl,
    bool? allowDirectProvider,
    Future<String?> Function()? accessToken,
    this.requestTimeout = const Duration(seconds: 35),
  }) : _client = client ?? http.Client(),
       apiKey = apiKey ?? const String.fromEnvironment('AIMLAPI_KEY'),
       model =
           model ??
           const String.fromEnvironment(
             'AIMLAPI_MODEL',
             defaultValue: 'google/gemini-3-8-flash',
           ),
       baseUrl =
           baseUrl ??
           const String.fromEnvironment(
             'AIMLAPI_BASE_URL',
             defaultValue: 'https://api.aimlapi.com/v1',
           ),
       proxyUrl =
           proxyUrl ?? const String.fromEnvironment('WORK_LIFE_AI_PROXY_URL'),
       allowDirectProvider =
           allowDirectProvider ??
           (apiKey != null ||
               const bool.fromEnvironment('ALLOW_INSECURE_LOCAL_AI')),
       _accessToken = accessToken ?? _supabaseAccessToken;

  final http.Client _client;
  final String apiKey, model, baseUrl, proxyUrl;
  final bool allowDirectProvider;
  final Future<String?> Function() _accessToken;
  final Duration requestTimeout;
  bool get _directConfigured =>
      !kReleaseMode &&
      allowDirectProvider &&
      apiKey.trim().isNotEmpty &&
      apiKey != 'replace_with_your_key';
  bool get configured => proxyUrl.trim().isNotEmpty || _directConfigured;

  Future<AiSuggestionResult> suggest({required String capture}) async {
    if (!configured) {
      throw StateError(
        'AI is not configured. Offline suggestions remain available.',
      );
    }
    final response = await _post('suggest', {
      'model': model,
      'temperature': 0.2,
      'messages': [
        {
          'role': 'system',
          'content': 'You help organize a personal work-life capture. Return an editable review using exactly these headings: Rephrased title, Suggested area, Outcome, Next actions, Checklist, Clarifying questions. Keep the original meaning, do not invent dates or commitments, and clearly mark uncertainty.',
        },
        {'role': 'user', 'content': capture},
      ],
    });
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _failure(response);
    }
    final body = jsonDecode(response.body);
    final content = body is Map ? body['choices'] : null;
    final text = content is List && content.isNotEmpty
        ? ((content.first as Map)['message'] as Map)['content']
              ?.toString()
              .trim()
        : null;
    if (text == null || text.isEmpty) {
      throw const FormatException('AI returned no usable suggestion.');
    }
    return AiSuggestionResult(text: text, model: model);
  }

  Future<AiScheduleProposal> analyzeScheduleImage(Uint8List bytes) async {
    if (!configured) throw StateError('AI is not configured.');
    if (bytes.length > 5 * 1024 * 1024) {
      throw ArgumentError('Choose an image smaller than 5 MB.');
    }
    final timer = Stopwatch()..start();
    final encoded = base64Encode(bytes);
    if (kDebugMode) {
      debugPrint(
        '[WORK_LIFE_IMPORT] encoded ${bytes.length} bytes in ${timer.elapsedMilliseconds}ms',
      );
    }
    try {
      final response = await _post('schedule_image', {
        'model': model,
        'temperature': 0.1,
        'messages': [
          {
            'role': 'system',
            'content': 'Extract a schedule image into an editable proposal. Return JSON only with this shape: {"type":"schedule_proposal","events":[{"title":"","kind":"classSession|work|meeting|commitment|other","area":null,"weekday":1,"date":"YYYY-MM-DD or null","start":"HH:mm or null","end":"HH:mm or null","notes":""}],"questions":[]}. For a weekly timetable set weekday to Monday=1 through Sunday=7 only when the image clearly identifies it; otherwise use null and add a question. Classify only from clear labels; use classSession only for a clearly identified class. Never invent dates or times; use null and add a question when unreadable.',
          },
          {
            'role': 'user',
            'content': [
              {
                'type': 'text',
                'text': 'Read this schedule and propose calendar events. Keep uncertainty in questions.',
              },
              {
                'type': 'image_url',
                'image_url': {'url': 'data:image/jpeg;base64,$encoded'},
              },
            ],
          },
        ],
      });
      if (kDebugMode) {
        debugPrint(
          '[WORK_LIFE_IMPORT] provider response in ${timer.elapsedMilliseconds}ms status=${response.statusCode}',
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw _failure(response);
      }
      final body = jsonDecode(response.body);
      final choices = body is Map ? body['choices'] : null;
      final text = choices is List && choices.isNotEmpty
          ? ((choices.first as Map)['message'] as Map)['content']
                ?.toString()
                .trim()
          : null;
      if (text == null || text.isEmpty) {
        throw const FormatException('AI returned no schedule proposal.');
      }
      final proposal = const AiProposalParser().schedule(text);
      if (kDebugMode) {
        debugPrint(
          '[WORK_LIFE_IMPORT] parsed ${proposal.events.length} events in ${timer.elapsedMilliseconds}ms total',
        );
      }
      return proposal;
    } on TimeoutException {
      throw const AiServiceException(
        'Schedule reading timed out. Try again with a clearer or smaller image.',
      );
    }
  }

  Future<AiProjectProposal> breakdown(String input) async {
    final result = await _complete(
      system: 'Return JSON only: {"type":"project_proposal","project":{"title":"","description":"","area":null,"tasks":[{"taskId":null,"title":"","area":null,"priority":"low|medium|high","minutes":25,"deadline":null,"reminder":null,"checklist":[]}]},"questions":[]}. Turn the input into practical, independently completable actions in the order they must happen. Preserve dependencies in task order and concise descriptions/checklists. Real-life actions such as travel, errands, appointments, household work, preparation, social commitments, personal care and rest are valid work-life content. Do not collapse multiple actions into one task and do not invent dates.',
      user: input,
    );
    return const AiProposalParser().project(result.text);
  }

  Future<AiCaptureProposal> classifyCapture(
    String input, {
    DateTime? now,
    List<String> existingAreas = const [],
  }) async {
    final localNow = (now ?? DateTime.now()).toLocal();
    final result = await _complete(
      system: '''Classify one capture and return JSON only. Shape: {"type":"capture_proposal","kind":"standalone_task|project|routine|reminder|planning_request","task":{"title":"","area":null,"priority":"low|medium|high","minutes":25,"deadline":"YYYY-MM-DD or null","reminder":"ISO-8601 with offset or null","checklist":[]},"project":{"title":"","description":"","area":null,"tasks":[]},"routine":{"title":"","area":null,"window":"human-readable days/time","minimum":"smallest version","normal":"","strong":""},"planningDate":"YYYY-MM-DD or null","questions":[]}. Include only the object relevant to kind. A single independently completable action is standalone_task. Two or more distinct actions, even in one sentence, are a project with one ordered task per action; preserve sequence and dependencies. For example, traveling to collect a person and then collecting a parcel are separate ordered actions, not one vague task. A repeating behavior is routine, an explicit request to alert the user is reminder, and a request to arrange time is planning_request. Understand everyday life broadly: commuting, travel, errands, shopping, pickups, appointments, cleaning, laundry, cooking, personal care, preparation, social/family time, breaks and rest are meaningful activities. Choose an exact existing Life Area when it fits semantically and case-insensitively. Suggest one concise reusable new area only when none fits; never create synonyms or near-duplicates. Preserve intent, resolve relative dates only from the supplied local timestamp, never invent a date, and ask questions only for genuine uncertainty.''',
      user: jsonEncode({
        'localNow': localNow.toIso8601String(),
        'capture': input,
        'existingAreas': existingAreas,
      }),
    );
    return const AiProposalParser().capture(result.text);
  }

  Future<AiScheduleProposal> planDay(String context) async {
    final result = await _complete(
      system: '''Return JSON only: {"type":"schedule_proposal","events":[{"planId":null,"recurringScheduleId":null,"taskId":null,"title":"","area":null,"date":null,"start":null,"end":null,"kind":"task|focus|exercise|meal|break|coffee|travel|commute|errand|appointment|household|social|preparation|personal|rest|routine|free_time|existing_planner","operation":"add|move|change|remove|unchanged","locked":false,"notes":"short user-facing reason"}],"questions":[]}. Use supplied taskId, planId and recurringScheduleId values exactly when referring to existing records. Treat fixed commitments and locked blocks as hard constraints. Respect wake/bed, avoid-focus-after, available capacity, deadlines, priorities, duration estimates and transition buffers. Build a realistic whole-life plan, not merely tasks plus meals and exercise: account for travel between places, commuting, errands, appointments, household chores, preparation, personal care, social/family time, recovery and intentional free time when supported by the supplied context or request. Existing actionable items such as a parcel pickup keep their taskId; supportive lifestyle blocks have taskId null and never become fake tasks. Do not manufacture optional commitments. If workload does not fit, move low-priority work to another feasible date and explain it. Preserve unrelated existing blocks for adjustment requests. Never invent a date or commitment.''',
      user: context,
    );
    return const AiProposalParser().schedule(result.text);
  }

  Future<AiScheduleProposal> planWeek(String context) async {
    final result = await _complete(
      system: '''Return JSON only: {"type":"schedule_proposal","events":[{"planId":null,"recurringScheduleId":null,"taskId":null,"title":"","area":null,"date":null,"start":null,"end":null,"kind":"task|focus|exercise|meal|break|coffee|travel|commute|errand|appointment|household|social|preparation|personal|rest|routine|free_time|existing_planner","operation":"add|move|change|remove|unchanged","locked":false,"notes":"short user-facing reason"}],"questions":[]}. Create one feasible Monday-to-Sunday whole-life plan from the supplied context. Use taskId, planId and recurringScheduleId exactly. Fixed commitments and locked blocks are hard constraints. Existing flexible blocks need an explicit operation. Schedule work before deadlines without accidental duplication or exceeding estimates. Balance demanding work across days. Include realistic transition/travel time and, when supported by context, commuting, errands, appointments, household work, preparation, personal care, social/family time, recovery and free time—not just meals and exercise. Existing actionable errands retain taskId; supportive lifestyle blocks have taskId null. Do not manufacture commitments. If workload cannot fit, leave lower-priority work unscheduled and explain it. Preserve unrelated blocks for adjustment requests. Never invent dates outside the supplied week.''',
      user: context,
    );
    return const AiProposalParser().schedule(result.text);
  }

  Future<AiProjectProposal> improveProject(String context) async {
    final result = await _complete(
      system: 'Return JSON only: {"type":"project_proposal","project":{"title":"","description":"","area":null,"tasks":[{"taskId":null,"operation":"add|change|move|remove|unchanged","title":"","area":null,"priority":"low|medium|high","minutes":25,"deadline":null,"reminder":null,"checklist":[]}]},"questions":[]}. Include every existing task exactly once with its taskId and an explicit operation. New tasks use taskId null and add. Use move only for a due-date move. Removal is only a proposal for user review. Do not invent dates.',
      user: context,
    );
    return const AiProposalParser().project(result.text);
  }

  Future<AiSuggestionResult> _complete({
    required String system,
    required String user,
  }) async {
    if (!configured) throw StateError('AI is not configured.');
    final response = await _post('structured_completion', {
      'model': model,
      'temperature': 0.1,
      'messages': [
        {'role': 'system', 'content': system},
        {'role': 'user', 'content': user},
      ],
    });
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _failure(response);
    }
    final body = jsonDecode(response.body);
    final choices = body is Map ? body['choices'] : null;
    final text = choices is List && choices.isNotEmpty
        ? ((choices.first as Map)['message'] as Map)['content']
              ?.toString()
              .trim()
        : null;
    if (text == null || text.isEmpty) {
      throw const FormatException('AI returned no usable proposal.');
    }
    return AiSuggestionResult(text: text, model: model);
  }

  AiServiceException _failure(http.Response response) {
    String? providerMessage;
    try {
      final body = jsonDecode(response.body);
      if (body is Map) {
        final error = body['error'];
        if (error is Map) {
          providerMessage = error['message']?.toString();
        } else if (error != null) {
          providerMessage = error.toString();
        }
      }
    } catch (_) {
      // Never expose an unstructured provider response in the app UI.
    }
    final userMessage = switch (response.statusCode) {
      401 || 403 => 'AI assistance could not sign in. Check the app configuration and try again.',
      402 => 'AI assistance is unavailable for this account right now.',
      404 => 'The selected AI model is no longer available. Update the app’s AI configuration.',
      429 => 'AI assistance is busy right now. Wait briefly and retry.',
      >= 500 => 'AI assistance is temporarily unavailable. Retry in a moment.',
      _ => 'Couldn’t complete the AI request. Please try again.',
    };
    final safeMessage = providerMessage
        ?.replaceAll(RegExp(r'[\r\n]+'), ' ')
        .trim();
    return AiServiceException(
      userMessage,
      statusCode: response.statusCode,
      diagnosticMessage: safeMessage == null || safeMessage.isEmpty
          ? null
          : safeMessage.length > 240
          ? '${safeMessage.substring(0, 240)}…'
          : safeMessage,
    );
  }

  Future<http.Response> _post(
    String operation,
    Map<String, Object?> providerRequest,
  ) async {
    if (proxyUrl.trim().isNotEmpty) {
      final token = await _accessToken();
      if (token == null || token.isEmpty) {
        throw StateError('Sign in to use AI assistance.');
      }
      return _client
          .post(
            Uri.parse(proxyUrl),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'operation': operation,
              'request': providerRequest,
            }),
          )
          .timeout(requestTimeout);
    }
    if (!_directConfigured) {
      throw StateError(
        'AI requires the secure proxy. Direct provider access is debug-only.',
      );
    }
    return _client
        .post(
          Uri.parse('$baseUrl/chat/completions'),
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(providerRequest),
        )
        .timeout(requestTimeout);
  }

  static Future<String?> _supabaseAccessToken() async {
    try {
      return Supabase.instance.client.auth.currentSession?.accessToken;
    } catch (_) {
      return null;
    }
  }

  void dispose() => _client.close();
}
