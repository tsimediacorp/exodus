/// Posts shown when the model cannot be reached.
///
/// The feed sits above the verse on the home screen, so an empty state is a
/// hole in the first thing the couple sees. These are deliberately general —
/// they are not tailored to anyone — and they follow the same rules as
/// generated posts: one is still unresolved, nobody is a professional, and
/// nothing is fixed by a single prayer.
class CommunityFallback {
  CommunityFallback._();

  static const List<Map<String, dynamic>> posts = [
    {
      'author': 'Marcus T.',
      'authorContext': 'married 11 years',
      'tag': 'Rebellion',
      'title': 'Our sixteen year old told us he is done with all of it',
      'body': '''
He said it at dinner, not even angry. Church, God, us, all of it. Said he had
been pretending for about two years and was tired.

My wife cried. I got loud, which helped nothing. What I actually felt under
the loud part was that we had failed at the one thing we thought we were doing
right.

He is seventeen now. Still does not come with us. But he came to me in March
about something he had gotten himself into and he told me the truth about it,
all of it, which he would not have done at fifteen. I do not know what that
means yet. I am trying to stop deciding what it means.''',
      'replies': [
        {
          'author': 'Renata O.',
          'body':
              'The deciding what it means part. I do that constantly. Every '
                  'small thing our daughter does gets read as either she is '
                  'coming back or she is gone forever and both readings are me '
                  'making it about me.',
          'fromAuthor': false,
        },
        {
          'author': 'Marcus T.',
          'body':
              'That is exactly it. Somebody told me my job right now is to be '
                  'somewhere he can come back to, not to get him back. I hate '
                  'how much slower that is.',
          'fromAuthor': true,
        },
        {
          'author': 'Dev P.',
          'body':
              'Mine is 24 and came back around on his own timeline, nothing to '
                  'do with anything we did. I wish I could give you the years '
                  'in between without the waiting but the waiting was the whole '
                  'thing.',
          'fromAuthor': false,
        },
      ],
    },
    {
      'author': 'Priya N.',
      'authorContext': 'married 6 years',
      'tag': 'Money',
      'title': 'The account I did not know about',
      'body': '''
Not a huge amount. Two hundred a month for about three years, into an account
in his name. He was not spending it on anything. That is the part I could not
get past for a long time — there was no woman, no gambling, nothing to point
at. He just wanted something that was his.

We are still in it, honestly. Six months of counselling and I still check
things I should not check.

I am posting because every version of this I found online ended with the
couple stronger than ever and I needed to read one that did not.''',
      'replies': [
        {
          'author': 'Aaron K.',
          'body':
              'I was the one who had the account. Took me a year of therapy to '
                  'say out loud that it was not about money, it was about not '
                  'having anywhere in my own life that was only mine. Which is '
                  'a me problem I made into an us problem.',
          'fromAuthor': false,
        },
        {
          'author': 'Priya N.',
          'body':
              'He said almost that word for word last month and I did not '
                  'believe him. Reading it from a stranger somehow lands '
                  'different. Thank you for that.',
          'fromAuthor': true,
        },
      ],
    },
    {
      'author': 'Tomas R.',
      'authorContext': 'married 23 years',
      'tag': 'Distance',
      'title': 'We were fine for nine years and I do not think either of us was there',
      'body': '''
No fighting. That is what I want people to hear. There was no fight to point
at. We ran a house, we raised three kids, we were polite. I could not have
told you one thing she was afraid of.

What broke it open was my father dying and me realising I was going to grieve
that alone in a house with another person in it.

It took about two years to get back and we needed help to do it. The thing
nobody told me is that the quiet kind is harder to notice and easier to lose,
because nothing looks wrong from outside and you get told constantly how
lucky you are.''',
      'replies': [
        {
          'author': 'Michelle A.',
          'body': 'Polite. That word just did something to me. We are polite.',
          'fromAuthor': false,
        },
        {
          'author': 'Tomas R.',
          'body':
              'If it helps at all, polite is not nothing to build on. We were '
                  'not cruel to each other for nine years, which meant there '
                  'was not much rubble to clear. Just a lot of ground to cover.',
          'fromAuthor': true,
        },
        {
          'author': 'Gareth L.',
          'body':
              'Two years is what it took us as well. Everyone acts like it '
                  'should be a weekend away.',
          'fromAuthor': false,
        },
      ],
    },
    {
      'author': 'Yolanda B.',
      'authorContext': 'married 4 years',
      'tag': 'Anger',
      'title': 'I am the one with the temper and I am tired of being the problem',
      'body': '''
He is patient. Everyone says so, including me, including his mother. Which
means every single time we get into it, I am the villain of the story before
we start.

Some of that is fair. I say things I cannot take back and I say them fast.

But I have started noticing that patient can also be a way of leaving the
room without leaving the room, and that I get loudest when I can feel him
going somewhere I cannot follow. I do not know what to do with that yet. I
brought it up once and it came out as an accusation, which proved his point.''',
      'replies': [
        {
          'author': 'Solomon W.',
          'body':
              'I am the patient one in mine. That last paragraph is more or '
                  'less what my wife has been trying to tell me for six years '
                  'and I heard it as her excusing the shouting every time.',
          'fromAuthor': false,
        },
        {
          'author': 'Yolanda B.',
          'body':
              'Did you ever hear it as something other than an excuse? '
                  'Genuinely asking, because I do not know how to say it in a '
                  'way that is not one.',
          'fromAuthor': true,
        },
        {
          'author': 'Solomon W.',
          'body':
              'Only when a counsellor said it instead of her, which is not the '
                  'answer you wanted. But we needed a third person in the room '
                  'for either of us to hear the other at all. That is not a '
                  'failure, it is just what it cost.',
          'fromAuthor': false,
        },
      ],
    },
  ];
}
