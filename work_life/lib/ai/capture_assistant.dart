class CaptureSuggestion {
  const CaptureSuggestion({required this.kind, required this.prompt});
  final String kind;
  final String prompt;
}

/// Offline fallback used until an AI provider is configured.
/// It never writes records or changes the user's original capture.
class CaptureAssistant {
  const CaptureAssistant();

  CaptureSuggestion? suggest(String input) {
    final text = input.trim().toLowerCase();
    if (text.isEmpty) return null;
    if (text.contains('?') || text.startsWith('how ')) {
      return const CaptureSuggestion(
        kind: 'Question',
        prompt: 'Turn this into a note or research task after clarifying what answer you need.',
      );
    }
    if (RegExp(
      r'\b(have to|need to|must|should|remember to|buy|send|finish|call|return|submit|due)\b',
    ).hasMatch(text)) {
      return const CaptureSuggestion(
        kind: 'Possible task',
        prompt: 'This sounds like a commitment. Choose a next action and add a date only if you mean it.',
      );
    }
    if (RegExp(r'\b(feel|felt|worry|grateful|happy|sad|tired)\b')
        .hasMatch(text)) {
      return const CaptureSuggestion(
        kind: 'Reflection',
        prompt: 'This may be useful as a private reflection. Keep the original words unchanged.',
      );
    }
    return const CaptureSuggestion(
      kind: 'Idea',
      prompt: 'Keep this as an idea, or add it to a project when you know where it belongs.',
    );
  }
}
