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

/// A post's or comment's likes, after liking it or taking the like back.
typedef ForumLikes = ({bool liked, int likes});

ForumLikes _likes(Object? json) {
  final map = json as Map<String, dynamic>;
  return (liked: map['liked'] as bool? ?? false, likes: map['likes'] as int? ?? 0);
}

/// published, hidden (by an editor) or deleted; posts from before 24
/// October 2026 may also be rejected (not approved).
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
    this.editedAt,
    this.reviewReason = '',
    this.attachments = const [],
    this.replies = 0,
    this.likes = 0,
    this.liked = false,
    this.isMine = false,
    this.canEdit = false,
    this.canHide = false,
    this.canRestore = false,
    this.canReport = false,
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
  final DateTime? editedAt;

  /// Why it was hidden: only for its author and editors.
  final String reviewReason;
  final List<ForumAttachment> attachments;

  /// Comments everyone sees.
  final int replies;
  final int likes;

  /// This account likes it.
  final bool liked;
  final bool isMine;

  /// Its author edits or deletes it.
  final bool canEdit;

  /// An editor hides it, or restores it when hidden.
  final bool canHide;
  final bool canRestore;
  final bool canReport;

  bool get isPublished => status == 'published';
  bool get isHidden => status == 'hidden';

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
    editedAt: _date(json['edited_at']),
    reviewReason: json['review_reason'] as String? ?? '',
    attachments: [
      for (final item in json['attachments'] as List<dynamic>? ?? const [])
        ForumAttachment.fromJson(item as Map<String, dynamic>),
    ],
    replies: json['replies'] as int? ?? 0,
    likes: json['likes'] as int? ?? 0,
    liked: json['liked'] as bool? ?? false,
    isMine: json['is_mine'] as bool? ?? false,
    canEdit: json['can_edit'] as bool? ?? false,
    canHide: json['can_hide'] as bool? ?? false,
    canRestore: json['can_restore'] as bool? ?? false,
    canReport: json['can_report'] as bool? ?? false,
  );

  ForumPost withLikes(ForumLikes value) => ForumPost(
    id: id,
    authorName: authorName,
    authorRole: authorRole,
    scope: scope,
    body: body,
    assignment: assignment,
    status: status,
    createdAt: createdAt,
    publishedAt: publishedAt,
    editedAt: editedAt,
    reviewReason: reviewReason,
    attachments: attachments,
    replies: replies,
    likes: value.likes,
    liked: value.liked,
    isMine: isMine,
    canEdit: canEdit,
    canHide: canHide,
    canRestore: canRestore,
    canReport: canReport,
  );
}

/// A comment on a post, or an answer to one ([parent]).
class ForumReply {
  const ForumReply({
    required this.id,
    required this.authorName,
    required this.authorRole,
    required this.body,
    required this.status,
    required this.createdAt,
    this.parent,
    this.editedAt,
    this.hideReason = '',
    this.likes = 0,
    this.liked = false,
    this.isMine = false,
    this.canEdit = false,
    this.canHide = false,
    this.canRestore = false,
    this.canReport = false,
  });

  final String id;

  /// The comment this answers; null for a comment on the post.
  final String? parent;
  final String authorName;
  final String authorRole;
  final String body;

  /// visible or hidden (hidden ones reach only their author and editors).
  final String status;
  final DateTime createdAt;
  final DateTime? editedAt;
  final String hideReason;
  final int likes;
  final bool liked;
  final bool isMine;
  final bool canEdit;
  final bool canHide;
  final bool canRestore;
  final bool canReport;

  bool get isHidden => status == 'hidden';
  bool get isVisible => status == 'visible';

  factory ForumReply.fromJson(Map<String, dynamic> json) => ForumReply(
    id: json['id'] as String,
    parent: json['parent'] as String?,
    authorName: json['author_name'] as String? ?? '',
    authorRole: json['author_role'] as String? ?? '',
    body: json['body'] as String? ?? '',
    status: json['status'] as String? ?? 'visible',
    createdAt: _date(json['created_at']) ?? DateTime.now(),
    editedAt: _date(json['edited_at']),
    hideReason: json['hide_reason'] as String? ?? '',
    likes: json['likes'] as int? ?? 0,
    liked: json['liked'] as bool? ?? false,
    isMine: json['is_mine'] as bool? ?? false,
    canEdit: json['can_edit'] as bool? ?? false,
    canHide: json['can_hide'] as bool? ?? false,
    canRestore: json['can_restore'] as bool? ?? false,
    canReport: json['can_report'] as bool? ?? false,
  );

  ForumReply withLikes(ForumLikes value) => ForumReply(
    id: id,
    parent: parent,
    authorName: authorName,
    authorRole: authorRole,
    body: body,
    status: status,
    createdAt: createdAt,
    editedAt: editedAt,
    hideReason: hideReason,
    likes: value.likes,
    liked: value.liked,
    isMine: isMine,
    canEdit: canEdit,
    canHide: canHide,
    canRestore: canRestore,
    canReport: canReport,
  );
}

/// A post or comment someone reported to the editors.
class ForumReport {
  const ForumReport({
    required this.id,
    required this.postId,
    required this.authorName,
    required this.excerpt,
    required this.targetStatus,
    required this.reason,
    required this.reporter,
    required this.createdAt,
    this.replyId,
  });

  final String id;
  final String postId;

  /// Set when a comment was reported.
  final String? replyId;

  /// Who wrote what was reported, and its words, shortened.
  final String authorName;
  final String excerpt;

  /// published or visible while it can still be hidden; hidden or deleted.
  final String targetStatus;
  final String reason;
  final String reporter;
  final DateTime createdAt;

  bool get isComment => replyId != null;
  bool get canHide => targetStatus == 'published' || targetStatus == 'visible';

  factory ForumReport.fromJson(Map<String, dynamic> json) => ForumReport(
    id: json['id'] as String,
    postId: json['post'] as String,
    replyId: json['reply'] as String?,
    authorName: json['author_name'] as String? ?? '',
    excerpt: json['excerpt'] as String? ?? '',
    targetStatus: json['target_status'] as String? ?? '',
    reason: json['reason'] as String? ?? '',
    reporter: json['reporter'] as String? ?? '',
    createdAt: _date(json['created_at']) ?? DateTime.now(),
  );
}

/// What this account may do in the forum.
class ForumMe {
  const ForumMe({required this.takesPart, required this.editor});

  /// Posts, comments, likes and reports: every member with an active
  /// membership, and every account with a role.
  final bool takesPart;

  /// Holds a role or position: hides and restores anywhere.
  final bool editor;

  factory ForumMe.fromJson(Map<String, dynamic> json) => ForumMe(
    takesPart: json['takes_part'] as bool? ?? false,
    editor: json['editor'] as bool? ?? false,
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

/// Which posts to list: the feed, this account's own, or (for editors) the
/// hidden ones.
enum ForumShow { feed, mine, hidden }

/// The Social Forum (`/forum/`). The server decides who posts, edits, hides
/// and restores.
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

  /// Its author changes the words or the assignment; pictures and videos stay.
  Future<ForumPost> edit(String id, {required String body, required String assignment}) async =>
      ForumPost.fromJson(
        await client.patch(
          'forum/posts/$id/',
          body: {'body': body.trim(), 'assignment': assignment.trim()},
        ) as Map<String, dynamic>,
      );

  Future<void> delete(String id) => client.delete('forum/posts/$id/');

  Future<ForumPost> hide(String id, String reason) async => ForumPost.fromJson(
    await client.post('forum/posts/$id/hide/', body: {'reason': reason.trim()})
        as Map<String, dynamic>,
  );

  Future<ForumPost> restore(String id) async =>
      ForumPost.fromJson(await client.post('forum/posts/$id/restore/') as Map<String, dynamic>);

  /// Likes the post, or takes the like back.
  Future<ForumLikes> like(String id, {bool on = true}) async => _likes(
    on
        ? await client.post('forum/posts/$id/like/')
        : await client.delete('forum/posts/$id/like/'),
  );

  Future<void> report(String id, String reason) =>
      client.post('forum/posts/$id/report/', body: {'reason': reason.trim()});

  /// Comments, oldest first, with their answers.
  Future<List<ForumReply>> replies(String postId) async => [
    for (final item in await client.get('forum/posts/$postId/replies/') as List<dynamic>)
      ForumReply.fromJson(item as Map<String, dynamic>),
  ];

  /// A comment on the post, or an answer to the comment [parent].
  Future<ForumReply> reply(String postId, String body, {String? parent}) async =>
      ForumReply.fromJson(
        await client.post(
          'forum/posts/$postId/replies/',
          body: {'body': body.trim(), 'parent': ?parent},
        ) as Map<String, dynamic>,
      );

  Future<ForumReply> editReply(String id, String body) async => ForumReply.fromJson(
    await client.patch('forum/replies/$id/', body: {'body': body.trim()}) as Map<String, dynamic>,
  );

  Future<void> deleteReply(String id) => client.delete('forum/replies/$id/');

  Future<ForumReply> hideReply(String id, String reason) async => ForumReply.fromJson(
    await client.post('forum/replies/$id/hide/', body: {'reason': reason.trim()})
        as Map<String, dynamic>,
  );

  Future<ForumReply> restoreReply(String id) async =>
      ForumReply.fromJson(await client.post('forum/replies/$id/restore/') as Map<String, dynamic>);

  Future<ForumLikes> likeReply(String id, {bool on = true}) async => _likes(
    on
        ? await client.post('forum/replies/$id/like/')
        : await client.delete('forum/replies/$id/like/'),
  );

  Future<void> reportReply(String id, String reason) =>
      client.post('forum/replies/$id/report/', body: {'reason': reason.trim()});

  /// Open reports, newest first, for editors.
  Future<ApiPage<ForumReport>> reports({int offset = 0}) async => ApiPage.fromJson(
    await client.get('forum/reports/', query: {if (offset > 0) 'offset': '$offset'}),
    ForumReport.fromJson,
  );

  /// Closes a report with nothing wrong; the post or comment stays.
  Future<void> dismissReport(String id) => client.post('forum/reports/$id/dismiss/', body: {});

  Future<ForumMe> me() async =>
      ForumMe.fromJson(await client.get('forum/me/') as Map<String, dynamic>);

  Future<List<AssignmentTag>> assignments() async => [
    for (final item in await client.get('forum/assignments/') as List<dynamic>)
      AssignmentTag(
        tag: (item as Map<String, dynamic>)['tag'] as String,
        posts: item['posts'] as int? ?? 0,
      ),
  ];

  Future<Uint8List> attachment(String id) => client.getBytes('forum/attachments/$id/');
}
