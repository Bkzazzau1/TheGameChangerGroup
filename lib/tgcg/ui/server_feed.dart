import 'dart:async';

import 'package:flutter/material.dart';

import '../access/access_widgets.dart' show formatMoment;
import '../sync/server_records.dart';
import 'tgcg_design.dart';

/// Where a page's records come from, and a way to load them again.
class ServerFeedStatus extends StatelessWidget {
  const ServerFeedStatus({super.key, required this.records});

  final ServerRecords<Object?> records;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: records,
        builder: (context, _) {
          if (!records.isLive) {
            return const TgcgStatusPill(
              label: 'DEMO FEED',
              color: TgcgColors.warning,
              icon: Icons.science_outlined,
            );
          }
          final loadedAt = records.loadedAt;
          final failed = records.loadError != null;
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TgcgStatusPill(
                label: failed ? 'NOT UPDATED' : 'LIVE FROM SERVER',
                color: failed ? TgcgColors.danger : TgcgColors.success,
                icon: failed ? Icons.cloud_off_rounded : Icons.circle,
              ),
              if (loadedAt != null)
                Text(
                  'Updated ${formatMoment(loadedAt)}',
                  style: const TextStyle(color: TgcgColors.muted, fontSize: 11),
                ),
              IconButton(
                tooltip: 'Load again',
                onPressed: records.loading ? null : () => unawaited(records.refresh()),
                icon: records.loading
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded),
              ),
            ],
          );
        },
      );
}

/// Says why the server's records could not be loaded, when they could not.
class ServerLoadError extends StatelessWidget {
  const ServerLoadError({super.key, required this.records, required this.what});

  final ServerRecords<Object?> records;

  /// What could not be loaded, as the start of a sentence ("Results").
  final String what;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: records,
        builder: (context, _) {
          final error = records.loadError;
          if (!records.isLive || error == null) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(top: 14),
            child: ServerNote(
              icon: Icons.cloud_off_rounded,
              text: '$what could not be loaded from the server: $error',
            ),
          );
        },
      );
}

/// A quiet note: something to know about the records on a page.
class ServerNote extends StatelessWidget {
  const ServerNote({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: TgcgColors.surfaceSoft,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: TgcgColors.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 17, color: TgcgColors.primaryMid),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(color: TgcgColors.ink, fontSize: 10.5, height: 1.4),
              ),
            ),
          ],
        ),
      );
}

/// Keeps a page's server records current while it is open: loads them when
/// the page opens (unless they are fresh) and every minute after.
mixin ServerAutoRefresh<T extends StatefulWidget> on State<T> {
  /// The stores whose records the page shows.
  List<ServerRecords<Object?>> refreshedRecords(BuildContext context);

  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh(const Duration(seconds: 20)));
    _refreshTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _refresh(const Duration(seconds: 50)),
    );
  }

  void _refresh(Duration age) {
    if (!mounted) return;
    for (final records in refreshedRecords(context)) {
      if (records.isLive) unawaited(records.refreshIfOlderThan(age));
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }
}
