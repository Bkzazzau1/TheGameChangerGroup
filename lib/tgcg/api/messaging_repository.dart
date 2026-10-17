import '../domain/models.dart';
import 'api_client.dart';
import 'meetings_repository.dart' show scopeInput;

DateTime? _date(Object? value) => value == null ? null : DateTime.tryParse('$value')?.toLocal();

/// The channels a message can go on, as the server names them.
const messageChannels = [
  ('sms', 'SMS'),
  ('whatsapp', 'WhatsApp'),
  ('push', 'App notification'),
];

String channelLabel(String channel) =>
    messageChannels.firstWhere((item) => item.$1 == channel, orElse: () => (channel, channel)).$2;

/// One group of people a message goes to. A message reaches everyone in any
/// of its groups, once.
class MessageGroup {
  const MessageGroup.filter({
    this.areas = const [],
    this.people = 'everyone',
    this.roles = const [],
    this.gender = '',
    this.verifiedOnly = false,
  }) : type = 'filter',
       id = null,
       name = null;

  const MessageGroup.project(String this.id, String this.name)
    : type = 'project',
      areas = const [],
      people = 'everyone',
      roles = const [],
      gender = '',
      verifiedOnly = false;

  const MessageGroup.list(String this.id, String this.name)
    : type = 'list',
      areas = const [],
      people = 'everyone',
      roles = const [],
      gender = '',
      verifiedOnly = false;

  /// filter, project or list.
  final String type;
  final List<GeographicScope> areas;

  /// everyone, withRole, noRole or roles.
  final String people;

  /// Role codes and names, when [people] is roles.
  final List<(String, String)> roles;

  /// male, female, or empty for both.
  final String gender;
  final bool verifiedOnly;

  /// The project's or list's id and name.
  final String? id;
  final String? name;

  Map<String, Object?> toJson() => switch (type) {
    'project' => {'type': 'project', 'project': id},
    'list' => {'type': 'list', 'list': id},
    _ => {
      'type': 'filter',
      'areas': [for (final area in areas) scopeInput(area)],
      'people': people,
      if (people == 'roles') 'roles': [for (final (code, _) in roles) code],
      'gender': gender,
      'verified_only': verifiedOnly,
    },
  };
}

class MessagePreview {
  const MessagePreview({required this.people, required this.channels, this.smsPages = 0});

  /// Everyone reached on at least one channel.
  final int people;

  /// Per channel: (reachable, unreachable: no number or no app).
  final Map<String, (int, int)> channels;
  final int smsPages;

  factory MessagePreview.fromJson(Map<String, dynamic> json) => MessagePreview(
    people: (json['people'] as num).toInt(),
    channels: {
      for (final entry in (json['channels'] as Map<String, dynamic>).entries)
        entry.key: (
          ((entry.value as Map<String, dynamic>)['reachable'] as num).toInt(),
          ((entry.value as Map<String, dynamic>)['unreachable'] as num).toInt(),
        ),
    },
    smsPages: (json['sms_pages'] as num?)?.toInt() ?? 0,
  );
}

/// A message as its sender sees it, with how far it got on each channel.
class SentMessage {
  const SentMessage({
    required this.id,
    required this.body,
    required this.channels,
    required this.people,
    required this.status,
    this.title = '',
    this.createdAt,
    this.delivered = const {},
  });

  final String id;
  final String title;
  final String body;
  final List<String> channels;
  final int people;

  /// sending or done.
  final String status;
  final DateTime? createdAt;

  /// Per channel, counts by status (sent, failed, queued, sending).
  final Map<String, Map<String, int>> delivered;

  int count(String channel, String status) => delivered[channel]?[status] ?? 0;

  factory SentMessage.fromJson(Map<String, dynamic> json) => SentMessage(
    id: json['id'] as String,
    title: json['title'] as String? ?? '',
    body: json['body'] as String,
    channels: [for (final channel in json['channels'] as List<dynamic>) '$channel'],
    people: (json['people'] as num?)?.toInt() ?? 0,
    status: json['status'] as String,
    createdAt: _date(json['created_at']),
    delivered: {
      for (final entry in ((json['delivered'] as Map<String, dynamic>?) ?? const {}).entries)
        entry.key: {
          for (final count in (entry.value as Map<String, dynamic>).entries)
            count.key: (count.value as num).toInt(),
        },
    },
  );
}

class SavedList {
  const SavedList({required this.id, required this.name, required this.people, this.members = const []});

  final String id;
  final String name;
  final int people;

  /// (membership number, name); loaded with a single list.
  final List<(String, String)> members;

  factory SavedList.fromJson(Map<String, dynamic> json) => SavedList(
    id: json['id'] as String,
    name: json['name'] as String,
    people: (json['people'] as num?)?.toInt() ?? 0,
    members: [
      for (final member in (json['members'] as List<dynamic>? ?? const []))
        (
          (member as Map<String, dynamic>)['membership_number'] as String,
          member['full_name'] as String? ?? '',
        ),
    ],
  );
}

class InboxMessage {
  const InboxMessage({required this.id, required this.body, this.title = '', this.createdAt});

  final String id;
  final String title;
  final String body;
  final DateTime? createdAt;

  factory InboxMessage.fromJson(Map<String, dynamic> json) => InboxMessage(
    id: json['id'] as String,
    title: json['title'] as String? ?? '',
    body: json['body'] as String,
    createdAt: _date(json['created_at']),
  );
}

/// The roles a group can name, and the channels this account may send on.
class MessagingOptions {
  const MessagingOptions({required this.roles, required this.channels});

  final List<(String, String)> roles;
  final List<String> channels;
}

/// Bulk messages (`/broadcasts/`), saved lists, the inbox, and phones that
/// receive app notifications.
class MessagingRepository {
  MessagingRepository(this.client);

  final ApiClient client;

  Future<MessagingOptions> options() async {
    final json = await client.get('broadcasts/roles/') as Map<String, dynamic>;
    return MessagingOptions(
      roles: [
        for (final role in json['roles'] as List<dynamic>)
          (
            (role as Map<String, dynamic>)['code'] as String,
            role['name'] as String,
          ),
      ],
      channels: [for (final channel in json['channels'] as List<dynamic>) '$channel'],
    );
  }

  Map<String, Object?> _message(List<String> channels, List<MessageGroup> groups, String body, String title) => {
    'channels': channels,
    'title': title.trim(),
    'body': body.trim(),
    'groups': [for (final group in groups) group.toJson()],
  };

  Future<MessagePreview> preview({
    required List<String> channels,
    required List<MessageGroup> groups,
    String body = '',
  }) async => MessagePreview.fromJson(
    await client.post('broadcasts/preview/', body: _message(channels, groups, body, ''))
        as Map<String, dynamic>,
  );

  Future<SentMessage> send({
    required List<String> channels,
    required List<MessageGroup> groups,
    required String body,
    String title = '',
  }) async => SentMessage.fromJson(
    await client.post('broadcasts/', body: _message(channels, groups, body, title))
        as Map<String, dynamic>,
  );

  Future<List<SentMessage>> sent() async {
    final json = await client.get('broadcasts/');
    final items = json is Map<String, dynamic> ? json['results'] as List<dynamic> : json as List<dynamic>;
    return [for (final item in items) SentMessage.fromJson(item as Map<String, dynamic>)];
  }

  Future<List<SavedList>> lists() async {
    final json = await client.get('message-lists/');
    final items = json is Map<String, dynamic> ? json['results'] as List<dynamic> : json as List<dynamic>;
    return [for (final item in items) SavedList.fromJson(item as Map<String, dynamic>)];
  }

  Future<SavedList> list(String id) async =>
      SavedList.fromJson(await client.get('message-lists/$id/') as Map<String, dynamic>);

  Future<SavedList> createList(String name, {List<String> members = const [], List<MessageGroup> groups = const []}) async =>
      SavedList.fromJson(
        await client.post(
          'message-lists/',
          body: {
            'name': name.trim(),
            'members': members,
            'groups': [for (final group in groups) group.toJson()],
          },
        ) as Map<String, dynamic>,
      );

  Future<SavedList> updateList(String id, {String? name, List<String> add = const [], List<String> remove = const []}) async =>
      SavedList.fromJson(
        await client.patch(
          'message-lists/$id/',
          body: {'name': ?name, if (add.isNotEmpty) 'add': add, if (remove.isNotEmpty) 'remove': remove},
        ) as Map<String, dynamic>,
      );

  Future<void> deleteList(String id) async => client.delete('message-lists/$id/');

  Future<List<InboxMessage>> inbox() async => [
    for (final item in await client.get('me/messages/') as List<dynamic>)
      InboxMessage.fromJson(item as Map<String, dynamic>),
  ];

  /// This phone receives the account's app notifications.
  Future<void> registerDevice(String token, String platform) async =>
      client.post('me/devices/', body: {'token': token, 'platform': platform});

  Future<void> unregisterDevice(String token) async =>
      client.delete('me/devices/', body: {'token': token});
}
