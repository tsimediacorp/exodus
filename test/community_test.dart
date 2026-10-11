import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:exodus/config/community_fallback.dart';
import 'package:exodus/config/community_prompt.dart';
import 'package:exodus/models/community_post.dart';
import 'package:exodus/services/community_service.dart';
import 'package:exodus/services/storage_service.dart';

Map<String, dynamic> _post({
  String author = 'Marcus T.',
  String title = 'Our son told us he is done',
  String? body,
  int replies = 2,
}) =>
    {
      'author': author,
      'authorContext': 'married 9 years',
      'tag': 'Rebellion',
      'title': title,
      'body': body ??
          'He said it at dinner, not even angry. Church, God, us, all of it. '
              'I got loud, which helped nothing at all.',
      'replies': [
        for (var i = 0; i < replies; i++)
          {
            'author': i.isEven ? 'Renata O.' : author,
            'body': 'That part about deciding what it means lands hard here.',
            'fromAuthor': i.isOdd,
          },
      ],
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('what counts as a post worth showing', () {
    CommunityPost build(Map<String, dynamic> json) =>
        CommunityPost.fromGenerated(json, id: 'x', createdAt: DateTime.now());

    test('a full thread is usable', () {
      expect(build(_post()).isUsable, isTrue);
    });

    test('a story with no replies is a testimonial, not a community', () {
      expect(build(_post(replies: 0)).isUsable, isFalse);
      expect(build(_post(replies: 1)).isUsable, isFalse);
    });

    test('a one-line body is not a story', () {
      expect(build(_post(body: 'It was hard.')).isUsable, isFalse);
    });

    test('an unnamed author is dropped', () {
      expect(build(_post(author: '')).isUsable, isFalse);
    });

    test('replies land after the post, spread out', () {
      final post = build(_post(replies: 3));
      expect(post.replies.length, 3);
      for (var i = 1; i < post.replies.length; i++) {
        expect(post.replies[i].createdAt.isAfter(post.replies[i - 1].createdAt),
            isTrue,
            reason: 'a thread should read as a conversation over hours');
      }
      expect(post.replies.first.createdAt.isAfter(post.createdAt), isTrue);
    });

    test('the original poster answering is marked', () {
      final post = build(_post(replies: 2));
      expect(post.replies.any((r) => r.fromAuthor), isTrue);
    });
  });

  group('a bad batch does not empty the feed', () {
    // Fetched inside each test: the singleton builds an HTTP client, and
    // constructing one at group-declaration time is outside the test zone.
    CommunityService service() => CommunityService.instance;

    String batch(List<Map<String, dynamic>> posts) =>
        posts.map((p) => _encode(p)).join(',').let((s) => '[$s]');

    test('the good posts survive one malformed neighbour', () {
      final raw = '[${_encode(_post(title: 'One'))},'
          '{"author":"Broken"},'
          '${_encode(_post(title: 'Two', author: 'Dani R.'))}]';
      final posts = service().parseBatch(raw);
      expect(posts.map((p) => p.title), ['One', 'Two']);
    });

    test('a preamble and a markdown fence are tolerated', () {
      final raw = 'Sure! Here are the posts:\n```json\n'
          '${batch([_post()])}\n```';
      expect(service().parseBatch(raw), hasLength(1));
    });

    test('nothing parseable yields nothing, not a crash', () {
      expect(service().parseBatch('I cannot help with that.'), isEmpty);
      expect(service().parseBatch(''), isEmpty);
      expect(service().parseBatch('[{'), isEmpty);
    });

    test('posts come back newest first', () {
      final raw = batch([
        _post(title: 'First'),
        _post(title: 'Second', author: 'Dani R.'),
      ]);
      final posts = service().parseBatch(raw);
      expect(posts.first.createdAt.isAfter(posts.last.createdAt), isTrue);
    });
  });

  group('the feed persists', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await StorageService.instance.init();
    });

    test('a saved post comes back whole', () async {
      final post = CommunityPost.fromGenerated(_post(replies: 3),
          id: 'p1', createdAt: DateTime(2026, 9, 1, 8));
      await StorageService.instance.saveCommunityPosts([post]);

      final back = StorageService.instance.loadCommunityPosts();
      expect(back, hasLength(1));
      expect(back.first.title, post.title);
      expect(back.first.author, post.author);
      expect(back.first.replies, hasLength(3));
      expect(back.first.replies.any((r) => r.fromAuthor), isTrue);
      expect(back.first.composite, isTrue);
    });

    test('corrupt storage reads as empty rather than throwing', () async {
      SharedPreferences.setMockInitialValues(
          {'exodus.community.posts': 'not json'});
      await StorageService.instance.init();
      expect(StorageService.instance.loadCommunityPosts(), isEmpty);
    });

    test('the day stamp starts empty, which means never generated', () {
      expect(StorageService.instance.communityLastDay, '');
    });
  });

  group('nobody types an em dash', () {
    test('a dash becomes the comma a person would have used', () {
      expect(asTyped('It was hard — harder than I expected.'),
          'It was hard, harder than I expected.');
      expect(asTyped('It was hard—harder than I expected.'),
          'It was hard, harder than I expected.');
      expect(asTyped('It was hard -- harder than that.'),
          'It was hard, harder than that.');
      expect(asTyped('Nine years – maybe ten.'), 'Nine years, maybe ten.');
    });

    test('it does not leave doubled or stranded punctuation', () {
      expect(asTyped('I stopped. — Then he called.'),
          'I stopped. Then he called.');
      expect(asTyped('I stopped, — then he called.'),
          'I stopped, then he called.');
      expect(asTyped('— He called.'), 'He called.');
      expect(asTyped('He called —'), 'He called');
      expect(asTyped('one — two — three'), 'one, two, three');
    });

    test('a dash at a paragraph break does not open the next one', () {
      expect(asTyped('First para.\n\n— Second para.'),
          'First para.\n\nSecond para.');
    });

    test('the single-character ellipsis goes too', () {
      expect(asTyped('I do not know…'), 'I do not know...');
    });

    test('ordinary text is left alone', () {
      const plain = 'He said it at dinner, not even angry. All of it.';
      expect(asTyped(plain), plain);
      expect(asTyped('a well-meaning brother-in-law'),
          'a well-meaning brother-in-law');
    });

    test('a generated post is clean in every field a reader sees', () {
      final post = CommunityPost.fromGenerated({
        'author': 'Marcus T.',
        'authorContext': 'married 9 years — nearly ten',
        'tag': 'Rebellion',
        'title': 'He told us — at dinner',
        'body': 'He said it at dinner — not even angry. Church, God, us, all '
            'of it, and I did not have one word ready.',
        'replies': [
          {'author': 'Dani R.', 'body': 'That part — the deciding — lands here.',
            'fromAuthor': false},
          {'author': 'Marcus T.', 'body': 'It is the whole thing — honestly.',
            'fromAuthor': true},
        ],
      }, id: 'x', createdAt: DateTime.now());

      final seen = [
        post.author,
        post.authorContext,
        post.title,
        post.body,
        for (final r in post.replies) ...[r.author, r.body],
      ];
      for (final text in seen) {
        expect(text, isNot(contains('—')), reason: text);
        expect(text, isNot(contains('–')), reason: text);
      }
      expect(post.title, 'He told us, at dinner');
    });

    test('posts written before this existed are cleaned on the way out', () {
      final stored = CommunityPost.fromJson({
        'id': 'old',
        'author': 'Priya N.',
        'authorContext': 'married 6 years',
        'tag': 'Money',
        'title': 'The account — I did not know about',
        'body': 'Not a huge amount — two hundred a month for three years.',
        'createdAt': DateTime(2026, 9, 1).toIso8601String(),
        'replies': [
          {
            'id': 'old-r0',
            'author': 'Aaron K.',
            'body': 'I was the one — with the account.',
            'fromAuthor': false,
            'createdAt': DateTime(2026, 9, 1, 3).toIso8601String(),
          },
        ],
      });
      expect(stored.title, isNot(contains('—')));
      expect(stored.body, isNot(contains('—')));
      expect(stored.replies.first.body, isNot(contains('—')));
    });

    test('the offline stories contain none either', () {
      for (final raw in CommunityFallback.posts) {
        final post = CommunityPost.fromGenerated(
            Map<String, dynamic>.from(raw),
            id: 'f',
            createdAt: DateTime.now());
        for (final text in [
          post.title,
          post.body,
          for (final r in post.replies) r.body,
        ]) {
          expect(text, isNot(contains('—')), reason: text);
        }
      }
    });

    test('the prompt forbids them, and does not model them either', () {
      final task = CommunityPrompt.task(count: 3, dayIndex: 0);
      expect(task, contains('Never use an em dash'));
      // Showing the model em dashes while telling it not to use them is the
      // weakest possible instruction.
      expect(task, isNot(contains('—')));
      expect(task, isNot(contains('–')));
    });
  });

  group('the subjects rotate, or the feed reads as static', () {
    test('consecutive days do not overlap', () {
      for (var day = 0; day < 40; day++) {
        final today = CommunityPrompt.subjectsFor(day, 3).toSet();
        final tomorrow = CommunityPrompt.subjectsFor(day + 1, 3).toSet();
        expect(today.intersection(tomorrow), isEmpty, reason: 'day $day');
      }
    });

    test('a batch has no repeats inside it', () {
      for (var day = 0; day < 40; day++) {
        final batch = CommunityPrompt.subjectsFor(day, 5);
        expect(batch.toSet().length, batch.length, reason: 'day $day');
      }
    });

    test('a week of batches covers real breadth', () {
      final week = <String>{};
      for (var day = 0; day < 7; day++) {
        week.addAll(CommunityPrompt.subjectsFor(day, 3));
      }
      expect(week.length, greaterThanOrEqualTo(20));
    });

    test('the subjects reach the prompt, numbered', () {
      final task = CommunityPrompt.task(count: 3, dayIndex: 5);
      for (final subject in CommunityPrompt.subjectsFor(5, 3)) {
        expect(task, contains(subject));
      }
      expect(task, contains('1. '));
      expect(task, contains('THE GROUND FOR THIS BATCH'));
    });

    test('the worked example that got copied verbatim is gone', () {
      // Every generation returned a variant of the hidden-account story
      // because the prompt handed it one to copy.
      final task = CommunityPrompt.task(count: 3, dayIndex: 0);
      expect(task, isNot(contains('200 dollars a month')));
      expect(task, contains('Do not reuse an example'));
    });

    test('asking for more than exists does not crash or repeat', () {
      final huge = CommunityPrompt.subjectsFor(3, 500);
      expect(huge.length, CommunityPrompt.subjects.length);
      expect(huge.toSet().length, huge.length);
    });

    test('zero and negative counts are empty, not an error', () {
      expect(CommunityPrompt.subjectsFor(1, 0), isEmpty);
      expect(CommunityPrompt.subjectsFor(1, -3), isEmpty);
    });
  });

  group('a curated story is the panel\'s, not the device\'s', () {
    test('curated is decided by the id the panel assigns', () {
      final curated = CommunityPost.fromGenerated(_post(),
          id: 'curated-abc', createdAt: DateTime.now());
      final generated = CommunityPost.fromGenerated(_post(),
          id: 'k3f9-0', createdAt: DateTime.now());
      expect(curated.curated, isTrue);
      expect(generated.curated, isFalse);
    });

    test('curated survives a storage round trip', () async {
      SharedPreferences.setMockInitialValues({});
      await StorageService.instance.init();
      final post = CommunityPost.fromGenerated(_post(),
          id: 'curated-xyz', createdAt: DateTime(2026, 9, 8));
      await StorageService.instance.saveCommunityPosts([post]);
      expect(StorageService.instance.loadCommunityPosts().first.curated, isTrue);
    });
  });

  group('what the posts must never be', () {
    test('every post records that EXODUS wrote it, for the launch cleanup', () {
      final post = CommunityPost.fromGenerated(_post(),
          id: 'x', createdAt: DateTime.now());
      expect(post.composite, isTrue);
    });

    test('every fallback post is a usable thread', () {
      for (final raw in CommunityFallback.posts) {
        final post = CommunityPost.fromGenerated(
            Map<String, dynamic>.from(raw),
            id: 'f',
            createdAt: DateTime.now());
        expect(post.isUsable, isTrue, reason: '${post.title} is not showable');
      }
    });

    test('the prompt forbids the single-prayer fix and demands outside help',
        () {
      final task = CommunityPrompt.task(count: 3, dayIndex: 0);
      expect(task, contains('single prayer'));
      expect(task.toLowerCase(), contains('counsellor'));
      expect(task, contains('fromAuthor'));
    });

    test('what the couple told EXODUS never reaches the story prompt', () {
      const memory = 'They argue about her mother Carol moving in. '
          'He hid 4,200 dollars of debt on the Visa.';
      final task = CommunityPrompt.task(
          count: 5, dayIndex: 0, themes: CommunityPrompt.themesIn(memory));
      for (final detail in ['Carol', '4,200', 'Visa', 'moving in']) {
        expect(task, isNot(contains(detail)), reason: detail);
      }
      expect(task, contains('You know nothing about who will read these'));
    });

    test('memory is reduced to broad subjects, most-mentioned first', () {
      final themes = CommunityPrompt.themesIn(
          'They fight about money. The debt is his. Money again last week. '
          'Her mother keeps calling.');
      expect(themes.first, 0, reason: 'money is mentioned most');
      expect(themes, contains(1));
      expect(CommunityPrompt.themesIn(''), isEmpty);
      expect(CommunityPrompt.themesIn('They like hiking.'), isEmpty);
    });

    test('most of a batch is other people\'s ground', () {
      const themes = [0, 1, 9]; // money, in-laws, anger
      final own = {for (final t in themes) CommunityPrompt.subjects[t]};
      for (var day = 0; day < 60; day++) {
        final three = CommunityPrompt.groundFor(
            dayIndex: day, count: 3, themes: themes);
        expect(three, hasLength(3));
        expect(three.toSet(), hasLength(3));
        expect(three.where(own.contains).length, lessThanOrEqualTo(1),
            reason: 'day $day');

        final five = CommunityPrompt.groundFor(
            dayIndex: day, count: 5, themes: themes);
        expect(five.where(own.contains).length, lessThanOrEqualTo(2),
            reason: 'day $day');
      }
    });

    test('one worry does not come round every day', () {
      final money = CommunityPrompt.subjects[0];
      var days = 0;
      for (var day = 0; day < 30; day++) {
        final batch = CommunityPrompt.groundFor(
            dayIndex: day, count: 3, themes: const [0]);
        if (batch.contains(money)) days++;
      }
      expect(days, 10, reason: 'one day in three');
    });

    test('the near story is not always the first one', () {
      const themes = [0, 1, 9];
      final own = {for (final t in themes) CommunityPrompt.subjects[t]};
      final positions = <int>{};
      for (var day = 0; day < 30; day++) {
        final batch = CommunityPrompt.groundFor(
            dayIndex: day, count: 3, themes: themes);
        final at = batch.indexWhere(own.contains);
        if (at >= 0) positions.add(at);
      }
      expect(positions, hasLength(3));
    });

    test('with nothing known the batch is the plain rotation', () {
      for (var day = 0; day < 10; day++) {
        expect(CommunityPrompt.groundFor(dayIndex: day, count: 3),
            CommunityPrompt.subjectsFor(day, 3));
      }
    });
  });
}

String _encode(Map<String, dynamic> p) {
  final replies = (p['replies'] as List)
      .map((r) => '{"author":"${r['author']}","body":"${r['body']}",'
          '"fromAuthor":${r['fromAuthor']}}')
      .join(',');
  return '{"author":"${p['author']}","authorContext":"${p['authorContext']}",'
      '"tag":"${p['tag']}","title":"${p['title']}",'
      '"body":"${(p['body'] as String).replaceAll('\n', ' ')}",'
      '"replies":[$replies]}';
}

extension<T> on T {
  R let<R>(R Function(T) f) => f(this);
}
