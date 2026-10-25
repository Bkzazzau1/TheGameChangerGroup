import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../access/access_widgets.dart' show failureMessage, promptText, showFailure;
import '../api/askme_repository.dart';
import '../api/backend.dart';
import '../ui/tgcg_design.dart';

/// Opens an answer's source page (replaced in tests).
typedef OpenSource = Future<bool> Function(Uri uri);

Future<bool> openSourceInBrowser(Uri uri) => launchUrl(uri, mode: LaunchMode.externalApplication);

/// Ask Me as its own screen, opened from the member app.
class AskMePage extends StatelessWidget {
  const AskMePage({super.key, this.openSource = openSourceInBrowser});

  final OpenSource openSource;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: TgcgColors.canvas,
    appBar: AppBar(title: const Text('Ask Me')),
    body: SafeArea(child: AskMeChat(openSource: openSource)),
  );
}

class _Turn {
  _Turn(this.question, {this.answer});

  final String question;
  AskMeAnswer? answer;
  Object? error;
  bool get sending => answer == null && error == null;
}

/// Questions and answers. Answers come only from TGCG's approved library,
/// in the language chosen (or the question's own), with their sources.
class AskMeChat extends StatefulWidget {
  const AskMeChat({super.key, this.openSource = openSourceInBrowser});

  final OpenSource openSource;

  @override
  State<AskMeChat> createState() => _AskMeChatState();
}

class _AskMeChatState extends State<AskMeChat> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  final _turns = <_Turn>[];
  var _language = AskMeLanguage.auto;
  AskMeAccess? _access;
  Object? _error;
  var _started = false;

  AskMeRepository get _askMe => TgcgBackend.of(context)!.askMe;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started || TgcgBackend.of(context) == null) return;
    _started = true;
    _load();
  }

  @override
  void dispose() {
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final askMe = _askMe;
      final access = await askMe.me();
      final history = access.canAsk ? await askMe.history() : null;
      if (!mounted) return;
      setState(() {
        _access = access;
        _turns
          ..clear()
          ..addAll([
            for (final answer in (history?.items ?? const <AskMeAnswer>[]).reversed)
              _Turn(answer.question, answer: answer),
          ]);
      });
      _toBottom();
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  void _toBottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
  });

  Future<void> _send() async {
    final question = _text.text.trim();
    if (question.isEmpty) return;
    final askMe = _askMe;
    final turn = _Turn(question);
    setState(() {
      _turns.add(turn);
      _text.clear();
    });
    _toBottom();
    try {
      final answer = await askMe.ask(question, language: _language);
      if (mounted) setState(() => turn.answer = answer);
    } catch (error) {
      if (mounted) setState(() => turn.error = error);
    }
    _toBottom();
  }

  Future<void> _rate(_Turn turn, int rating) async {
    final answer = turn.answer!;
    final askMe = _askMe;
    var reason = '';
    if (rating == -1) {
      final given = await promptText(
        context,
        title: 'What was wrong?',
        label: 'Reason (optional)',
        action: 'Send',
      );
      if (given == null) return;
      reason = given;
    }
    try {
      final rated = await askMe.rate(answer.id, rating, reason: reason);
      if (mounted) setState(() => turn.answer = rated);
    } catch (error) {
      if (mounted) showFailure(context, error);
    }
  }

  Future<void> _consent(bool allowed) async {
    try {
      final access = await _askMe.setTrainingConsent(allowed);
      if (mounted) setState(() => _access = access);
    } catch (error) {
      if (mounted) showFailure(context, error);
    }
  }

  Future<void> _open(AskMeSource source) async {
    final uri = Uri.tryParse(source.url);
    if (uri == null || !await widget.openSource(uri)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(source.url)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final access = _access;
    if (TgcgBackend.of(context) == null) {
      return const TgcgEmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'Connect to the TGCG server',
        message: 'Sign in with a server account to use Ask Me.',
      );
    }
    if (_error != null) {
      return Center(
        child: TgcgEmptyState(
          icon: Icons.cloud_off_outlined,
          title: 'Ask Me could not be loaded',
          message: failureMessage(_error!),
          action: TextButton(onPressed: _load, child: const Text('Try again')),
        ),
      );
    }
    if (access == null) return const Center(child: CircularProgressIndicator());
    if (!access.canAsk) {
      return const Center(
        child: TgcgEmptyState(
          icon: Icons.record_voice_over_outlined,
          title: 'Ask Me is not open yet',
          message: 'Please check back soon.',
        ),
      );
    }
    final busy = _turns.any((turn) => turn.sending);
    return Column(
      children: [
        // Every language in view, so speakers see their own at once.
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final language in AskMeLanguage.values)
                ChoiceChip(
                  label: Text(language.label),
                  visualDensity: VisualDensity.compact,
                  selected: _language == language,
                  onSelected: (_) => setState(() => _language = language),
                ),
            ],
          ),
        ),
        if (access.trainingOk == null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
            child: TgcgSectionCard(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'May TGCG use your questions to improve its own AI? Your name is never attached.',
                    style: TextStyle(color: TgcgColors.ink),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      FilledButton(onPressed: () => _consent(true), child: const Text('Yes')),
                      OutlinedButton(onPressed: () => _consent(false), child: const Text('No')),
                    ],
                  ),
                ],
              ),
            ),
          ),
        Expanded(
          child: _turns.isEmpty
              ? const Center(
                  child: TgcgEmptyState(
                    icon: Icons.record_voice_over_outlined,
                    title: 'Ask me anything',
                    message: "About the government's work, or how to vote.",
                  ),
                )
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                  itemCount: _turns.length,
                  itemBuilder: (context, index) => _TurnView(
                    turn: _turns[index],
                    onRate: (rating) => _rate(_turns[index], rating),
                    onSource: _open,
                  ),
                ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          decoration: const BoxDecoration(
            color: TgcgColors.surface,
            border: Border(top: BorderSide(color: TgcgColors.border)),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _text,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  inputFormatters: [LengthLimitingTextInputFormatter(1000)],
                  onSubmitted: (_) => busy ? null : _send(),
                  decoration: const InputDecoration(
                    hintText: "Ask about the government's work or voting",
                  ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton.filled(
                tooltip: 'Ask',
                onPressed: busy ? null : _send,
                icon: const Icon(Icons.send_rounded),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TurnView extends StatelessWidget {
  const _TurnView({required this.turn, required this.onRate, required this.onSource});

  final _Turn turn;
  final ValueChanged<int> onRate;
  final ValueChanged<AskMeSource> onSource;

  @override
  Widget build(BuildContext context) {
    final answer = turn.answer;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 520),
            margin: const EdgeInsets.only(left: 48, bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: TgcgColors.primary,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(turn.question, style: const TextStyle(color: Colors.white)),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 560),
            margin: const EdgeInsets.only(right: 32, bottom: 14),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            decoration: BoxDecoration(
              color: TgcgColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: TgcgColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.record_voice_over_outlined, size: 15, color: TgcgColors.primary),
                    SizedBox(width: 6),
                    Text(
                      'TGCG Ask Me · AI',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: TgcgColors.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                if (turn.sending)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                  )
                else if (turn.error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      failureMessage(turn.error!),
                      style: const TextStyle(color: TgcgColors.danger),
                    ),
                  )
                else ...[
                  Text(
                    answer!.answer,
                    style: TextStyle(
                      color: answer.isAnswered ? TgcgColors.ink : TgcgColors.muted,
                      height: 1.4,
                    ),
                  ),
                  if (answer.sources.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final source in answer.sources)
                          ActionChip(
                            avatar: const Icon(Icons.link_rounded, size: 16),
                            label: Text('Source: ${_host(source.url)}'),
                            onPressed: () => onSource(source),
                          ),
                      ],
                    ),
                  ],
                  if (answer.isAnswered)
                    Row(
                      children: [
                        IconButton(
                          tooltip: 'Helpful',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => onRate(1),
                          icon: Icon(
                            answer.rating == 1 ? Icons.thumb_up_alt_rounded : Icons.thumb_up_alt_outlined,
                            size: 18,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Not helpful',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => onRate(-1),
                          icon: Icon(
                            answer.rating == -1
                                ? Icons.thumb_down_alt_rounded
                                : Icons.thumb_down_alt_outlined,
                            size: 18,
                          ),
                        ),
                      ],
                    )
                  else
                    const SizedBox(height: 6),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

String _host(String url) {
  final host = Uri.tryParse(url)?.host ?? url;
  return host.startsWith('www.') ? host.substring(4) : host;
}
