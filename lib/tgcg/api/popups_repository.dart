import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'access_repository.dart' show ApiPage;
import 'api_client.dart';

/// How often each person sees a pop-up: the server's code, and its name.
const popupFrequencies = [
  ('once', 'Once only'),
  ('everyOpen', 'Every sign-in'),
  ('daily', 'Once a day'),
  ('weekly', 'Once a week'),
];

String popupFrequencyLabel(String code) =>
    popupFrequencies.firstWhere((frequency) => frequency.$1 == code, orElse: () => (code, code)).$2;

/// A message that pops up for everyone. Its dates, state and author come only
/// to those who post them.
class PopupPost {
  const PopupPost({
    required this.id,
    required this.title,
    required this.body,
    required this.frequency,
    this.hasPicture = false,
    this.linkUrl = '',
    this.linkLabel = '',
    this.startsAt,
    this.endsAt,
    this.state = '',
    this.author = '',
  });

  final String id;
  final String title;
  final String body;

  /// A code from [popupFrequencies].
  final String frequency;
  final bool hasPicture;
  final String linkUrl;
  final String linkLabel;
  final DateTime? startsAt;
  final DateTime? endsAt;

  /// showing, scheduled, ended or stopped.
  final String state;
  final String author;

  bool get hasLink => linkUrl.isNotEmpty && linkLabel.isNotEmpty;

  /// It comes back each time someone signs in or opens the app.
  bool get everyOpen => frequency == 'everyOpen';

  /// How long before someone sees it again; null when they see it only once.
  Duration? get repeatEvery => switch (frequency) {
    'daily' => const Duration(hours: 24),
    'weekly' => const Duration(days: 7),
    _ => null,
  };

  factory PopupPost.fromJson(Map<String, dynamic> json) => PopupPost(
    id: json['id'] as String,
    title: json['title'] as String? ?? '',
    body: json['body'] as String? ?? '',
    frequency: json['frequency'] as String? ?? 'once',
    hasPicture: json['has_picture'] as bool? ?? false,
    linkUrl: json['link_url'] as String? ?? '',
    linkLabel: json['link_label'] as String? ?? '',
    startsAt: DateTime.tryParse(json['starts_at'] as String? ?? '')?.toLocal(),
    endsAt: DateTime.tryParse(json['ends_at'] as String? ?? '')?.toLocal(),
    state: json['state'] as String? ?? '',
    author: json['author'] as String? ?? '',
  );
}

/// Pop-up messages: what shows now, and posting and stopping them.
class PopupsRepository {
  PopupsRepository(this.client);

  final ApiClient client;

  /// What pops up now, newest first.
  Future<List<PopupPost>> showing() async => [
    for (final item in await client.get('me/popups/') as List<dynamic>)
      PopupPost.fromJson(item as Map<String, dynamic>),
  ];

  /// Every message posted, newest first, for those who post them.
  Future<ApiPage<PopupPost>> posted({int offset = 0}) async => ApiPage.fromJson(
    await client.get('popups/', query: {if (offset > 0) 'offset': '$offset'}),
    PopupPost.fromJson,
  );

  /// [picture] goes with it in one request. Without [startsAt] it shows at once.
  Future<PopupPost> post({
    required String title,
    required String body,
    required String frequency,
    ({Uint8List bytes, String name})? picture,
    String linkUrl = '',
    String linkLabel = '',
    DateTime? startsAt,
    DateTime? endsAt,
  }) async => PopupPost.fromJson(
    await client.postMultipart(
          'popups/',
          fields: {
            'title': title.trim(),
            'body': body.trim(),
            'frequency': frequency,
            if (linkUrl.trim().isNotEmpty) 'link_url': linkUrl.trim(),
            if (linkLabel.trim().isNotEmpty) 'link_label': linkLabel.trim(),
            'starts_at': startsAt?.toUtc().toIso8601String(),
            'ends_at': endsAt?.toUtc().toIso8601String(),
          },
          files: () async => [
            if (picture != null)
              http.MultipartFile.fromBytes('picture', picture.bytes, filename: picture.name),
          ],
          requestTimeout: const Duration(minutes: 2),
        )
        as Map<String, dynamic>,
  );

  Future<PopupPost> stop(String id) async =>
      PopupPost.fromJson(await client.post('popups/$id/stop/') as Map<String, dynamic>);

  Future<Uint8List> picture(String id) => client.getBytes('popups/$id/picture/');
}
