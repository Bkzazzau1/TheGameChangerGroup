import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/api_client.dart';
import '../api/backend.dart';
import '../session.dart';
import '../ui/tgcg_design.dart';
import 'member_registration_page.dart' show normalizeNigerianPhone;

/// Members who forgot their PIN (or were registered by a coordinator and have
/// none yet) get a code by SMS and choose a new PIN.
class ForgotPinPage extends StatefulWidget {
  const ForgotPinPage({super.key});

  @override
  State<ForgotPinPage> createState() => _ForgotPinPageState();
}

class _ForgotPinPageState extends State<ForgotPinPage> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  final _pin = TextEditingController();
  final _pinAgain = TextEditingController();
  String? _sentTo;
  bool _busy = false;
  Map<String, String> _errors = {};

  @override
  void dispose() {
    for (final controller in [_phone, _code, _pin, _pinAgain]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _errors = {};
    });
    try {
      await action();
    } on ApiException catch (error) {
      if (mounted) {
        setState(() => _errors = {
              for (final entry in error.fieldErrors.entries) entry.key: entry.value.first,
              if (error.fieldErrors.isEmpty) 'general': error.message,
            });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendCode() => _run(() async {
        final phone = normalizeNigerianPhone(_phone.text)!;
        await TgcgBackend.of(context)!.member.requestPinCode(phone);
        if (mounted) setState(() => _sentTo = phone);
      });

  Future<void> _setPin() {
    final session = TgcgSession.of(context, listen: false);
    final navigator = Navigator.of(context);
    final members = TgcgBackend.of(context)!.member;
    return _run(() async {
      final card = await members.setPin(phone: _sentTo!, code: _code.text.trim(), pin: _pin.text);
      navigator.popUntil((route) => route.isFirst);
      session.signInMember(fullName: card.fullName, membershipNumber: card.membershipNumber);
    });
  }

  bool get _pinReady =>
      RegExp(r'^\d{6}$').hasMatch(_code.text.trim()) &&
      RegExp(r'^\d{6}$').hasMatch(_pin.text) &&
      _pin.text == _pinAgain.text;

  @override
  Widget build(BuildContext context) {
    final phoneValid = normalizeNigerianPhone(_phone.text) != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Set a new PIN')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              _sentTo == null
                  ? 'Enter the phone number you registered with. We will text you a code.'
                  : 'Enter the code we sent to $_sentTo and choose a new 6-digit PIN.',
              style: const TextStyle(color: TgcgColors.muted, height: 1.4),
            ),
            const SizedBox(height: 14),
            if (_errors['general'] != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(_errors['general']!, style: const TextStyle(color: TgcgColors.danger)),
              ),
            if (_sentTo == null) ...[
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Phone number',
                  hintText: '0803 123 4567',
                  errorText: _errors['phone_number'],
                ),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: phoneValid && !_busy ? _sendCode : null,
                icon: const Icon(Icons.sms_outlined),
                label: const Text('Send code'),
              ),
            ] else ...[
              TextField(
                controller: _code,
                keyboardType: TextInputType.number,
                maxLength: 6,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(labelText: 'Code from the SMS', errorText: _errors['code']),
              ),
              TextField(
                controller: _pin,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(labelText: 'New PIN', errorText: _errors['pin']),
              ),
              TextField(
                controller: _pinAgain,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'New PIN again',
                  errorText: _pinAgain.text.length == 6 && _pinAgain.text != _pin.text
                      ? 'The two PINs do not match.'
                      : null,
                ),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _pinReady && !_busy ? _setPin : null,
                child: const Text('Save PIN and sign in'),
              ),
              TextButton(
                onPressed: _busy ? null : () => setState(() => _sentTo = null),
                child: const Text('Use a different number'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
