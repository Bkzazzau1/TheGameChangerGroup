import 'package:flutter/material.dart';

import '../access/access_widgets.dart' show failureMessage, formatMoment;
import '../api/backend.dart';
import '../api/messaging_repository.dart';
import '../ui/tgcg_design.dart';

/// Messages sent to the signed-in member, on any channel, newest first.
class InboxPage extends StatefulWidget {
  const InboxPage({super.key});

  @override
  State<InboxPage> createState() => _InboxPageState();
}

class _InboxPageState extends State<InboxPage> {
  Future<List<InboxMessage>>? _messages;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _messages ??= TgcgBackend.of(context)?.messaging.inbox();
  }

  void _reload() => setState(() {
    _messages = TgcgBackend.of(context)?.messaging.inbox();
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: TgcgColors.canvas,
    appBar: AppBar(
      title: const Text('Messages'),
      actions: [
        IconButton(tooltip: 'Refresh', onPressed: _reload, icon: const Icon(Icons.refresh_rounded)),
      ],
    ),
    body: FutureBuilder<List<InboxMessage>>(
      future: _messages,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: TgcgEmptyState(
              icon: Icons.cloud_off_outlined,
              title: 'Messages could not be loaded',
              message: failureMessage(snapshot.error!),
              action: OutlinedButton(onPressed: _reload, child: const Text('Try again')),
            ),
          );
        }
        final messages = snapshot.data;
        if (messages == null) return const Center(child: CircularProgressIndicator());
        if (messages.isEmpty) {
          return const Center(
            child: TgcgEmptyState(
              icon: Icons.mark_email_read_outlined,
              title: 'No messages',
              message: 'Messages from TGCG appear here.',
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: messages.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final message = messages[index];
            return TgcgSectionCard(
              title: message.title.isEmpty ? 'TGCG' : message.title,
              subtitle: message.createdAt == null ? null : formatMoment(message.createdAt!),
              child: SelectableText(message.body, style: const TextStyle(height: 1.4)),
            );
          },
        );
      },
    ),
  );
}

/// Opens the inbox; for app bars.
class InboxButton extends StatelessWidget {
  const InboxButton({super.key, this.color});

  final Color? color;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Messages',
    onPressed: () => Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const InboxPage()),
    ),
    icon: Icon(Icons.mail_outline_rounded, color: color),
  );
}
