/// One line of a coaching session transcript.
class CoachingTurn {
  /// 'couple' for the partners' speech, 'exodus' for the coach.
  final String speaker;
  final String text;

  CoachingTurn({required this.speaker, required this.text});

  Map<String, dynamic> toJson() => {'speaker': speaker, 'text': text};

  factory CoachingTurn.fromJson(Map<String, dynamic> j) =>
      CoachingTurn(speaker: j['speaker'] as String, text: j['text'] as String);
}

/// A completed (or in-progress) voice coaching session.
class CoachingSession {
  final String id;
  final int lengthMinutes;
  final DateTime startedAt;
  DateTime? endedAt;
  final List<CoachingTurn> transcript;

  CoachingSession({
    required this.id,
    required this.lengthMinutes,
    required this.startedAt,
    this.endedAt,
    List<CoachingTurn>? transcript,
  }) : transcript = transcript ?? [];

  factory CoachingSession.start(int lengthMinutes) {
    final now = DateTime.now();
    return CoachingSession(
      id: now.microsecondsSinceEpoch.toRadixString(36),
      lengthMinutes: lengthMinutes,
      startedAt: now,
    );
  }

  String get title {
    final m = startedAt.month.toString().padLeft(2, '0');
    final d = startedAt.day.toString().padLeft(2, '0');
    return '$lengthMinutes-min session · $m/$d';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'lengthMinutes': lengthMinutes,
        'startedAt': startedAt.toIso8601String(),
        if (endedAt != null) 'endedAt': endedAt!.toIso8601String(),
        'transcript': transcript.map((t) => t.toJson()).toList(),
      };

  factory CoachingSession.fromJson(Map<String, dynamic> j) => CoachingSession(
        id: j['id'] as String,
        lengthMinutes: j['lengthMinutes'] as int,
        startedAt: DateTime.parse(j['startedAt'] as String),
        endedAt: j['endedAt'] != null
            ? DateTime.parse(j['endedAt'] as String)
            : null,
        transcript: (j['transcript'] as List<dynamic>? ?? [])
            .map((e) => CoachingTurn.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
