import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/api_client.dart';
import '../api/backend.dart';
import '../session.dart';
import '../ui/tgcg_design.dart';

/// Changes the signed-in account's PIN (members) or password (staff).
Future<void> showChangePin(BuildContext context) async {
  final session = TgcgSession.of(context, listen: false);
  final pin = session.isMember || session.role == null;
  final messenger = ScaffoldMessenger.of(context);
  final changed = await showDialog<bool>(
    context: context,
    builder: (_) => ChangePinDialog(pin: pin),
  );
  if (changed == true) {
    messenger.showSnackBar(
      SnackBar(content: Text(pin ? 'Your PIN was changed.' : 'Your password was changed.')),
    );
  }
}

/// The current PIN or password, then the new one twice. The server signs out
/// every other device; this one carries on.
class ChangePinDialog extends StatefulWidget {
  const ChangePinDialog({super.key, required this.pin});

  /// A member's 6-digit PIN rather than a staff password.
  final bool pin;

  @override
  State<ChangePinDialog> createState() => _ChangePinDialogState();
}

class _ChangePinDialogState extends State<ChangePinDialog> {
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _again = TextEditingController();
  bool _busy = false;
  Map<String, String> _errors = {};

  @override
  void dispose() {
    for (final controller in [_current, _new, _again]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final pin = widget.pin;
    final errors = {
      if (_current.text.isEmpty) 'current_password': 'Enter what you sign in with now.',
      if (pin && !RegExp(r'^\d{6}$').hasMatch(_new.text)) 'new_password': 'Choose 6 digits.',
      if (!pin && _new.text.isEmpty) 'new_password': 'Choose a new password.',
      if (_again.text != _new.text) 'again': 'The two do not match.',
    };
    setState(() => _errors = errors);
    if (errors.isNotEmpty) return;
    final auth = TgcgBackend.of(context)!.auth;
    final navigator = Navigator.of(context);
    setState(() => _busy = true);
    try {
      await auth.changePassword(current: _current.text, newPassword: _new.text);
      navigator.pop(true);
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _errors = {
            for (final entry in error.fieldErrors.entries) entry.key: entry.value.first,
            if (error.fieldErrors.isEmpty) 'general': error.message,
          };
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pin = widget.pin;
    final digits = pin ? [FilteringTextInputFormatter.digitsOnly] : null;
    return AlertDialog(
      title: Text(pin ? 'Change your PIN' : 'Change your password'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_errors['general'] case final general?)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(general, style: const TextStyle(color: TgcgColors.danger)),
                ),
              TextField(
                controller: _current,
                obscureText: true,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: pin ? 'Current PIN or password' : 'Current password',
                  errorText: _errors['current_password'],
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _new,
                obscureText: true,
                keyboardType: pin ? TextInputType.number : null,
                maxLength: pin ? 6 : null,
                inputFormatters: digits,
                decoration: InputDecoration(
                  labelText: pin ? 'New 6-digit PIN' : 'New password',
                  errorText: _errors['new_password'],
                ),
              ),
              TextField(
                controller: _again,
                obscureText: true,
                keyboardType: pin ? TextInputType.number : null,
                maxLength: pin ? 6 : null,
                inputFormatters: digits,
                onSubmitted: (_) => _save(),
                decoration: InputDecoration(
                  labelText: pin ? 'New PIN again' : 'New password again',
                  errorText: _errors['again'],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(pin ? 'Change PIN' : 'Change password'),
        ),
      ],
    );
  }
}
