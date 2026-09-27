import 'dart:async';

import 'package:flutter/material.dart';

import '../domain/models.dart';
import '../offline/offline_persistence.dart';
import '../session.dart';
import '../ui/tgcg_design.dart';
import 'device_evidence_service.dart';

class EvidenceCapturePage extends StatefulWidget {
  const EvidenceCapturePage({super.key});

  @override
  State<EvidenceCapturePage> createState() => _EvidenceCapturePageState();
}

class _EvidenceCapturePageState extends State<EvidenceCapturePage> {
  final _service = DeviceEvidenceService();
  final _reference = TextEditingController();
  final List<CapturedEvidence> _captured = [];
  bool _busy = false;
  bool _recording = false;

  @override
  void dispose() {
    _reference.dispose();
    unawaited(_service.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = TgcgSession.of(context);
    final offline = OfflinePersistence.of(context);
    final photos = _captured.where((item) => item.type == EvidenceType.photo).length;
    final videos = _captured.where((item) => item.type == EvidenceType.video).length;
    final audio = _captured.where((item) => item.type == EvidenceType.audio).length;
    final locations = _captured.where((item) => item.type == EvidenceType.location).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 36),
      children: [
        TgcgPageHeader(
          eyebrow: 'FIELD EVIDENCE',
          title: 'Evidence Capture',
          subtitle: '${session.scope.label}: capture and preserve field media with location and integrity metadata.',
          trailing: TgcgStatusPill(
            label: offline.pendingOutbox.isEmpty ? 'SYNCED' : '${offline.pendingOutbox.length} QUEUED',
            color: offline.pendingOutbox.isEmpty ? TgcgColors.success : TgcgColors.warning,
            icon: offline.pendingOutbox.isEmpty ? Icons.cloud_done_outlined : Icons.cloud_upload_outlined,
          ),
        ),
        const SizedBox(height: 18),
        LayoutBuilder(builder: (context, constraints) {
          final columns = constraints.maxWidth >= 900 ? 4 : constraints.maxWidth >= 520 ? 2 : 1;
          const gap = 12.0;
          final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              TgcgMetricCard(width: width, label: 'Photos', value: '$photos', detail: 'Captured images', icon: Icons.photo_camera_outlined, tone: TgcgMetricTone.info),
              TgcgMetricCard(width: width, label: 'Videos', value: '$videos', detail: 'Captured clips', icon: Icons.videocam_outlined, tone: TgcgMetricTone.ai),
              TgcgMetricCard(width: width, label: 'Audio', value: '$audio', detail: 'Voice evidence', icon: Icons.mic_none_rounded, tone: TgcgMetricTone.warning),
              TgcgMetricCard(width: width, label: 'Locations', value: '$locations', detail: 'GPS evidence', icon: Icons.location_on_outlined, tone: TgcgMetricTone.success),
            ],
          );
        }),
        const SizedBox(height: 16),
        LayoutBuilder(builder: (context, constraints) {
          final capture = _CapturePanel(
            busy: _busy,
            recording: _recording,
            reference: _reference,
            onPhoto: () => _capture(context, () => _service.capturePhoto()),
            onVideo: () => _capture(context, () => _service.captureVideo()),
            onLocation: () => _capture(context, () => _service.captureLocation()),
            onAudio: () => _toggleAudio(context),
          );
          final ledger = _EvidenceLedger(items: _captured);
          if (constraints.maxWidth < 980) {
            return Column(children: [capture, const SizedBox(height: 16), ledger]);
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 5, child: capture),
              const SizedBox(width: 16),
              Expanded(flex: 7, child: ledger),
            ],
          );
        }),
      ],
    );
  }

  Future<void> _toggleAudio(BuildContext context) async {
    if (_recording) {
      setState(() => _busy = true);
      try {
        final evidence = await _service.stopAudioRecording();
        if (evidence != null) await _save(context, evidence);
        if (mounted) setState(() => _recording = false);
      } catch (error) {
        _showError(error);
      } finally {
        if (mounted) setState(() => _busy = false);
      }
      return;
    }
    setState(() => _busy = true);
    try {
      await _service.startAudioRecording();
      if (mounted) setState(() => _recording = true);
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _capture(
    BuildContext context,
    Future<CapturedEvidence?> Function() action,
  ) async {
    setState(() => _busy = true);
    try {
      final evidence = await action();
      if (evidence != null) await _save(context, evidence);
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save(BuildContext context, CapturedEvidence evidence) async {
    final session = TgcgSession.of(context, listen: false);
    final offline = OfflinePersistence.of(context, listen: false);
    final id = 'EVD-${DateTime.now().microsecondsSinceEpoch}';
    await offline.persistMutation(
      entityType: 'evidence',
      entityId: id,
      mutationType: SyncMutationType.create,
      ownerId: session.accessId,
      scopeKey: session.scope.label,
      payload: {
        'id': id,
        'type': evidence.type.name,
        'fileName': evidence.fileName,
        'mimeType': evidence.mimeType,
        'contentHash': evidence.contentHash,
        'latitude': evidence.latitude,
        'longitude': evidence.longitude,
        'reference': _reference.text.trim().isEmpty ? null : _reference.text.trim(),
        'uploaderId': session.accessId,
        'createdAt': evidence.createdAt.toIso8601String(),
        'scope': session.scope.label,
      },
    );
    if (!mounted) return;
    setState(() => _captured.insert(0, evidence));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Evidence captured and queued securely.')),
    );
  }

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Capture failed: $error')),
    );
  }
}

class _CapturePanel extends StatelessWidget {
  const _CapturePanel({required this.busy, required this.recording, required this.reference, required this.onPhoto, required this.onVideo, required this.onLocation, required this.onAudio});
  final bool busy;
  final bool recording;
  final TextEditingController reference;
  final VoidCallback onPhoto;
  final VoidCallback onVideo;
  final VoidCallback onLocation;
  final VoidCallback onAudio;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Capture evidence',
        subtitle: 'Attach media to an incident, field report or result reference.',
        child: Column(
          children: [
            TextField(
              controller: reference,
              decoration: const InputDecoration(
                labelText: 'Incident / report / result reference',
                prefixIcon: Icon(Icons.link_rounded),
              ),
            ),
            const SizedBox(height: 16),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.45,
              children: [
                _CaptureAction(icon: Icons.photo_camera_outlined, label: 'Photo', detail: 'Camera image', enabled: !busy, onTap: onPhoto),
                _CaptureAction(icon: Icons.videocam_outlined, label: 'Video', detail: 'Up to 3 minutes', enabled: !busy, onTap: onVideo),
                _CaptureAction(icon: recording ? Icons.stop_circle_outlined : Icons.mic_none_rounded, label: recording ? 'Stop audio' : 'Audio', detail: recording ? 'Recording now' : 'Voice evidence', enabled: !busy, onTap: onAudio, active: recording),
                _CaptureAction(icon: Icons.my_location_rounded, label: 'Location', detail: 'GPS coordinates', enabled: !busy, onTap: onLocation),
              ],
            ),
            if (busy) ...[
              const SizedBox(height: 14),
              const LinearProgressIndicator(),
            ],
          ],
        ),
      );
}

class _CaptureAction extends StatelessWidget {
  const _CaptureAction({required this.icon, required this.label, required this.detail, required this.enabled, required this.onTap, this.active = false});
  final IconData icon;
  final String label;
  final String detail;
  final bool enabled;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) => Material(
        color: active ? TgcgColors.danger.withValues(alpha: .08) : TgcgColors.surfaceSoft,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: active ? TgcgColors.danger : TgcgColors.primary, size: 28),
                const SizedBox(height: 7),
                Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 2),
                Text(detail, textAlign: TextAlign.center, style: const TextStyle(color: TgcgColors.muted, fontSize: 10)),
              ],
            ),
          ),
        ),
      );
}

class _EvidenceLedger extends StatelessWidget {
  const _EvidenceLedger({required this.items});
  final List<CapturedEvidence> items;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Captured evidence',
        subtitle: 'Latest media preserved from this device session.',
        child: items.isEmpty
            ? const TgcgEmptyState(
                icon: Icons.perm_media_outlined,
                title: 'No evidence captured',
                message: 'Captured media will appear here.',
              )
            : Column(
                children: items.map((item) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: TgcgColors.primarySoft,
                    child: Icon(_icon(item.type), color: TgcgColors.primary),
                  ),
                  title: Text(item.fileName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text(_subtitle(item), maxLines: 2, overflow: TextOverflow.ellipsis),
                  trailing: TgcgStatusPill(label: item.contentHash == null ? 'CAPTURED' : 'HASHED', color: item.contentHash == null ? TgcgColors.info : TgcgColors.success, compact: true),
                )).toList(),
              ),
      );

  static IconData _icon(EvidenceType type) => switch (type) {
        EvidenceType.photo => Icons.photo_outlined,
        EvidenceType.video => Icons.videocam_outlined,
        EvidenceType.audio => Icons.mic_none_rounded,
        EvidenceType.location => Icons.location_on_outlined,
        EvidenceType.document => Icons.description_outlined,
        EvidenceType.resultForm => Icons.fact_check_outlined,
      };

  static String _subtitle(CapturedEvidence item) {
    if (item.latitude != null && item.longitude != null) {
      return '${item.latitude!.toStringAsFixed(6)}, ${item.longitude!.toStringAsFixed(6)}';
    }
    if (item.contentHash != null) {
      final hash = item.contentHash!;
      return '${item.mimeType} • ${hash.length > 24 ? '${hash.substring(0, 24)}…' : hash}';
    }
    return item.mimeType;
  }
}
