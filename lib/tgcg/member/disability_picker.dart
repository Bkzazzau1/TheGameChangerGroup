import 'package:flutter/material.dart';

import '../api/member_repository.dart';
import '../ui/tgcg_design.dart';

/// Chips for the kinds of disability, any number of them, and a box for the
/// member's own words when "Other" is chosen.
class DisabilityChoices extends StatelessWidget {
  const DisabilityChoices({
    super.key,
    required this.kinds,
    required this.onChanged,
    required this.other,
    this.otherError,
  });

  /// Codes from [disabilityKinds].
  final List<String> kinds;
  final ValueChanged<List<String>> onChanged;
  final TextEditingController other;
  final String? otherError;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final (code, label) in disabilityKinds)
                FilterChip(
                  label: Text(label),
                  selected: kinds.contains(code),
                  onSelected: (on) => onChanged([
                    for (final (kind, _) in disabilityKinds)
                      if (kind == code ? on : kinds.contains(kind)) kind,
                  ]),
                ),
            ],
          ),
          if (kinds.contains('other')) ...[
            const SizedBox(height: 10),
            TextField(
              controller: other,
              maxLength: 100,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Which other disability',
                errorText: otherError,
              ),
            ),
          ],
        ],
      );
}

/// Chooses the member's disabilities; pops (codes, words for other), or
/// nothing when cancelled. Saving none takes them all back.
class DisabilityDialog extends StatefulWidget {
  const DisabilityDialog({super.key, required this.kinds, required this.other});

  final List<String> kinds;
  final String other;

  @override
  State<DisabilityDialog> createState() => _DisabilityDialogState();
}

class _DisabilityDialogState extends State<DisabilityDialog> {
  late var _kinds = [...widget.kinds];
  late final _other = TextEditingController(text: widget.other);
  String? _otherError;

  @override
  void dispose() {
    _other.dispose();
    super.dispose();
  }

  void _save() {
    final other = _other.text.trim();
    if (_kinds.contains('other') && other.isEmpty) {
      setState(() => _otherError = 'Say which other disability.');
      return;
    }
    Navigator.pop(context, (_kinds, _kinds.contains('other') ? other : ''));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Disability'),
        content: SingleChildScrollView(
          child: DisabilityChoices(
            kinds: _kinds,
            other: _other,
            otherError: _otherError,
            onChanged: (kinds) => setState(() {
              _kinds = kinds;
              _otherError = null;
            }),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: TgcgColors.primary),
            onPressed: _save,
            child: const Text('Save'),
          ),
        ],
      );
}
