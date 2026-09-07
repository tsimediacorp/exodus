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

  group('the disclosure', () {
    test('every generated post is marked composite', () {
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

    test('the notice says who wrote them', () {
      expect(CommunityPrompt.compositeNotice.toLowerCase(),
          contains('exodus'));
      expect(CommunityPrompt.compositeNotice, isNotEmpty);
    });

    test('the prompt forbids the single-prayer fix and demands outside help',
        () {
      final task = CommunityPrompt.task(memoryBlock: '', count: 3);
      expect(task, contains('single prayer'));
      expect(task.toLowerCase(), contains('counsellor'));
      expect(task, contains('fromAuthor'));
    });

    test('the prompt carries the couple\'s own struggles when there are any',
        () {
      final task = CommunityPrompt.task(
          memoryBlock: 'They argue about her mother.', count: 3);
      expect(task, contains('They argue about her mother.'));
      expect(task, contains('RHYME'));
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
