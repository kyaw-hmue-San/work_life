import 'dart:math';

class Capture {
  const Capture({
    required this.id,
    required this.originalText,
    required this.createdAt,
  });

  factory Capture.create(String text) {
    final random = Random.secure();
    final id = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    return Capture(
      id: id,
      originalText: text,
      createdAt: DateTime.now().toUtc(),
    );
  }

  final String id;
  final String originalText;
  final DateTime createdAt;
}
