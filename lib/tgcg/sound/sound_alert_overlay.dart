import 'package:flutter/material.dart';

import '../ui/tgcg_design.dart';
import 'sound_alerts.dart';

/// Shows a danger alert's countdown above whatever is open on the phone,
/// with False alarm and Send now.
class SoundAlertOverlay extends StatefulWidget {
  const SoundAlertOverlay({super.key, required this.alerts, required this.child});

  final SoundAlerts alerts;
  final Widget child;

  @override
  State<SoundAlertOverlay> createState() => _SoundAlertOverlayState();
}

class _SoundAlertOverlayState extends State<SoundAlertOverlay> {
  OverlayEntry? _entry;

  @override
  void initState() {
    super.initState();
    widget.alerts.addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_) => _changed());
  }

  @override
  void didUpdateWidget(SoundAlertOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.alerts == widget.alerts) return;
    oldWidget.alerts.removeListener(_changed);
    widget.alerts.addListener(_changed);
  }

  void _changed() {
    if (!mounted) return;
    final alerting = widget.alerts.alert != null;
    if (alerting && _entry == null) {
      final entry = _entry = OverlayEntry(builder: (_) => _AlertCard(alerts: widget.alerts));
      Overlay.of(context, rootOverlay: true).insert(entry);
    } else if (!alerting) {
      _hide();
    }
  }

  void _hide() {
    _entry?.remove();
    _entry?.dispose();
    _entry = null;
  }

  @override
  void dispose() {
    widget.alerts.removeListener(_changed);
    _hide();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({required this.alerts});

  final SoundAlerts alerts;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: alerts,
        builder: (context, _) {
          final danger = alerts.alert;
          if (danger == null) return const SizedBox.shrink();
          final sending = alerts.state == SoundAlertsState.sending;
          final seconds = alerts.secondsLeft;
          final total = alerts.countdown.inSeconds;
          final share = total == 0 ? 0.0 : (seconds / total).clamp(0.0, 1.0);
          return Material(
            color: Colors.black54,
            child: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
                      decoration: BoxDecoration(
                        color: TgcgColors.surface,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.hearing_rounded, color: TgcgColors.danger, size: 40),
                          const SizedBox(height: 10),
                          Text(
                            '${danger.kind.label} heard',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: TgcgColors.ink,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            sending ? 'Sending the alert…' : 'Sending an alert in $seconds s',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: TgcgColors.muted, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 14),
                          LinearProgressIndicator(
                            value: sending ? null : share,
                            color: TgcgColors.danger,
                            backgroundColor: TgcgColors.border,
                            minHeight: 6,
                            borderRadius: BorderRadius.circular(3),
                          ),
                          const SizedBox(height: 18),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: sending ? null : alerts.falseAlarm,
                                  child: const Text('False alarm'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: FilledButton(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: TgcgColors.danger,
                                  ),
                                  onPressed: sending ? null : alerts.sendNow,
                                  child: const Text('Send now'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
}
