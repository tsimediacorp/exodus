/// Built-in devotionals used when the model is unreachable or returns nothing
/// usable. Guarantees the Devotional tab — and the morning notification —
/// ALWAYS have a real, complete devotional, even fully offline.
///
/// Picked by day so the fallback also rotates rather than repeating one verse.
class DevotionalFallback {
  static const List<Map<String, String>> _bank = [
    {
      'title': 'One Flesh',
      'scriptureRef': 'Genesis 2:24',
      'scriptureText':
          'Therefore a man shall leave his father and his mother and hold fast to his wife, and they shall become one flesh.',
      'reflection':
          'Marriage is God\'s first institution — a leaving and a holding fast. Today, consider one way you can "hold fast" to each other above every other relationship and demand on your time.',
      'prayer':
          'Father, knit our hearts together as one. Help us put each other first under You. Amen.',
      'action':
          'Name one thing competing for your attention this week, and decide together how to guard your marriage from it.',
    },
    {
      'title': 'Love That Lays Down',
      'scriptureRef': 'Ephesians 5:25',
      'scriptureText':
          'Husbands, love your wives, as Christ loved the church and gave himself up for her.',
      'reflection':
          'Christ\'s love is sacrificial, not convenient. The measure isn\'t how you feel today but what you\'re willing to lay down for each other.',
      'prayer':
          'Lord, teach us a love that gives itself away, as You gave Yourself for us. Amen.',
      'action': 'Do one small, unasked-for act of service for your spouse today.',
    },
    {
      'title': 'Quick to Listen',
      'scriptureRef': 'James 1:19',
      'scriptureText':
          'Let every person be quick to hear, slow to speak, slow to anger.',
      'reflection':
          'Most conflict grows where listening shrinks. Being "quick to hear" is a gift you give your spouse before you ever give an answer.',
      'prayer':
          'God, make us slow enough to truly hear each other before we respond. Amen.',
      'action':
          'Ask your spouse, "What\'s something you wish I understood better?" — then just listen.',
    },
    {
      'title': 'Bearing With Each Other',
      'scriptureRef': 'Colossians 3:13',
      'scriptureText':
          'Bearing with one another and, if one has a complaint against another, forgiving each other; as the Lord has forgiven you, so you also must forgive.',
      'reflection':
          'Forgiveness is the daily oxygen of a marriage. Holding an account of wrongs slowly suffocates love; releasing it lets you breathe again.',
      'prayer':
          'Lord, help us forgive freely, as You have forgiven us completely. Amen.',
      'action':
          'Release one small grievance you\'ve been quietly keeping, and tell your spouse it\'s forgiven.',
    },
    {
      'title': 'A Cord of Three Strands',
      'scriptureRef': 'Ecclesiastes 4:12',
      'scriptureText':
          'And though a man might prevail against one who is alone, two will withstand him — a threefold cord is not quickly broken.',
      'reflection':
          'The strength of your marriage isn\'t just the two of you, but the third strand: God woven through it. Invite Him into the ordinary.',
      'prayer':
          'Father, be the third strand in our marriage — our strength when we are weak. Amen.',
      'action': 'Pray together out loud tonight, even if it\'s only a sentence each.',
    },
    {
      'title': 'Rejoice Together',
      'scriptureRef': 'Proverbs 5:18',
      'scriptureText':
          'Let your fountain be blessed, and rejoice in the wife of your youth.',
      'reflection':
          'Delight is a discipline. Scripture calls you to actively rejoice in each other — not someday, but in the season you\'re in right now.',
      'prayer':
          'Lord, renew our delight in one another and guard our hearts for each other alone. Amen.',
      'action': 'Tell your spouse one specific thing you delight in about them today.',
    },
    {
      'title': 'Pray Without Ceasing',
      'scriptureRef': '1 Thessalonians 5:16-18',
      'scriptureText':
          'Rejoice always, pray without ceasing, give thanks in all circumstances; for this is the will of God in Christ Jesus for you.',
      'reflection':
          'A praying couple is a peaceful couple. Bringing the small things to God together keeps the big things from dividing you.',
      'prayer':
          'Father, make prayer the rhythm of our home, in joy and in trial alike. Amen.',
      'action':
          'Share one thing you each want to thank God for, and one thing you want to ask Him for.',
    },
  ];

  /// A complete fallback devotional, rotated by [day] so it varies.
  static Map<String, String> forDay(DateTime day) {
    final index = (day.difference(DateTime(day.year)).inDays) % _bank.length;
    return _bank[index];
  }
}
