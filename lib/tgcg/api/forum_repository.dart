import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../domain/models.dart';
import 'access_repository.dart';
import 'api_client.dart';
import 'auth_repository.dart';

DateTime? _date(Object? value) => value == null ? null : DateTime.tryParse('$value')?.toLocal();

enum ForumMediaKind { photo, video }

/// A picture or video in a post, downloaded with the session's token.
class ForumAttachment {
  const ForumAttachment({
    required this.id,
    required this.kind,
    required this.mimeType,
    required this.size,
  });

  final String id;
  final ForumMediaKind kind;
  final String mimeType;
  final int size;

  factory ForumAttachment.fromJson(Map<String, dynamic> json) => ForumAttachment(
    id: json['id'] as String,
    kind: json['kind'] == 'video' ? ForumMediaKind.video : ForumMediaKind.photo,
    mimeType: json['mime_type'] as String? ?? '',
    size: json['size'] as int? ?? 0,
  );
}

/// published, pending (waiting for the ward coordinator), rejected, hidden
/// or deleted.
class ForumPost {
  const ForumPost({
    required this.id,
    required this.authorName,
    required this.authorRole,
    required this.scope,
    required this.body,
    required this.assignment,
    required this.status,
    required this.createdAt,
    this.publishedAt,
    this.reviewReason = '',
    this.attachments = const [],
    this.replies = 0,
    this.isMine = false,
    this.canModerate = false,
  });

  final String id;
  final String authorName;
  final String authorRole;
  final GeographicScope scope;
  final String body;

  /// The assignment the post shows, or empty.
  final String assignment;
  final String status;
  final DateTime createdAt;
  final DateTime? publishedAt;

  /// Why it was not approved or was hidden: only for its author and moderators.
  final String reviewReason;
  final List<ForumAttachment> attachments;
  final int replies;
  final bool isMine;

  /// May approve, refuse or hide it.
  final bool canModerate;

  bool get isPublished => status == 'published';
  bool get isPending => status == 'pending';

  factory ForumPost.fromJson(Map<String, dynamic> json) => ForumPost(
    id: json['id'] as String,
    authorName: json['author_name'] as String? ?? '',
    authorRole: json['author_role'] as String? ?? '',
    scope: json['scope'] is Map<String, dynamic>
        ? geographicScopeFromJson(json['scope'] as Map<String, dynamic>)
        : GeographicScope.nigeria,
    body: json['body'] as String? ?? '',
    assignment: json['assignment'] as String? ?? '',
    status: json['status'] as String? ?? 'published',
    createdAt: _date(json['created_at']) ?? DateTime.now(),
    publishedAt: _date(json['published_at']),
    reviewReason: json['review_reason'] as String? ?? '',
    attachments: [
      for (final item in json['attachments'] as List<dynamic>? ?? const [])
        ForumAttachment.fromJson(item as Map<String, dynamic>),
    ],
    replies: json['replies'] as int? ?? 0,
    isMine: json['is_mine'] as bool? ?? false,
    canModerate: json['can_moderate'] as bool? ?? false,
  );
}

class ForumReply {
  const ForumReply({
    required this.id,
    required this.authorName,
    required this.authorRole,
    required this.body,
    required this.status,
    required this.createdAt,
    this.hideReason = '',
    this.isMine = false,
  });

  final String id;
  final String authorName;
  final String authorRole;
  final String body;

  /// visible or hidden (hidden ones reach only their author and moderators).
  final String status;
  final DateTime createdAt;
  final String hideReason;
  final bool isMine;

  bool get isHidden => status == 'hidden';

  factory ForumReply.fromJson(Map<String, dynamic> json) => ForumReply(
    id: json['id'] as String,
    authorName: json['author_name'] as String? ?? '',
    authorRole: json['author_role'] as String? ?? '',
    body: json['body'] as String? ?? '',
    status: json['status'] as String? ?? 'visible',
    createdAt: _date(json['created_at']) ?? DateTime.now(),
    hideReason: json['hide_reason'] as String? ?? '',
    isMine: json['is_mine'] as bool? ?? false,
  );
}

class ForumSettings {
  const ForumSettings({required this.approvalRequired, required this.canChange});

  /// Posts from polling units wait for the ward coordinator.
  final bool approvalRequired;

  /// Only a National Administrator changes it.
  final bool canChange;

  factory ForumSettings.fromJson(Map<String, dynamic> json) => ForumSettings(
    approvalRequired: json['approval_required'] as bool? ?? true,
    canChange: json['can_change'] as bool? ?? false,
  );
}

class AssignmentTag {
  const AssignmentTag({required this.tag, required this.posts});

  final String tag;
  final int posts;
}

/// A picture or video chosen on this device for a new post.
class ForumUpload {
  const ForumUpload({
    required this.kind,
    required this.fileName,
    required this.mimeType,
    required this.bytes,
  });

  final ForumMediaKind kind;
  final String fileName;
  final String mimeType;
  final Uint8List bytes;
}

/// Which posts to list.
enum ForumShow { feed, mine, review }

/// The discussion forum (`/forum/`). The server decides who sees, posts,
/// approves and hides.
class ForumRepository {
  ForumRepository(this.client);

  final ApiClient client;

  Future<ApiPage<ForumPost>> posts({
    ForumShow show = ForumShow.feed,
    String? assignment,
    bool assignmentsOnly = false,
    int offset = 0,
  }) async => ApiPage.fromJson(
    await client.get(
      'forum/posts/',
      query: {
        if (show != ForumShow.feed) 'show': show.name,
        if (assignment != null) 'assignment': assignment,
        if (assignment == null && assignmentsOnly) 'assignments': 'true',
        if (offset > 0) 'offset': '$offset',
      },
    ),
    ForumPost.fromJson,
  );

  Future<ForumPost> post(String id) async =>
      ForumPost.fromJson(await client.get('forum/posts/$id/') as Map<String, dynamic>);

  /// Sends the post with its files in one request; a large video may take a
  /// while on a slow network.
  Future<ForumPost> create({
    required String body,
    String assignment = '',
    List<ForumUpload> files = const [],
    String? clientId,
  }) async => ForumPost.fromJson(
    await client.postMultipart(
      'forum/posts/',
      fields: {'body': body, 'assignment': assignment, 'client_id': clientId},
      files: () async => [
        for (final file in files)
          http.MultipartFile.fromBytes('files', file.bytes, filename: file.fileName),
      ],
      requestTimeout: const Duration(minutes: 10),
    ) as Map<String, dynamic>,
  );

  Future<void> delete(String id) => client.delete('forum/posts/$id/');

  Future<ForumPost> approve(String id) async =>
      ForumPost.fromJson(await client.post('forum/posts/$id/approve/') as Map<String, dynamic>);

  Future<ForumPost> reject(String id, String reason) async => ForumPost.fromJson(
    await client.post('forum/posts/$id/reject/', body: {'reason': reason.trim()})
        as Map<String, dynamic>,
  );

  Future<ForumPost> hide(String id, String reason) async => ForumPost.fromJson(
    await client.post('forum/posts/$id/hide/', body: {'reason': reason.trim()})
        as Map<String, dynamic>,
  );

  Future<List<ForumReply>> replies(String postId) async => [
    for (final item in await client.get('forum/posts/$postId/replies/') as List<dynamic>)
      ForumReply.fromJson(item as Map<String, dynamic>),
  ];

  Future<ForumReply> reply(String postId, String body) async => ForumReply.fromJson(
    await client.post('forum/posts/$postId/replies/', body: {'body': body.trim()})
        as Map<String, dynamic>,
  );

  Future<ForumReply> hideReply(String id, String reason) async => ForumReply.fromJson(
    await client.post('forum/replies/$id/hide/', body: {'reason': reason.trim()})
        as Map<String, dynamic>,
  );

  Future<void> deleteReply(String id) => client.delete('forum/replies/$id/');

  Future<ForumSettings> settings() async =>
      ForumSettings.fromJson(await client.get('forum/settings/') as Map<String, dynamic>);

  Future<ForumSettings> setApprovalRequired(bool required) async => ForumSettings.fromJson(
    await client.patch('forum/settings/', body: {'approval_required': required})
        as Map<String, dynamic>,
  );

  Future<List<AssignmentTag>> assignments() async => [
    for (final item in await client.get('forum/assignments/') as List<dynamic>)
      AssignmentTag(
        tag: (item as Map<String, dynamic>)['tag'] as String,
        posts: item['posts'] as int? ?? 0,
      ),
  ];

  Future<Uint8List> attachment(String id) => client.getBytes('forum/attachments/$id/');
}
