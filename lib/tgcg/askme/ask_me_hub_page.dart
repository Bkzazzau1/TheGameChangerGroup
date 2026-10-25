import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../access/access_widgets.dart'
    show confirmAction, failureMessage, formatMoment, promptText, showDone, showFailure;
import '../api/access_repository.dart' show ApiPage;
import '../api/askme_repository.dart';
import '../api/backend.dart';
import '../ui/tgcg_design.dart';
import 'ask_me_chat.dart';

/// Ask Me in the operations app: everyone asks; reviewers also review
/// answers and build the library from trusted official pages; a National
/// Administrator approves what Ask Me may say and sets its switches.
class AskMeHubPage extends StatefulWidget {
  const AskMeHubPage({super.key, this.openSource = openSourceInBrowser});

  final OpenSource openSource;

  @override
  State<AskMeHubPage> createState() => _AskMeHubPageState();
}

enum _Section { ask, review, library, sources, settings }

class _AskMeHubPageState extends State<AskMeHubPage> {
  AskMeAccess? _access;
  Object? _error;
  var _section = _Section.ask;
  var _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started || TgcgBackend.of(context) == null) return;
    _started = true;
    _load();
  }

  Future<void> _load() async {
    try {
      final access = await TgcgBackend.of(context)!.askMe.me();
      if (mounted) setState(() => _access = access);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final access = _access;
    if (TgcgBackend.of(context) == null || _error != null || access == null || !access.canReview) {
      // AskMeChat shows its own loading, errors and "not open yet".
      return AskMeChat(openSource: widget.openSource);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: SegmentedButton<_Section>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: _Section.ask, label: Text('Ask')),
              ButtonSegment(value: _Section.review, label: Text('Review')),
              ButtonSegment(value: _Section.library, label: Text('Library')),
              ButtonSegment(value: _Section.sources, label: Text('Sources')),
              ButtonSegment(value: _Section.settings, label: Text('Settings')),
            ],
            selected: {_section},
            onSelectionChanged: (chosen) => setState(() => _section = chosen.first),
          ),
        ),
        Expanded(
          child: switch (_section) {
            _Section.ask => AskMeChat(openSource: widget.openSource),
            _Section.review => const _ReviewSection(),
            _Section.library => _LibrarySection(canApprove: access.canApprove),
            _Section.sources => _SourcesSection(
              canApprove: access.canApprove,
              aiReady: access.aiReady,
            ),
            _Section.settings => _SettingsSection(canApprove: access.canApprove),
          },
        ),
      ],
    );
  }
}

/// A list that loads page by page, for the sections below.
mixin _Paged<T, W extends StatefulWidget> on State<W> {
  final items = <T>[];
  var hasMore = false;
  var loading = false;
  Object? error;
  var _generation = 0;

  Future<ApiPage<T>> fetch(int offset);

  Future<void> load({bool reset = false}) async {
    final generation = reset ? ++_generation : _generation;
    setState(() {
      if (reset) {
        items.clear();
        hasMore = false;
      }
      loading = true;
      error = null;
    });
    try {
      final page = await fetch(items.length);
      if (!mounted || generation != _generation) return;
      setState(() {
        items.addAll(page.items);
        hasMore = page.hasMore;
      });
    } catch (caught) {
      if (mounted && generation == _generation) setState(() => error = caught);
    } finally {
      if (mounted && generation == _generation) setState(() => loading = false);
    }
  }

  List<Widget> listFooter({required String emptyTitle, required IconData icon}) => [
    if (error != null)
      TgcgEmptyState(
        icon: Icons.error_outline_rounded,
        title: 'Could not load',
        message: failureMessage(error!),
        action: OutlinedButton(onPressed: () => load(reset: items.isEmpty), child: const Text('Try again')),
      )
    else if (!loading && items.isEmpty)
      TgcgEmptyState(icon: icon, title: emptyTitle, message: 'Nothing here right now.'),
    if (loading)
      const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
    else if (hasMore && error == null)
      OutlinedButton(onPressed: load, child: const Text('Show more')),
  ];
}

Widget _chips<T>(List<(T, String)> options, T selected, ValueChanged<T> onSelected) => Wrap(
  spacing: 8,
  runSpacing: 8,
  children: [
    for (final (value, label) in options)
      ChoiceChip(
        label: Text(label),
        selected: selected == value,
        onSelected: (_) => onSelected(value),
      ),
  ],
);

String _languageName(String code) =>
    code.isEmpty ? 'Language not detected' : AskMeLanguage.fromCode(code).label;

/// Writes or corrects an answer. Null when cancelled.
Future<String?> _writeAnswer(BuildContext context, String initial) => showDialog<String>(
  context: context,
  builder: (_) => _LongTextDialog(title: 'The right answer', initial: initial, action: 'Save answer'),
);

class _LongTextDialog extends StatefulWidget {
  const _LongTextDialog({required this.title, required this.initial, required this.action});

  final String title;
  final String initial;
  final String action;

  @override
  State<_LongTextDialog> createState() => _LongTextDialogState();
}

class _LongTextDialogState extends State<_LongTextDialog> {
  late final _text = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 520,
      child: TextField(
        controller: _text,
        autofocus: true,
        minLines: 4,
        maxLines: 10,
        inputFormatters: [LengthLimitingTextInputFormatter(1500)],
        onChanged: (_) => setState(() {}),
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
      FilledButton(
        onPressed: _text.text.trim().isEmpty ? null : () => Navigator.of(context).pop(_text.text.trim()),
        child: Text(widget.action),
      ),
    ],
  );
}

// --- Review ----------------------------------------------------------------------------

const _reviewKinds = <(String, String)>[
  ('', 'New'),
  ('not_yet', 'Not yet answered'),
  ('flagged', 'Marked unhelpful'),
  ('held', 'Held back'),
  ('reviewed', 'Reviewed'),
];

class _ReviewSection extends StatefulWidget {
  const _ReviewSection();

  @override
  State<_ReviewSection> createState() => _ReviewSectionState();
}

class _ReviewSectionState extends State<_ReviewSection> with _Paged<AskMeReviewItem, _ReviewSection> {
  var _kind = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (items.isEmpty && !loading && error == null) load(reset: true);
  }

  @override
  Future<ApiPage<AskMeReviewItem>> fetch(int offset) =>
      TgcgBackend.of(context)!.askMe.reviewQueue(kind: _kind, offset: offset);

  Future<void> _decide(AskMeReviewItem question, String decision) async {
    final askMe = TgcgBackend.of(context)!.askMe;
    var corrected = '';
    if (decision == 'correct') {
      final written = await _writeAnswer(context, question.correctedAnswer.isNotEmpty ? question.correctedAnswer : question.answer);
      if (written == null) return;
      corrected = written;
    }
    try {
      final decided = await askMe.decide(question.id, decision, correctedAnswer: corrected);
      if (!mounted) return;
      setState(() {
        final index = items.indexWhere((item) => item.id == question.id);
        if (index < 0) return;
        if (_kind == 'reviewed') {
          items[index] = decided;
        } else {
          items.removeAt(index);
        }
      });
      showDone(context, switch (decision) {
        'approve' => 'Approved: it answers the same question from now on.',
        'correct' => 'Saved: your answer is given to the same question from now on.',
        _ => 'Rejected.',
      });
    } catch (caught) {
      if (mounted) showFailure(context, caught);
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      _chips(_reviewKinds, _kind, (kind) {
        _kind = kind;
        load(reset: true);
      }),
      const SizedBox(height: 14),
      for (final question in items)
        _ReviewCard(
          key: ValueKey(question.id),
          question: question,
          onApprove: question.answer.isNotEmpty && (question.status == 'answered' || question.status == 'refused')
              ? () => _decide(question, 'approve')
              : null,
          onCorrect: () => _decide(question, 'correct'),
          onReject: question.review == 'rejected' ? null : () => _decide(question, 'reject'),
        ),
      ...listFooter(emptyTitle: 'No questions here', icon: Icons.fact_check_outlined),
    ],
  );
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({
    super.key,
    required this.question,
    required this.onApprove,
    required this.onCorrect,
    required this.onReject,
  });

  final AskMeReviewItem question;
  final VoidCallback? onApprove;
  final VoidCallback onCorrect;
  final VoidCallback? onReject;

  @override
  Widget build(BuildContext context) {
    final shown = question.correctedAnswer.isNotEmpty ? question.correctedAnswer : question.answer;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(question.question, style: const TextStyle(fontWeight: FontWeight.w800)),
            Text(
              [
                _languageName(question.language),
                if (question.createdAt != null) formatMoment(question.createdAt!),
                if (question.trainingOk) 'may be used for training',
              ].join(' · '),
              style: const TextStyle(color: TgcgColors.muted, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                TgcgStatusPill(
                  compact: true,
                  label: switch (question.status) {
                    'answered' => 'Answered',
                    'not_yet' => 'Not yet answered',
                    'refused' => 'Refused',
                    _ => 'Could not answer',
                  },
                  color: question.status == 'answered' ? TgcgColors.success : TgcgColors.warning,
                ),
                if (question.review != 'unreviewed')
                  TgcgStatusPill(compact: true, label: question.review, color: TgcgColors.primary),
              ],
            ),
            if (shown.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(shown, style: const TextStyle(color: TgcgColors.ink, height: 1.35)),
            ],
            if (question.checkFailed.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Held back: ${question.checkFailed}',
                style: const TextStyle(color: TgcgColors.warning, fontSize: 12.5),
              ),
            ],
            if (question.flagReason.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Member said: ${question.flagReason}',
                style: const TextStyle(color: TgcgColors.danger, fontSize: 12.5),
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (onApprove != null) FilledButton(onPressed: onApprove, child: const Text('Approve')),
                OutlinedButton(
                  onPressed: onCorrect,
                  child: Text(shown.isEmpty ? 'Write the answer' : 'Correct'),
                ),
                if (onReject != null) TextButton(onPressed: onReject, child: const Text('Reject')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// --- Library -----------------------------------------------------------------------------

const _libraryViews = <(String, String)>[
  ('draft', 'Waiting for approval'),
  ('approved', 'Approved'),
  ('review', 'Needs another look'),
  ('retired', 'Retired'),
];

class _LibrarySection extends StatefulWidget {
  const _LibrarySection({required this.canApprove});

  final bool canApprove;

  @override
  State<_LibrarySection> createState() => _LibrarySectionState();
}

class _LibrarySectionState extends State<_LibrarySection> with _Paged<AskMeItem, _LibrarySection> {
  var _view = 'draft';
  final _search = TextEditingController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (items.isEmpty && !loading && error == null) load(reset: true);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Future<ApiPage<AskMeItem>> fetch(int offset) => TgcgBackend.of(context)!.askMe.items(
    status: _view == 'review' ? null : _view,
    needsReview: _view == 'review',
    search: _search.text,
    offset: offset,
  );

  Future<void> _edit([AskMeItem? item]) async {
    final saved = await Navigator.of(context).push<AskMeItem>(
      MaterialPageRoute(builder: (_) => AskMeItemEditor(item: item)),
    );
    if (saved == null || !mounted) return;
    showDone(context, 'Saved. It waits for approval before Ask Me uses it.');
    load(reset: true);
  }

  Future<void> _approve(AskMeItem item) async {
    try {
      await TgcgBackend.of(context)!.askMe.approveItem(item.id);
      if (!mounted) return;
      showDone(context, 'Approved: Ask Me may use it now.');
      load(reset: true);
    } catch (caught) {
      if (mounted) showFailure(context, caught);
    }
  }

  Future<void> _retire(AskMeItem item) async {
    final askMe = TgcgBackend.of(context)!.askMe;
    final reason = await promptText(context, title: 'Retire this item?', label: 'Reason', action: 'Retire', destructive: true);
    if (reason == null) return;
    try {
      await askMe.retireItem(item.id, reason);
      if (!mounted) return;
      showDone(context, 'Retired: Ask Me no longer uses it.');
      load(reset: true);
    } catch (caught) {
      if (mounted) showFailure(context, caught);
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => load(reset: true),
              decoration: const InputDecoration(
                labelText: 'Search the library',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
          ),
          const SizedBox(width: 10),
          FilledButton.icon(
            onPressed: _edit,
            icon: const Icon(Icons.add_rounded),
            label: const Text('New item'),
          ),
        ],
      ),
      const SizedBox(height: 12),
      _chips(_libraryViews, _view, (view) {
        _view = view;
        load(reset: true);
      }),
      const SizedBox(height: 14),
      for (final item in items)
        Card(
          key: ValueKey(item.id),
          margin: const EdgeInsets.only(bottom: 10),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title, style: const TextStyle(fontWeight: FontWeight.w800)),
                Text(
                  [
                    askMeTopics[item.topic] ?? item.topic,
                    if (item.sourceUrl.isNotEmpty) Uri.tryParse(item.sourceUrl)?.host ?? item.sourceUrl,
                  ].join(' · '),
                  style: const TextStyle(color: TgcgColors.muted, fontSize: 12),
                ),
                const SizedBox(height: 6),
                Text(item.fact, maxLines: 4, overflow: TextOverflow.ellipsis),
                if (item.reviewNote.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(item.reviewNote, style: const TextStyle(color: TgcgColors.warning, fontSize: 12.5)),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton(onPressed: () => _edit(item), child: const Text('Edit')),
                    if (widget.canApprove && (item.status == 'draft' || item.reviewNote.isNotEmpty))
                      FilledButton(onPressed: () => _approve(item), child: const Text('Approve')),
                    if (widget.canApprove && item.status != 'retired')
                      TextButton(onPressed: () => _retire(item), child: const Text('Retire')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ...listFooter(emptyTitle: 'No items here', icon: Icons.menu_book_outlined),
    ],
  );
}

/// Writes or edits a library item: the fact, the argument for it, the
/// approved replies to complaints, and where it comes from.
class AskMeItemEditor extends StatefulWidget {
  const AskMeItemEditor({super.key, this.item, this.page});

  final AskMeItem? item;

  /// A page the new item comes from.
  final AskMeSourcePage? page;

  @override
  State<AskMeItemEditor> createState() => _AskMeItemEditorState();
}

class _AskMeItemEditorState extends State<AskMeItemEditor> {
  late String _topic = widget.item?.topic ?? 'achievement';
  late final _title = TextEditingController(text: widget.item?.title ?? '');
  late final _fact = TextEditingController(text: widget.item?.fact ?? '');
  late final _argument = TextEditingController(text: widget.item?.argument ?? '');
  late final _objections = TextEditingController(text: widget.item?.objections ?? '');
  late final _keywords = TextEditingController(text: widget.item?.keywords ?? '');
  late final _source = TextEditingController(text: widget.item?.sourceUrl ?? widget.page?.url ?? '');
  late DateTime? _date = widget.item?.factDate;
  var _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final controller in [_title, _fact, _argument, _objections, _keywords, _source]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? DateTime.now(),
      firstDate: DateTime(2023),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty || _fact.text.trim().isEmpty) {
      setState(() => _error = 'Give it a title and the fact.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final date = _date;
    try {
      final saved = await TgcgBackend.of(context)!.askMe.saveItem({
        'topic': _topic,
        'title': _title.text.trim(),
        'fact': _fact.text.trim(),
        'argument': _argument.text.trim(),
        'objections': _objections.text.trim(),
        'keywords': _keywords.text.trim(),
        'source_url': _source.text.trim(),
        'fact_date': date == null
            ? null
            : '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
        if (widget.item == null && widget.page != null) 'source_page': widget.page!.id,
      }, id: widget.item?.id);
      if (mounted) Navigator.of(context).pop(saved);
    } catch (caught) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = failureMessage(caught);
        });
      }
    }
  }

  Widget _field(TextEditingController controller, String label, {int lines = 1, int max = 2000}) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: controller,
      enabled: !_saving,
      minLines: lines,
      maxLines: lines == 1 ? 1 : lines + 4,
      inputFormatters: [LengthLimitingTextInputFormatter(max)],
      decoration: InputDecoration(labelText: label, alignLabelWithHint: lines > 1),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: TgcgColors.canvas,
    appBar: AppBar(title: Text(widget.item == null ? 'New library item' : 'Edit library item')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        DropdownButtonFormField<String>(
          initialValue: _topic,
          decoration: const InputDecoration(labelText: 'Topic'),
          items: [
            for (final topic in askMeTopics.entries)
              DropdownMenuItem(value: topic.key, child: Text(topic.value)),
          ],
          onChanged: _saving ? null : (value) => setState(() => _topic = value ?? _topic),
        ),
        const SizedBox(height: 12),
        _field(_title, 'Title', max: 200),
        _field(_fact, 'The fact, exactly as the source says it', lines: 3),
        _field(_argument, 'Why it matters (the argument)', lines: 3),
        _field(_objections, 'Common complaints and the approved reply to each', lines: 4, max: 3000),
        _field(_keywords, 'Keywords in any language', max: 500),
        _field(_source, 'Source page link (a trusted website)', max: 500),
        Row(
          children: [
            Expanded(
              child: Text(
                _date == null ? 'No date' : 'Date: ${_date!.day}/${_date!.month}/${_date!.year}',
                style: const TextStyle(color: TgcgColors.muted),
              ),
            ),
            TextButton(onPressed: _saving ? null : _pickDate, child: const Text('Choose date')),
            if (_date != null)
              TextButton(onPressed: _saving ? null : () => setState(() => _date = null), child: const Text('Clear')),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: const TextStyle(color: TgcgColors.danger)),
        ],
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving…' : 'Save for approval'),
        ),
      ],
    ),
  );
}

// --- Sources -----------------------------------------------------------------------------

class _SourcesSection extends StatefulWidget {
  const _SourcesSection({required this.canApprove, required this.aiReady});

  final bool canApprove;
  final bool aiReady;

  @override
  State<_SourcesSection> createState() => _SourcesSectionState();
}

class _SourcesSectionState extends State<_SourcesSection> with _Paged<AskMeSourcePage, _SourcesSection> {
  List<AskMeSite> _sites = const [];
  final _busy = <String>{};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (items.isEmpty && !loading && error == null) {
      load(reset: true);
      _loadSites();
    }
  }

  @override
  Future<ApiPage<AskMeSourcePage>> fetch(int offset) => TgcgBackend.of(context)!.askMe.pages(offset: offset);

  Future<void> _loadSites() async {
    try {
      final sites = await TgcgBackend.of(context)!.askMe.sites();
      if (mounted) setState(() => _sites = sites.items);
    } catch (_) {
      // The pages still list without the sites.
    }
  }

  Future<void> _addSite() async {
    final askMe = TgcgBackend.of(context)!.askMe;
    final domain = await promptText(
      context,
      title: 'Trust a website',
      label: 'Address, like statehouse.gov.ng',
      action: 'Next',
      required: true,
    );
    if (domain == null || !mounted) return;
    final name = await promptText(context, title: 'Its name', label: 'Name, like State House', action: 'Add');
    if (name == null) return;
    try {
      await askMe.addSite(domain, name: name);
      await _loadSites();
    } catch (caught) {
      if (mounted) showFailure(context, caught);
    }
  }

  Future<void> _setActive(AskMeSite site, bool active) async {
    try {
      await TgcgBackend.of(context)!.askMe.setSiteActive(site.id, active);
      await _loadSites();
    } catch (caught) {
      if (mounted) showFailure(context, caught);
    }
  }

  Future<void> _import() async {
    final askMe = TgcgBackend.of(context)!.askMe;
    final url = await promptText(
      context,
      title: 'Import a page',
      label: 'Link of the official page (https://...)',
      action: 'Import',
      required: true,
    );
    if (url == null) return;
    try {
      await askMe.importPage(url);
      if (!mounted) return;
      showDone(context, 'Page imported.');
      load(reset: true);
      _loadSites();
    } catch (caught) {
      if (mounted) showFailure(context, caught);
    }
  }

  Future<void> _work(AskMeSourcePage page, Future<void> Function() work) async {
    setState(() => _busy.add(page.id));
    try {
      await work();
    } catch (caught) {
      if (mounted) showFailure(context, caught);
    } finally {
      if (mounted) setState(() => _busy.remove(page.id));
    }
  }

  Future<void> _recheck(AskMeSourcePage page) => _work(page, () async {
    final checked = await TgcgBackend.of(context)!.askMe.recheckPage(page.id);
    if (!mounted) return;
    setState(() => items[items.indexWhere((item) => item.id == page.id)] = checked);
    showDone(context, checked.status == 'failed' ? 'It could not be read: ${checked.error}' : 'Page read again.');
  });

  Future<void> _suggest(AskMeSourcePage page) => _work(page, () async {
    final sure = await confirmAction(
      context,
      title: 'Draft items with AI?',
      message: 'The AI reads this page and drafts facts for the library. Each draft waits for approval.',
      action: 'Draft',
    );
    if (!sure || !mounted) return;
    final made = await TgcgBackend.of(context)!.askMe.suggestItems(page.id);
    if (!mounted) return;
    showDone(context, '${made.length} drafts added to the library, waiting for approval.');
    load(reset: true);
  });

  Future<void> _read(AskMeSourcePage page) => _work(page, () async {
    final full = await TgcgBackend.of(context)!.askMe.page(page.id);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(full.title.isEmpty ? full.url : full.title),
        content: SizedBox(
          width: 640,
          child: SingleChildScrollView(child: SelectableText(full.text)),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(this.context).push<AskMeItem>(
                MaterialPageRoute(builder: (_) => AskMeItemEditor(page: full)),
              );
            },
            child: const Text('Write an item from it'),
          ),
          FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
        ],
      ),
    );
  });

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      TgcgSectionCard(
        title: 'Trusted websites',
        trailing: widget.canApprove
            ? TextButton.icon(onPressed: _addSite, icon: const Icon(Icons.add_rounded), label: const Text('Add'))
            : null,
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            if (_sites.isEmpty)
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('None yet.', style: TextStyle(color: TgcgColors.muted)),
              ),
            for (final site in _sites)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(site.name.isEmpty ? site.domain : site.name),
                subtitle: Text('${site.domain} · ${site.pages} pages'),
                value: site.active,
                onChanged: widget.canApprove ? (active) => _setActive(site, active) : null,
              ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.icon(
          onPressed: _import,
          icon: const Icon(Icons.download_rounded),
          label: const Text('Import a page'),
        ),
      ),
      const SizedBox(height: 14),
      for (final page in items)
        Card(
          key: ValueKey(page.id),
          margin: const EdgeInsets.only(bottom: 10),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  page.title.isEmpty ? page.url : page.title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(page.url, style: const TextStyle(color: TgcgColors.muted, fontSize: 12)),
                const SizedBox(height: 6),
                Text(
                  [
                    '${page.items} items',
                    if (page.fetchedAt != null) 'read ${formatMoment(page.fetchedAt!)}',
                    if (page.changedAt != null) 'changed ${formatMoment(page.changedAt!)}',
                  ].join(' · '),
                  style: const TextStyle(color: TgcgColors.muted, fontSize: 12),
                ),
                if (page.status == 'failed')
                  Text(page.error, style: const TextStyle(color: TgcgColors.danger, fontSize: 12.5)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: _busy.contains(page.id) ? null : () => _read(page),
                      child: const Text('Read'),
                    ),
                    OutlinedButton(
                      onPressed: _busy.contains(page.id) ? null : () => _recheck(page),
                      child: const Text('Read again'),
                    ),
                    if (widget.aiReady)
                      FilledButton.icon(
                        onPressed: _busy.contains(page.id) ? null : () => _suggest(page),
                        icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                        label: const Text('Draft items with AI'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ...listFooter(emptyTitle: 'No pages yet', icon: Icons.public_rounded),
    ],
  );
}

// --- Settings ----------------------------------------------------------------------------

class _SettingsSection extends StatefulWidget {
  const _SettingsSection({required this.canApprove});

  final bool canApprove;

  @override
  State<_SettingsSection> createState() => _SettingsSectionState();
}

class _SettingsSectionState extends State<_SettingsSection> {
  AskMeSettings? _settings;
  Object? _error;
  var _saving = false;
  var _enabled = false;
  var _tone = 'calm';
  final _daily = TextEditingController();
  final _monthly = TextEditingController();
  DateTime? _silenceStarts;
  DateTime? _silenceEnds;
  final _messages = {
    for (final language in AskMeLanguage.values.where((language) => language.code.isNotEmpty))
      language.code: TextEditingController(),
  };
  var _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _load();
  }

  @override
  void dispose() {
    _daily.dispose();
    _monthly.dispose();
    for (final controller in _messages.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _show(AskMeSettings settings) {
    _settings = settings;
    _enabled = settings.enabled;
    _tone = settings.tone;
    _daily.text = '${settings.dailyLimit}';
    _monthly.text = '${settings.monthlyAiLimit}';
    _silenceStarts = settings.silenceStartsAt;
    _silenceEnds = settings.silenceEndsAt;
    for (final entry in _messages.entries) {
      entry.value.text = settings.notYetMessages[entry.key] ?? '';
    }
  }

  Future<void> _load() async {
    try {
      final settings = await TgcgBackend.of(context)!.askMe.settings();
      if (mounted) setState(() => _show(settings));
    } catch (caught) {
      if (mounted) setState(() => _error = caught);
    }
  }

  Future<DateTime?> _pickMoment(DateTime? initial) async {
    final day = await showDatePicker(
      context: context,
      initialDate: initial ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 1000)),
    );
    if (day == null || !mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial ?? DateTime(day.year, day.month, day.day, 8)),
    );
    if (time == null) return null;
    return DateTime(day.year, day.month, day.day, time.hour, time.minute);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final saved = await TgcgBackend.of(context)!.askMe.updateSettings({
        'enabled': _enabled,
        'tone': _tone,
        'daily_limit': int.tryParse(_daily.text.trim()) ?? 0,
        'monthly_ai_limit': int.tryParse(_monthly.text.trim()) ?? 0,
        'silence_starts_at': _silenceStarts?.toUtc().toIso8601String(),
        'silence_ends_at': _silenceEnds?.toUtc().toIso8601String(),
        'not_yet_messages': {
          for (final entry in _messages.entries)
            if (entry.value.text.trim().isNotEmpty) entry.key: entry.value.text.trim(),
        },
      });
      if (!mounted) return;
      setState(() => _show(saved));
      showDone(context, 'Settings saved.');
    } catch (caught) {
      if (mounted) showFailure(context, caught);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    if (_error != null) {
      return TgcgEmptyState(
        icon: Icons.error_outline_rounded,
        title: 'Settings could not be loaded',
        message: failureMessage(_error!),
      );
    }
    if (settings == null) return const Center(child: CircularProgressIndicator());
    final edit = widget.canApprove && !_saving;
    String moment(DateTime? value) => value == null ? 'Not set' : formatMoment(value);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            TgcgStatusPill(
              label: 'AI answers this month: ${settings.aiAnswersThisMonth} of ${settings.monthlyAiLimit}',
              color: TgcgColors.primary,
            ),
            if (settings.inSilence)
              const TgcgStatusPill(label: 'Campaign silence now', color: TgcgColors.warning),
          ],
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Open to members'),
          value: _enabled,
          onChanged: edit ? (value) => setState(() => _enabled = value) : null,
        ),
        const SizedBox(height: 8),
        const Text('Tone', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        SegmentedButton<String>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: 'calm', label: Text('Calm explainer')),
            ButtonSegment(value: 'passionate', label: Text('Passionate advocate')),
          ],
          selected: {_tone},
          onSelectionChanged: edit ? (chosen) => setState(() => _tone = chosen.first) : null,
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _daily,
                enabled: edit,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Questions per member a day'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _monthly,
                enabled: edit,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'AI answers a month'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const Text('Campaign silence', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('From ${moment(_silenceStarts)} to ${moment(_silenceEnds)}'),
            TextButton(
              onPressed: edit
                  ? () async {
                      final starts = await _pickMoment(_silenceStarts);
                      if (starts == null || !mounted) return;
                      final ends = await _pickMoment(_silenceEnds ?? starts.add(const Duration(days: 1)));
                      if (ends != null) {
                        setState(() {
                          _silenceStarts = starts;
                          _silenceEnds = ends;
                        });
                      }
                    }
                  : null,
              child: const Text('Choose'),
            ),
            if (_silenceStarts != null)
              TextButton(
                onPressed: edit
                    ? () => setState(() {
                          _silenceStarts = null;
                          _silenceEnds = null;
                        })
                    : null,
                child: const Text('Clear'),
              ),
          ],
        ),
        const SizedBox(height: 16),
        const Text('When there is no approved answer', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        for (final language in AskMeLanguage.values.where((language) => language.code.isNotEmpty))
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: TextField(
              controller: _messages[language.code],
              enabled: edit,
              maxLines: 2,
              decoration: InputDecoration(labelText: language.label),
            ),
          ),
        if (widget.canApprove) ...[
          const SizedBox(height: 8),
          FilledButton(onPressed: edit ? _save : null, child: Text(_saving ? 'Saving…' : 'Save settings')),
        ],
      ],
    );
  }
}
