/// Daily couples question, chosen deterministically by date so both partners
/// always get the same prompt without needing the server to assign one.
class QuizBank {
  static const List<String> _questions = [
    'What is one thing your spouse did this week that made you feel loved?',
    'If we could pray for one specific thing over our marriage this month, what would it be?',
    'What is a small habit of mine that blesses you — or that you wish I would change?',
    "What's one dream for our future you've been thinking about lately?",
    'When do you feel most connected to me?',
    'What is one way we could invite God more into our daily routine?',
    'What is something you need more of from me right now: words, time, touch, help, or gifts?',
    'What is a fear about our marriage you rarely say out loud?',
    'What is your favorite memory of us, and why?',
    'Where do you feel we are most aligned right now?',
    'What is one area where we tend to clash, and how could we handle it better?',
    'How can I pray for you specifically this week?',
    'What does feeling respected look like to you?',
    "What's one thing we could do to make our home more peaceful?",
  ];

  /// The question for [day], rotating through the bank by day of the year.
  static String forDay(DateTime day) {
    final dayOfYear = day.difference(DateTime(day.year)).inDays;
    return _questions[dayOfYear % _questions.length];
  }
}
