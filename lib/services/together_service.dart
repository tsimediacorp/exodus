import 'dart:convert';
import 'dart:math';
import 'package:amplify_flutter/amplify_flutter.dart';

/// A message in the couples space (mirrors the backend Message model).
class TogetherMessage {
  final String id;
  final String authorId;
  final String role; // 'user' | 'exodus'
  final String text;
  final String visibility; // 'private' | 'shared'
  final DateTime createdAt;

  TogetherMessage({
    required this.id,
    required this.authorId,
    required this.role,
    required this.text,
    required this.visibility,
    required this.createdAt,
  });

  bool get isExodus => role == 'exodus';

  factory TogetherMessage.fromJson(Map<String, dynamic> j) => TogetherMessage(
        id: j['id'] as String,
        authorId: (j['authorId'] ?? '') as String,
        role: (j['role'] ?? 'user').toString().toLowerCase(),
        text: (j['text'] ?? '') as String,
        visibility: (j['visibility'] ?? 'shared').toString().toLowerCase(),
        createdAt: DateTime.tryParse((j['createdAt'] ?? '') as String) ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );
}

class Couple {
  final String id;
  final String member1Id;
  final String? member2Id;
  final String? inviteCode;
  Couple({required this.id, required this.member1Id, this.member2Id, this.inviteCode});
  bool get isPaired => member2Id != null && member2Id!.isNotEmpty;

  factory Couple.fromJson(Map<String, dynamic> j) => Couple(
        id: j['id'] as String,
        member1Id: (j['member1Id'] ?? '') as String,
        member2Id: j['member2Id'] as String?,
        inviteCode: j['inviteCode'] as String?,
      );
}

/// All Couples-in-Sync data access: auth + GraphQL against the Amplify backend.
class TogetherService {
  // ---------------- Auth ----------------

  Future<bool> isSignedIn() async {
    try {
      return (await Amplify.Auth.fetchAuthSession()).isSignedIn;
    } on Exception {
      return false;
    }
  }

  Future<String?> currentUserId() async {
    try {
      return (await Amplify.Auth.getCurrentUser()).userId;
    } on Exception {
      return null;
    }
  }

  Future<SignUpResult> signUp(String email, String password) =>
      Amplify.Auth.signUp(
        username: email,
        password: password,
        options: SignUpOptions(userAttributes: {AuthUserAttributeKey.email: email}),
      );

  Future<SignUpResult> confirm(String email, String code) =>
      Amplify.Auth.confirmSignUp(username: email, confirmationCode: code);

  Future<SignInResult> signIn(String email, String password) =>
      Amplify.Auth.signIn(username: email, password: password);

  Future<void> signOut() => Amplify.Auth.signOut();

  // ---------------- GraphQL helpers ----------------

  Future<Map<String, dynamic>> _gql(String document,
      {Map<String, dynamic> variables = const {}}) async {
    final res = await Amplify.API
        .query(request: GraphQLRequest<String>(document: document, variables: variables))
        .response;
    if (res.errors.isNotEmpty) {
      throw Exception(res.errors.map((e) => e.message).join('; '));
    }
    return jsonDecode(res.data ?? '{}') as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _mutate(String document,
      {Map<String, dynamic> variables = const {}}) async {
    final res = await Amplify.API
        .mutate(request: GraphQLRequest<String>(document: document, variables: variables))
        .response;
    if (res.errors.isNotEmpty) {
      throw Exception(res.errors.map((e) => e.message).join('; '));
    }
    return jsonDecode(res.data ?? '{}') as Map<String, dynamic>;
  }

  // ---------------- Couple / pairing ----------------

  static const _coupleFields = 'id member1Id member2Id inviteCode members';

  Future<Couple?> myCouple(String userId) async {
    final data = await _gql('''
      query My(\$uid: String!) {
        listCouples(filter: {members: {contains: \$uid}}, limit: 1) {
          items { $_coupleFields }
        }
      }
    ''', variables: {'uid': userId});
    final items = (data['listCouples']?['items'] as List?) ?? [];
    return items.isEmpty ? null : Couple.fromJson(items.first as Map<String, dynamic>);
  }

  String _newInviteCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random.secure();
    return List.generate(6, (_) => chars[r.nextInt(chars.length)]).join();
  }

  Future<Couple> createCouple(String userId) async {
    final code = _newInviteCode();
    final data = await _mutate('''
      mutation Create(\$m1: String!, \$members: [String]!, \$code: String!) {
        createCouple(input: {member1Id: \$m1, members: \$members, inviteCode: \$code}) {
          $_coupleFields
        }
      }
    ''', variables: {'m1': userId, 'members': [userId], 'code': code});
    return Couple.fromJson(data['createCouple'] as Map<String, dynamic>);
  }

  /// Returns the coupleId joined, or null if the code was invalid.
  Future<String?> redeemInvite(String code) async {
    final data = await _mutate('''
      mutation Redeem(\$code: String!) { redeemInvite(inviteCode: \$code) }
    ''', variables: {'code': code.trim().toUpperCase()});
    final id = data['redeemInvite'] as String?;
    return (id == null || id.isEmpty) ? null : id;
  }

  // ---------------- Messages ----------------

  Future<List<TogetherMessage>> listMessages(String coupleId) async {
    final data = await _gql('''
      query Msgs(\$cid: ID!) {
        listMessages(filter: {coupleId: {eq: \$cid}}, limit: 300) {
          items { id authorId role text visibility createdAt }
        }
      }
    ''', variables: {'cid': coupleId});
    final items = (data['listMessages']?['items'] as List?) ?? [];
    final msgs = items
        .map((e) => TogetherMessage.fromJson(e as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return msgs;
  }

  /// Send a message and get EXODUS's reply. The server persists both messages
  /// (the partner's and EXODUS's) with the correct confidentiality audience.
  Future<String> ask({
    required String coupleId,
    required String text,
    required bool shared,
  }) async {
    final data = await _mutate('''
      mutation Ask(\$cid: String!, \$text: String!, \$vis: String!) {
        askExodus(coupleId: \$cid, text: \$text, visibility: \$vis)
      }
    ''', variables: {'cid': coupleId, 'text': text, 'vis': shared ? 'shared' : 'private'});
    return (data['askExodus'] as String?) ?? '';
  }
}
