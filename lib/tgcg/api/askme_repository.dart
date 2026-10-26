import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'access_repository.dart';
import 'api_client.dart';

DateTime? _date(Object? value) => value == null ? null : DateTime.tryParse('$value')?.toLocal();

/// The languages Ask Me answers in; [auto] answers in the question's own.
enum AskMeLanguage {
  auto('', 'Any language'),
  english('en', 'English'),
  hausa('ha', 'Hausa'),
  yoruba('yo', 'Yorùbá'),
  igbo('ig', 'Igbo'),
  pidgin('pcm', 'Pidgin');

  const AskMeLanguage(this.code, this.label);

  final String code;
  final String label;

  static AskMeLanguage fromCode(String? code) =>
      values.firstWhere((language) => language.code == code, orElse: () => auto);
}

/// Where an answer's facts come from.
class AskMeSource {
  const AskMeSource({required this.title, required this.url, this.date});

  final String title;
  final String url;
  final DateTime? date;

  factory AskMeSource.fromJson(Map<String, dynamic> json) => AskMeSource(
    title: json['title'] as String? ?? '',
    url: json['url'] as String? ?? '',
    date: _date(json['date']),
  );
}

List<AskMeSource> _sources(Object? json) => [
  for (final source in json as List<dynamic>? ?? const [])
    AskMeSource.fromJson(source as Map<String, dynamic>),
];

/// A question and Ask Me's answer, as its asker sees it.
class AskMeAnswer {
  const AskMeAnswer({
    required this.id,
    required this.question,
    required this.status,
    required this.answer,
    this.language = '',
    this.channel = 'text',
    this.sources = const [],
    this.rating,
    this.createdAt,
  });

  final String id;

  /// As typed, or as the voice service heard it.
  final String question;

  /// text or voice.
  final String channel;

  /// answered, not_yet, refused, limit, off or error.
  final String status;
  final String answer;
  final String language;
  final List<AskMeSource> sources;

  /// 1 helpful, -1 not, null not rated.
  final int? rating;
  final DateTime? createdAt;

  bool get isAnswered => status == 'answered';

  factory AskMeAnswer.fromJson(Map<String, dynamic> json) => AskMeAnswer(
    id: json['id'] as String,
    question: json['text'] as String? ?? '',
    status: json['status'] as String? ?? 'error',
    answer: json['answer'] as String? ?? '',
    language: json['language'] as String? ?? '',
    channel: json['channel'] as String? ?? 'text',
    sources: _sources(json['sources']),
    rating: (json['rating'] as num?)?.toInt(),
    createdAt: _date(json['created_at']),
  );
}

/// What this account may do in Ask Me.
class AskMeAccess {
  const AskMeAccess({
    this.canAsk = false,
    this.enabled = false,
    this.trainingOk,
    this.askedToday = 0,
    this.dailyLimit = 0,
    this.canReview = false,
    this.canApprove = false,
    this.aiReady = false,
    this.voiceReady = false,
    this.voiceOk,
  });

  final bool canAsk;
  final bool enabled;

  /// Null until the person has decided.
  final bool? trainingOk;
  final int askedToday;
  final int dailyLimit;
  final bool canReview;
  final bool canApprove;

  /// A Gemini key is set on the server.
  final bool aiReady;

  /// Questions may be spoken and answers heard.
  final bool voiceReady;

  /// May keep their spoken questions to train TGCG's listening AI; null
  /// until they decide.
  final bool? voiceOk;

  factory AskMeAccess.fromJson(Map<String, dynamic> json) => AskMeAccess(
    canAsk: json['can_ask'] as bool? ?? false,
    enabled: json['enabled'] as bool? ?? false,
    trainingOk: json['training_ok'] as bool?,
    askedToday: (json['asked_today'] as num?)?.toInt() ?? 0,
    dailyLimit: (json['daily_limit'] as num?)?.toInt() ?? 0,
    canReview: json['can_review'] as bool? ?? false,
    canApprove: json['can_approve'] as bool? ?? false,
    aiReady: json['ai_ready'] as bool? ?? false,
    voiceReady: json['voice_ready'] as bool? ?? false,
    voiceOk: json['voice_ok'] as bool?,
  );
}

class AskMeSite {
  const AskMeSite({
    required this.id,
    required this.domain,
    required this.name,
    this.active = true,
    this.pages = 0,
  });

  final String id;
  final String domain;
  final String name;
  final bool active;
  final int pages;

  factory AskMeSite.fromJson(Map<String, dynamic> json) => AskMeSite(
    id: json['id'] as String,
    domain: json['domain'] as String? ?? '',
    name: json['name'] as String? ?? '',
    active: json['active'] as bool? ?? true,
    pages: (json['pages'] as num?)?.toInt() ?? 0,
  );
}

/// A kept copy of an official page.
class AskMeSourcePage {
  const AskMeSourcePage({
    required this.id,
    required this.url,
    required this.site,
    this.title = '',
    this.status = 'ok',
    this.error = '',
    this.fetchedAt,
    this.changedAt,
    this.items = 0,
    this.text = '',
  });

  final String id;
  final String url;
  final String site;
  final String title;

  /// ok or failed.
  final String status;
  final String error;
  final DateTime? fetchedAt;
  final DateTime? changedAt;
  final int items;

  /// Only when one page is fetched.
  final String text;

  factory AskMeSourcePage.fromJson(Map<String, dynamic> json) => AskMeSourcePage(
    id: json['id'] as String,
    url: json['url'] as String? ?? '',
    site: json['site'] as String? ?? '',
    title: json['title'] as String? ?? '',
    status: json['status'] as String? ?? 'ok',
    error: json['error'] as String? ?? '',
    fetchedAt: _date(json['fetched_at']),
    changedAt: _date(json['changed_at']),
    items: (json['items'] as num?)?.toInt() ?? 0,
    text: json['text'] as String? ?? '',
  );
}

/// One piece of what Ask Me may say.
class AskMeItem {
  const AskMeItem({
    required this.id,
    required this.title,
    required this.fact,
    this.topic = 'achievement',
    this.argument = '',
    this.objections = '',
    this.keywords = '',
    this.sourcePage,
    this.sourceUrl = '',
    this.factDate,
    this.status = 'draft',
    this.reviewNote = '',
    this.approvedBy,
  });

  final String id;
  final String topic;
  final String title;
  final String fact;
  final String argument;

  /// Common complaints and the approved reply to each.
  final String objections;
  final String keywords;
  final String? sourcePage;
  final String sourceUrl;
  final DateTime? factDate;

  /// draft (waiting for approval), approved or retired.
  final String status;

  /// Why it needs another look, such as its page having changed.
  final String reviewNote;
  final String? approvedBy;

  factory AskMeItem.fromJson(Map<String, dynamic> json) => AskMeItem(
    id: json['id'] as String,
    topic: json['topic'] as String? ?? 'achievement',
    title: json['title'] as String? ?? '',
    fact: json['fact'] as String? ?? '',
    argument: json['argument'] as String? ?? '',
    objections: json['objections'] as String? ?? '',
    keywords: json['keywords'] as String? ?? '',
    sourcePage: json['source_page'] as String?,
    sourceUrl: json['source_url'] as String? ?? '',
    factDate: DateTime.tryParse('${json['fact_date']}'),
    status: json['status'] as String? ?? 'draft',
    reviewNote: json['review_note'] as String? ?? '',
    approvedBy: json['approved_by'] as String?,
  );
}

const askMeTopics = {
  'achievement': 'Government achievement',
  'voting': 'Voting and taking part',
  'tgcg': 'TGCG and its app',
};

/// A member's question as a reviewer sees it: no name.
class AskMeReviewItem {
  const AskMeReviewItem({
    required this.id,
    required this.question,
    required this.status,
    this.language = '',
    this.channel = 'text',
    this.correctedText = '',
    this.hasRecording = false,
    this.route = 'none',
    this.answer = '',
    this.correctedAnswer = '',
    this.sources = const [],
    this.checkFailed = '',
    this.rating,
    this.flagReason = '',
    this.review = 'unreviewed',
    this.trainingOk = false,
    this.createdAt,
  });

  final String id;
  final String question;
  final String status;
  final String language;

  /// text or voice.
  final String channel;

  /// What a spoken question really said, written by a reviewer.
  final String correctedText;

  /// The spoken question was kept (the asker allowed it).
  final bool hasRecording;

  /// ready (a reviewed answer), ai, or none.
  final String route;
  final String answer;
  final String correctedAnswer;
  final List<AskMeSource> sources;

  /// Why the server held the AI's answer back.
  final String checkFailed;
  final int? rating;
  final String flagReason;

  /// unreviewed, approved, corrected or rejected.
  final String review;
  final bool trainingOk;
  final DateTime? createdAt;

  factory AskMeReviewItem.fromJson(Map<String, dynamic> json) => AskMeReviewItem(
    id: json['id'] as String,
    question: json['text'] as String? ?? '',
    status: json['status'] as String? ?? '',
    language: json['language'] as String? ?? '',
    channel: json['channel'] as String? ?? 'text',
    correctedText: json['corrected_text'] as String? ?? '',
    hasRecording: json['has_recording'] as bool? ?? false,
    route: json['route'] as String? ?? 'none',
    answer: json['answer'] as String? ?? '',
    correctedAnswer: json['corrected_answer'] as String? ?? '',
    sources: _sources(json['sources']),
    checkFailed: json['check_failed'] as String? ?? '',
    rating: (json['rating'] as num?)?.toInt(),
    flagReason: json['flag_reason'] as String? ?? '',
    review: json['review'] as String? ?? 'unreviewed',
    trainingOk: json['training_ok'] as bool? ?? false,
    createdAt: _date(json['created_at']),
  );
}

/// Ask Me's switches, set by a National Administrator.
class AskMeSettings {
  const AskMeSettings({
    this.enabled = false,
    this.tone = 'calm',
    this.dailyLimit = 20,
    this.monthlyAiLimit = 5000,
    this.silenceStartsAt,
    this.silenceEndsAt,
    this.notYetMessages = const {},
    this.inSilence = false,
    this.aiAnswersThisMonth = 0,
    this.voiceEnabled = true,
    this.voices = const {},
    this.voiceReady = false,
    this.voiceOptions = const {},
  });

  final bool enabled;

  /// calm or passionate.
  final String tone;
  final int dailyLimit;
  final int monthlyAiLimit;
  final DateTime? silenceStartsAt;
  final DateTime? silenceEndsAt;

  /// What Ask Me says when it has no approved answer, by language code.
  final Map<String, String> notYetMessages;
  final bool inSilence;
  final int aiAnswersThisMonth;

  /// Members may speak questions and hear answers.
  final bool voiceEnabled;

  /// The chosen voice for each language code.
  final Map<String, String> voices;

  /// The voice service is set up on the server.
  final bool voiceReady;

  /// The voices to choose from, by language code.
  final Map<String, List<String>> voiceOptions;

  factory AskMeSettings.fromJson(Map<String, dynamic> json) => AskMeSettings(
    enabled: json['enabled'] as bool? ?? false,
    tone: json['tone'] as String? ?? 'calm',
    dailyLimit: (json['daily_limit'] as num?)?.toInt() ?? 0,
    monthlyAiLimit: (json['monthly_ai_limit'] as num?)?.toInt() ?? 0,
    silenceStartsAt: _date(json['silence_starts_at']),
    silenceEndsAt: _date(json['silence_ends_at']),
    notYetMessages: {
      for (final entry in (json['not_yet_messages'] as Map<String, dynamic>? ?? const {}).entries)
        entry.key: '${entry.value}',
    },
    inSilence: json['in_silence'] as bool? ?? false,
    aiAnswersThisMonth: (json['ai_answers_this_month'] as num?)?.toInt() ?? 0,
    voiceEnabled: json['voice_enabled'] as bool? ?? true,
    voices: {
      for (final entry in (json['voice_options'] as Map<String, dynamic>? ?? const {}).entries)
        entry.key: '${(entry.value as Map<String, dynamic>)['chosen'] ?? ''}',
    },
    voiceReady: json['voice_ready'] as bool? ?? false,
    voiceOptions: {
      for (final entry in (json['voice_options'] as Map<String, dynamic>? ?? const {}).entries)
        entry.key: [
          for (final voice in (entry.value as Map<String, dynamic>)['voices'] as List<dynamic>? ?? const [])
            '$voice',
        ],
    },
  );
}

/// Ask Me (`/askme/`): answers only from TGCG's approved library. The
/// server decides who asks, reviews and approves.
class AskMeRepository {
  AskMeRepository(this.client);

  final ApiClient client;

  Future<AskMeAnswer> ask(String text, {AskMeLanguage language = AskMeLanguage.auto}) async =>
      AskMeAnswer.fromJson(
        await client.post('askme/ask/', body: {'text': text.trim(), 'language': language.code})
            as Map<String, dynamic>,
      );

  Future<AskMeAccess> me() async =>
      AskMeAccess.fromJson(await client.get('askme/me/') as Map<String, dynamic>);

  /// Whether TGCG may use this person's questions to train its own model.
  Future<AskMeAccess> setTrainingConsent(bool allowed) async => AskMeAccess.fromJson(
    await client.patch('askme/me/', body: {'training_ok': allowed}) as Map<String, dynamic>,
  );

  /// Whether TGCG may keep this person's spoken questions to train its
  /// listening AI.
  Future<AskMeAccess> setVoiceConsent(bool allowed) async => AskMeAccess.fromJson(
    await client.patch('askme/me/', body: {'voice_ok': allowed}) as Map<String, dynamic>,
  );

  /// A spoken question, in [language] (not "any language"): the server has it
  /// written down and answers it like a typed one.
  Future<AskMeAnswer> askByVoice(
    Uint8List audio, {
    required String fileName,
    required AskMeLanguage language,
  }) async => AskMeAnswer.fromJson(
    await client.postMultipart(
      'askme/ask/voice/',
      fields: {'language': language.code},
      files: () async => [http.MultipartFile.fromBytes('audio', audio, filename: fileName)],
      requestTimeout: const Duration(minutes: 2),
    ) as Map<String, dynamic>,
  );

  /// The answer read aloud, as MP3.
  Future<Uint8List> answerAudio(String id) =>
      client.getBytes('askme/questions/$id/audio/', requestTimeout: const Duration(minutes: 1));

  /// A kept spoken question, for reviewers.
  Future<Uint8List> recording(String id) => client.getBytes('askme/review/$id/recording/');

  /// What a spoken question really said, written by a reviewer.
  Future<AskMeReviewItem> correctHeard(String id, String text) async => AskMeReviewItem.fromJson(
    await client.post('askme/review/$id/heard/', body: {'text': text.trim()}) as Map<String, dynamic>,
  );

  /// The account's own questions, newest first.
  Future<ApiPage<AskMeAnswer>> history({int offset = 0}) async => ApiPage.fromJson(
    await client.get('askme/questions/', query: {if (offset > 0) 'offset': '$offset'}),
    AskMeAnswer.fromJson,
  );

  Future<AskMeAnswer> rate(String id, int rating, {String reason = ''}) async =>
      AskMeAnswer.fromJson(
        await client.post('askme/questions/$id/rate/', body: {'rating': rating, 'reason': reason.trim()})
            as Map<String, dynamic>,
      );

  // --- reviewers and the National Administrator ----------------------------------

  Future<ApiPage<AskMeReviewItem>> reviewQueue({String kind = '', int offset = 0}) async =>
      ApiPage.fromJson(
        await client.get(
          'askme/review/',
          query: {if (kind.isNotEmpty) 'kind': kind, if (offset > 0) 'offset': '$offset'},
        ),
        AskMeReviewItem.fromJson,
      );

  /// approve, correct (with [correctedAnswer]) or reject.
  Future<AskMeReviewItem> decide(String id, String decision, {String correctedAnswer = ''}) async =>
      AskMeReviewItem.fromJson(
        await client.post(
          'askme/review/$id/decide/',
          body: {'decision': decision, 'corrected_answer': correctedAnswer.trim()},
        ) as Map<String, dynamic>,
      );

  Future<ApiPage<AskMeItem>> items({
    String? status,
    bool needsReview = false,
    String search = '',
    int offset = 0,
  }) async => ApiPage.fromJson(
    await client.get(
      'askme/items/',
      query: {
        if (status != null) 'status': status,
        if (needsReview) 'needs_review': 'true',
        if (search.trim().isNotEmpty) 'search': search.trim(),
        if (offset > 0) 'offset': '$offset',
      },
    ),
    AskMeItem.fromJson,
  );

  /// Creates an item, or edits [id]'s; either way it waits for approval.
  Future<AskMeItem> saveItem(Map<String, Object?> fields, {String? id}) async => AskMeItem.fromJson(
    await (id == null
            ? client.post('askme/items/', body: fields)
            : client.patch('askme/items/$id/', body: fields))
        as Map<String, dynamic>,
  );

  Future<AskMeItem> approveItem(String id) async =>
      AskMeItem.fromJson(await client.post('askme/items/$id/approve/') as Map<String, dynamic>);

  Future<AskMeItem> retireItem(String id, String reason) async => AskMeItem.fromJson(
    await client.post('askme/items/$id/retire/', body: {'reason': reason.trim()})
        as Map<String, dynamic>,
  );

  Future<ApiPage<AskMeSite>> sites() async =>
      ApiPage.fromJson(await client.get('askme/sites/'), AskMeSite.fromJson);

  Future<AskMeSite> addSite(String domain, {String name = ''}) async => AskMeSite.fromJson(
    await client.post('askme/sites/', body: {'domain': domain.trim(), 'name': name.trim()})
        as Map<String, dynamic>,
  );

  Future<AskMeSite> setSiteActive(String id, bool active) async => AskMeSite.fromJson(
    await client.patch('askme/sites/$id/', body: {'active': active}) as Map<String, dynamic>,
  );

  Future<ApiPage<AskMeSourcePage>> pages({int offset = 0}) async => ApiPage.fromJson(
    await client.get('askme/pages/', query: {if (offset > 0) 'offset': '$offset'}),
    AskMeSourcePage.fromJson,
  );

  Future<AskMeSourcePage> page(String id) async =>
      AskMeSourcePage.fromJson(await client.get('askme/pages/$id/') as Map<String, dynamic>);

  Future<AskMeSourcePage> importPage(String url) async => AskMeSourcePage.fromJson(
    await client.post('askme/pages/', body: {'url': url.trim()}) as Map<String, dynamic>,
  );

  Future<AskMeSourcePage> recheckPage(String id) async =>
      AskMeSourcePage.fromJson(await client.post('askme/pages/$id/recheck/') as Map<String, dynamic>);

  /// The AI drafts items from a page; they wait for approval.
  Future<List<AskMeItem>> suggestItems(String pageId) async => [
    for (final item in await client.post('askme/pages/$pageId/suggest/') as List<dynamic>)
      AskMeItem.fromJson(item as Map<String, dynamic>),
  ];

  Future<AskMeSettings> settings() async =>
      AskMeSettings.fromJson(await client.get('askme/settings/') as Map<String, dynamic>);

  Future<AskMeSettings> updateSettings(Map<String, Object?> fields) async => AskMeSettings.fromJson(
    await client.patch('askme/settings/', body: fields) as Map<String, dynamic>,
  );
}
