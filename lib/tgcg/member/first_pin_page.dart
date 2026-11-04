import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/api_client.dart';
import '../api/backend.dart';
import '../ui/tgcg_design.dart';

/// A member who signed in with a first password others know (their VIN, from
/// a group's list) chooses their own 6-digit PIN before anything else; the
/// server refuses everything until they do. Pops true once it is changed,
/// false if they sign out instead.
class FirstPinPage extends StatefulWidget {
  const FirstPinPage({super.key, required this.firstPassword});

  /// What they signed in with, sent as the current password.
  final String firstPassword;

  @override
  State<FirstPinPage> createState() => _FirstPinPageState();
}

class _FirstPinPageState extends State<FirstPinPage> {
  final _pin = TextEditingController();
  final _again = TextEditingController();
  bool _busy = false;
  Map<String, String> _errors = {};

  @override
  void dispose() {
    _pin.dispose();
    _again.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    final errors = {
      if (!RegExp(r'^\d{6}$').hasMatch(_pin.text)) 'new_password': 'Choose 6 digits.',
      if (_again.text != _pin.text) 'again': 'The two PINs do not match.',
    };
    setState(() => _errors = errors);
    if (errors.isNotEmpty) return;
    final auth = TgcgBackend.of(context)!.auth;
    final navigator = Navigator.of(context);
    setState(() => _busy = true);
    try {
      await auth.changePassword(current: widget.firstPassword, newPassword: _pin.text);
      if (mounted) navigator.pop(true);
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
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    child: Scaffold(
      appBar: AppBar(automaticallyImplyLeading: false, title: const Text('Choose your own PIN')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
          children: [
            const Text(
              'You signed in with your VIN, which is on the list your group gave TGCG. '
              'Choose a 6-digit PIN only you know. From now on you sign in with your VIN '
              'and this PIN.',
              style: TextStyle(color: TgcgColors.muted, height: 1.4),
            ),
            const SizedBox(height: 16),
            if (_errors['general'] case final general?)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(general, style: const TextStyle(color: TgcgColors.danger)),
              ),
            TextField(
              controller: _pin,
              obscureText: true,
              autofocus: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: 'New 6-digit PIN',
                errorText: _errors['new_password'],
              ),
            ),
            TextField(
              controller: _again,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onSubmitted: (_) => _save(),
              decoration: InputDecoration(labelText: 'New PIN again', errorText: _errors['again']),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Save my PIN'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy ? null : () => Navigator.of(context).pop(false),
              child: const Text('Sign out'),
            ),
          ],
        ),
      ),
    ),
  );
}
