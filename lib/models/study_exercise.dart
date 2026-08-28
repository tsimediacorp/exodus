/// One day's Bible study exercise.
///
/// Deliberately not a devotional. A devotional is something you read; an
/// exercise is something you *do* — [steps] is the practice, and the day is
/// not finished by scrolling to the bottom of it.
class StudyExercise {
  /// Day key, yyyy-mm-dd — also the storage identity (one per day).
  final String dayKey;
  final DateTime day;

  /// What the practice is called, e.g. "Take the Enemy to Court".
  final String title;

  /// The form of the exercise, e.g. "courtroom", "word study". Kept so the
  /// generator can be told which forms have come up lately: without it the
  /// model settles into producing the same shape with different verses.
  final String form;

  /// One line on what this practice is for.
  final String premise;

  final String scriptureRef;
  final String scriptureText;

  /// The exercise itself, in order. Each step is a plain instruction.
  final List<String> steps;

  /// The question to sit with once the steps are done.
  final String question;

  final String closingPrayer;

  /// When the couple marked this done, or null while it is still open.
  DateTime? completedAt;

  /// Whatever they wrote in response to [question]. Stays on the device.
  String notes;

  /// True when this came from the built-in bank rather than the model.
  /// Persisted so a day that fell back can be retried once the network is
  /// healthy again, instead of serving canned content until midnight.
  final bool isFallback;

  bool get isComplete => completedAt != null;

  StudyExercise({
    required this.day,
    required this.title,
    required this.form,
    required this.premise,
    required this.scriptureRef,
    required this.scriptureText,
    required this.steps,
    required this.question,
    required this.closingPrayer,
    this.completedAt,
    this.notes = '',
    this.isFallback = false,
  }) : dayKey = keyFor(day);

  /// Whether what's stored for a day needs (re)generating. Unlike the
  /// devotional there is no goal to compare against, so this is only about
  /// having nothing, or having canned content we can now improve on.
  ///
  /// A fallback the couple has already worked through is NOT regenerated —
  /// replacing an exercise underneath someone who is halfway through it, or
  /// who finished it and wrote notes against it, would be worse than serving
  /// canned content.
  static bool needsGeneration(StudyExercise? existing) =>
      existing == null ||
      (existing.isFallback &&
          !existing.isComplete &&
          existing.notes.trim().isEmpty);

  static String keyFor(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Build from the model's JSON object. Tolerates missing keys and accepts
  /// `steps` as either a list or a single newline-separated string, since
  /// models drift between the two.
  factory StudyExercise.fromGenerated({
    required DateTime day,
    required Map<String, dynamic> json,
    bool isFallback = false,
  }) {
    String s(String k) => (json[k] ?? '').toString().trim();

    final rawSteps = json['steps'];
    final steps = <String>[];
    if (rawSteps is List) {
      for (final step in rawSteps) {
        final text = step.toString().trim();
        if (text.isNotEmpty) steps.add(text);
      }
    } else if (rawSteps is String) {
      for (final line in rawSteps.split('\n')) {
        // Strip any numbering the model added; the UI numbers them itself.
        final text =
            line.trim().replaceFirst(RegExp(r'^\s*(\d+[.)]|[-*])\s*'), '');
        if (text.isNotEmpty) steps.add(text);
      }
    }

    return StudyExercise(
      day: day,
      title: s('title').isEmpty ? 'Today\'s Exercise' : s('title'),
      form: s('form'),
      premise: s('premise'),
      scriptureRef: s('scriptureRef'),
      scriptureText: s('scriptureText'),
      steps: steps,
      question: s('question'),
      closingPrayer: s('closingPrayer'),
      isFallback: isFallback,
    );
  }

  Map<String, dynamic> toJson() => {
        'day': day.toIso8601String(),
        'title': title,
        'form': form,
        'premise': premise,
        'scriptureRef': scriptureRef,
        'scriptureText': scriptureText,
        'steps': steps,
        'question': question,
        'closingPrayer': closingPrayer,
        'completedAt': completedAt?.toIso8601String(),
        'notes': notes,
        'isFallback': isFallback,
      };

  factory StudyExercise.fromJson(Map<String, dynamic> j) {
    final completed = j['completedAt'] as String?;
    return StudyExercise(
      day: DateTime.parse(j['day'] as String),
      title: j['title'] as String? ?? '',
      form: j['form'] as String? ?? '',
      premise: j['premise'] as String? ?? '',
      scriptureRef: j['scriptureRef'] as String? ?? '',
      scriptureText: j['scriptureText'] as String? ?? '',
      steps: (j['steps'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
      question: j['question'] as String? ?? '',
      closingPrayer: j['closingPrayer'] as String? ?? '',
      completedAt:
          (completed == null || completed.isEmpty) ? null : DateTime.tryParse(completed),
      notes: j['notes'] as String? ?? '',
      isFallback: j['isFallback'] as bool? ?? false,
    );
  }
}
