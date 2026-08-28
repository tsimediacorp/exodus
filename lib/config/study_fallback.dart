/// Built-in study exercises used when the model is unreachable or returns
/// nothing usable. Guarantees the Bible Study tab ALWAYS has a real, complete
/// exercise, even fully offline.
///
/// Picked by day so the fallback rotates rather than repeating one practice.
class StudyFallback {
  static const List<Map<String, Object>> _bank = [
    {
      'title': 'Take the Enemy to Court',
      'form': 'courtroom',
      'premise':
          'The accuser deals in accusations that feel like verdicts. This puts '
              'them where they belong — on trial, before a judge who has already ruled.',
      'scriptureRef': 'Revelation 12:10-11',
      'scriptureText':
          'For the accuser of our brethren is cast down, which accused them before our God day and night. And they overcame him by the blood of the Lamb, and by the word of their testimony.',
      'steps': [
        'Take a sheet of paper and draw a line down the middle. Head the left column ACCUSATION and the right column EVIDENCE.',
        'In the left column, write down — in the exact words you hear them — the three things you have been told about yourself this week. Not what you believe about God. What you believe about you at your lowest.',
        'Read them aloud to each other. Do not soften them and do not argue with them yet.',
        'Now open Scripture and, for each accusation, write in the right column what God has said instead. Cite the reference. An unsourced encouragement is not evidence.',
        'Read the right column aloud over each other, by name. "You are not…", "You are…"',
        'Tear the left column off and destroy it. The record has been answered; it does not need keeping.',
      ],
      'question':
          'Which accusation did you find you had no verse for — and is that because Scripture is silent, or because you have never gone looking?',
      'closingPrayer':
          'Father, You are judge, and You have already ruled. Silence the voice that keeps re-trying a case You closed at the cross. Teach us to answer lies with Your word rather than with our own strength. Amen.',
    },
    {
      'title': 'The Third Reading',
      'form': 'copy by hand',
      'premise':
          'Familiar passages stop being read and start being recognised. Writing '
              'one out by hand slows you down enough to actually see it again.',
      'scriptureRef': '1 Corinthians 13:4-7',
      'scriptureText':
          'Charity suffereth long, and is kind; charity envieth not; charity vaunteth not itself, is not puffed up, doth not behave itself unseemly, seeketh not her own, is not easily provoked, thinketh no evil.',
      'steps': [
        'Each take a sheet of paper and copy the passage out longhand. No phones. Write slowly enough that your hand aches a little.',
        'Read what you wrote out loud, once, to yourself.',
        'Read it a second time, and underline every phrase that is a NEGATIVE — something love does not do.',
        'Read it a third time, and circle the one underlined phrase that describes you this month.',
        'Swap papers. Read your spouse\'s circled phrase without commenting on it.',
      ],
      'question':
          'You circled something love does not do. What would it cost you, concretely, to stop doing it this week?',
      'closingPrayer':
          'Lord, we have heard these words at weddings until we stopped hearing them at all. Make them heavy again. Amen.',
    },
    {
      'title': 'Write Your Own Lament',
      'form': 'lament',
      'premise':
          'A third of the psalms are complaints. Scripture gives grief a form to '
              'take, so it does not have to be either swallowed or spilled.',
      'scriptureRef': 'Psalm 13',
      'scriptureText':
          'How long wilt thou forget me, O LORD? for ever? how long wilt thou hide thy face from me? ... But I have trusted in thy mercy; my heart shall rejoice in thy salvation.',
      'steps': [
        'Read Psalm 13 aloud. It is six verses; it takes thirty seconds.',
        'Notice its shape: it addresses God, it complains, it asks for something specific, and it ends by remembering. Four movements.',
        'Each write your own, in those four movements, about something that is actually wrong right now. Six lines is enough.',
        'Do not skip the complaint to get to the ending. The psalmist did not.',
        'Read them to each other. No fixing, no advice, no "but at least".',
      ],
      'question':
          'Was the last movement — remembering — hard to write honestly? What does that tell you about where you are?',
      'closingPrayer':
          'God, You did not ask us to pretend. Thank You that the book You gave us has room for how long, and why, and still. Amen.',
    },
    {
      'title': 'What It Would Cost',
      'form': 'obedience audit',
      'premise':
          'Agreement is cheap. This works out the price of one command in the '
              'currency of your actual week.',
      'scriptureRef': 'Ephesians 4:26-27',
      'scriptureText':
          'Be ye angry, and sin not: let not the sun go down upon your wrath: neither give place to the devil.',
      'steps': [
        'Read the command. Note that it is not "do not be angry" — it is about the clock.',
        'Between you, list the last three disagreements that went unresolved overnight.',
        'For each one, write down what obeying this verse would have required: what time you would have had to stop, what you would have had to say, what you would have had to give up being right about.',
        'Add up the cost honestly. Some of it is sleep. Some of it is pride.',
        'Agree one rule you will actually keep this week — and name who is allowed to call it.',
      ],
      'question':
          'Which was harder to write down: the time, or the pride?',
      'closingPrayer':
          'Father, we would rather agree with Your word than obey it. Give us the courage to pay what obedience costs tonight rather than tomorrow. Amen.',
    },
    {
      'title': 'Follow the Word Home',
      'form': 'word study',
      'premise':
          'One word, carried through several passages, teaches more than one '
              'passage read several times.',
      'scriptureRef': 'Ruth 2:12',
      'scriptureText':
          'The LORD recompense thy work, and a full reward be given thee of the LORD God of Israel, under whose wings thou art come to trust.',
      'steps': [
        'Write down the phrase "under whose wings".',
        'Find it, or its close relatives, in Psalm 91:4, Psalm 17:8, and Matthew 23:37. Use the in-app Bible.',
        'For each one, write in a single line WHO is sheltering and WHO is being sheltered.',
        'Notice the last one. It is the same image, and something has gone wrong in it. Write down what.',
        'Say out loud which of the four you are living in this month.',
      ],
      'question':
          'In Matthew the sheltering was refused. What does it look like, practically, to refuse shelter you have been offered?',
      'closingPrayer':
          'Lord, You have gathered us before we thought to come. Keep us from being the ones who would not. Amen.',
    },
    {
      'title': 'Pray It Over Them',
      'form': 'intercession',
      'premise':
          'Praying for your spouse in private is good. Praying Scripture over '
              'them, out loud, in front of them, is a different thing entirely.',
      'scriptureRef': 'Colossians 1:9-11',
      'scriptureText':
          'That ye might be filled with the knowledge of his will in all wisdom and spiritual understanding; that ye might walk worthy of the Lord unto all pleasing, being fruitful in every good work.',
      'steps': [
        'Read the passage once, silently, each on your own.',
        'Break it into phrases. There are roughly five.',
        'Sit facing each other. One of you prays the first phrase over the other, by name, out loud — not "help them" but "fill you".',
        'Swap. Same phrase, other direction.',
        'Work through all five phrases, alternating. Do not add your own material.',
        'Sit in the silence afterwards for a full minute before either of you speaks.',
      ],
      'question':
          'Which phrase was hardest to say out loud to their face — and why that one?',
      'closingPrayer':
          'Father, we have prayed about each other for years and over each other rarely. Teach us to speak Your words toward the person in the room. Amen.',
    },
    {
      'title': 'The Moment It Turned',
      'form': 'timeline',
      'premise':
          'Disasters in Scripture rarely begin where they become visible. Mapping '
              'the sequence shows you where the decision actually got made.',
      'scriptureRef': '2 Samuel 11:1-5',
      'scriptureText':
          'And it came to pass, after the year was expired, at the time when kings go forth to battle, that David sent Joab ... But David tarried still at Jerusalem.',
      'steps': [
        'Read the passage. Write down every event, in order, as a short line — one line per event.',
        'You should have somewhere between six and ten lines.',
        'Now go back to the top and mark the FIRST line at which the outcome became likely. Not the sinful act — the moment before it.',
        'Notice how early it is, and how ordinary.',
        'Each name one "tarried still at Jerusalem" in your own life right now — a good thing you are not doing, that nobody would call a sin.',
      ],
      'question':
          'What would have had to happen at your marked line for the story to end differently?',
      'closingPrayer':
          'Lord, keep us from the ordinary decisions that make the terrible ones easy. Send us out where we are supposed to be. Amen.',
    },
  ];

  /// A complete exercise for [day], rotating through the bank by date.
  static Map<String, Object> forDay(DateTime day) {
    final ordinal =
        DateTime(day.year, day.month, day.day).difference(DateTime(2000)).inDays;
    return _bank[ordinal.abs() % _bank.length];
  }

  static int get count => _bank.length;
}
