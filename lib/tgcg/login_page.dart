import 'package:flutter/material.dart';

import 'api/api_client.dart';
import 'api/backend.dart';
import 'app.dart';
import 'member/forgot_pin_page.dart';
import 'member/member_registration_page.dart';
import 'session.dart';
import 'ui/tgcg_design.dart';

/// The first page: the TGCG poster and welcome, then sign-in against the
/// server. On a phone the welcome comes first and "Sign in" opens the form;
/// on a wide screen they stand side by side.
class TgcgLoginPage extends StatefulWidget {
  const TgcgLoginPage({super.key});

  @override
  State<TgcgLoginPage> createState() => _TgcgLoginPageState();
}

class _TgcgLoginPageState extends State<TgcgLoginPage> {
  final accessIdController = TextEditingController();
  final passwordController = TextEditingController();

  bool showForm = false;
  bool obscurePassword = true;
  bool rememberDevice = true;
  bool signingIn = false;
  String? serverError;

  @override
  void dispose() {
    accessIdController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    final services = TgcgBackend.of(context)!;
    final identifier = accessIdController.text.trim();
    if (identifier.isEmpty || passwordController.text.isEmpty) {
      setState(() => serverError = 'Enter your access ID or phone number and password.');
      return;
    }
    setState(() {
      signingIn = true;
      serverError = null;
    });
    try {
      final user = await services.auth.login(
        identifier: identifier,
        password: passwordController.text,
      );
      if (!mounted) return;
      if (user.usesMemberApp) {
        TgcgSession.of(context, listen: false).signInMember(
          fullName: user.fullName,
          membershipNumber: user.membershipNumber ?? user.accessId,
          waitingRole: user.roleAwaitingVerification,
        );
        return;
      }
      if (user.roleAwaitingVerification case final role?) {
        // An agent or observer account that belongs to no member.
        await services.auth.logout();
        setState(() => serverError = 'This $role account cannot work yet. Agents and observers '
            'must be members whose identity a coordinator has checked. Ask your coordinator.');
        return;
      }
      if (user.role == null && user.capabilities.isEmpty) {
        await services.auth.logout();
        setState(() => serverError = 'This account type cannot use the operations app.');
        return;
      }
      // A fixed role, or a member's appointments: the server says what it may do.
      TgcgSession.of(context, listen: false).signInFromServer(
        role: user.role,
        fullName: user.fullName,
        accessId: user.accessId,
        scope: user.workingScope,
        capabilities: user.capabilities,
        grants: user.access,
        supervises: user.supervises,
        membershipNumber: user.membershipNumber ?? (user.isMember ? user.accessId : null),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => serverError = error.isUnauthorized
          ? 'Wrong access ID, phone number or password. After 5 failed attempts '
              'the account locks for 15 minutes.'
          : error.message);
    } finally {
      if (mounted) setState(() => signingIn = false);
    }
  }

  void _register() => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const MemberRegistrationPage()),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= 980) {
                return Row(
                  children: [
                    const Expanded(
                      flex: 10,
                      child: Padding(padding: EdgeInsets.all(18), child: Center(child: _Poster())),
                    ),
                    Expanded(flex: 13, child: _formPanel(welcome: true)),
                  ],
                );
              }
              if (!showForm) return _phoneWelcome(constraints);
              return ListView(
                padding: const EdgeInsets.all(18),
                children: [
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Back',
                        onPressed: () => setState(() => showForm = false),
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                      const SizedBox(width: 4),
                      const Expanded(child: _Brand()),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _formPanel(),
                ],
              );
            },
          ),
        ),
      );

  /// A phone's first page: the poster, the welcome, and the two ways in.
  Widget _phoneWelcome(BoxConstraints constraints) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: constraints.maxHeight * .6),
              child: const _Poster(),
            ),
          ),
          const SizedBox(height: 18),
          const _WelcomeNote(),
          const SizedBox(height: 18),
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: () => setState(() => showForm = true),
              icon: const Icon(Icons.login_rounded),
              label: const Text('Sign in'),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _register,
            icon: const Icon(Icons.person_add_alt_1_rounded),
            label: const Text('New member? Register with your PVC'),
          ),
        ],
      );

  Widget _formPanel({bool welcome = false}) => Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: welcome ? 48 : 4, vertical: welcome ? 30 : 0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (welcome) ...[const _WelcomeNote(), const SizedBox(height: 28)],
                const Text(
                  'Sign in to your account',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: TgcgApp.ink,
                    letterSpacing: -.5,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Members use their phone number and 6-digit PIN. Coordinators and agents use '
                  'their access ID and password.',
                  style: TextStyle(color: TgcgApp.muted, fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: accessIdController,
                  autofillHints: const [AutofillHints.username],
                  textInputAction: TextInputAction.next,
                  decoration: _decoration(
                    'Access ID or phone number',
                    'e.g. TGCG-KD-0001 or 0803 123 4567',
                    Icons.badge_outlined,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passwordController,
                  obscureText: obscurePassword,
                  onSubmitted: (_) => _signIn(),
                  autofillHints: const [AutofillHints.password],
                  decoration: _decoration(
                    'Password or PIN',
                    'Members use their 6-digit PIN',
                    Icons.lock_outline_rounded,
                  ).copyWith(
                    suffixIcon: IconButton(
                      onPressed: () => setState(() => obscurePassword = !obscurePassword),
                      icon: Icon(
                        obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Checkbox(
                      value: rememberDevice,
                      onChanged: (value) => setState(() => rememberDevice = value ?? false),
                    ),
                    const Expanded(
                      child: Text(
                        'Remember this device',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const ForgotPinPage()),
                      ),
                      child: const Text('Forgot PIN?'),
                    ),
                  ],
                ),
                if (serverError != null) ...[
                  const SizedBox(height: 4),
                  Container(
                    key: const ValueKey('login-error'),
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: TgcgColors.danger.withValues(alpha: .08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: TgcgColors.danger.withValues(alpha: .3)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.error_outline_rounded, color: TgcgColors.danger, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            serverError!,
                            style: const TextStyle(color: TgcgColors.ink, height: 1.35),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: FilledButton.icon(
                    onPressed: signingIn ? null : _signIn,
                    icon: signingIn
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.login_rounded),
                    label: Text(signingIn ? 'Signing in…' : 'Sign in'),
                    style: FilledButton.styleFrom(
                      backgroundColor: TgcgApp.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      textStyle: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: signingIn ? null : _register,
                    icon: const Icon(Icons.person_add_alt_1_rounded),
                    label: const Text('New member? Register with your PVC'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  InputDecoration _decoration(String label, String hint, IconData icon) => InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFDDDFE5)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: TgcgApp.primary, width: 1.5),
        ),
      );
}

/// The TGCG poster (assets/brand/login_poster.webp): the logo, the
/// president and the programme, as designed.
class _Poster extends StatelessWidget {
  const _Poster();

  @override
  Widget build(BuildContext context) => AspectRatio(
        // The poster's own shape (1086 x 1448), so its place is kept while it
        // loads and the welcome below does not jump.
        aspectRatio: 1086 / 1448,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: const Color(0xFF000E2F),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Image.asset(
            'assets/brand/login_poster.webp',
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
            semanticLabel: 'TGCG-EMCOP, the Election Monitoring and Collation Programme of '
                'The Game Changer Group',
          ),
        ),
      );
}

/// The logo (assets/brand/tgcg_logo.png) and the programme's name.
class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) => const Row(
        children: [
          TgcgLogo(size: 44),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'TGCG-EMCOP',
                  style: TextStyle(
                    color: TgcgApp.ink,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .8,
                  ),
                ),
                Text(
                  'Election Monitoring & Collation Programme',
                  style: TextStyle(color: TgcgApp.muted, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      );
}

class _WelcomeNote extends StatelessWidget {
  const _WelcomeNote();

  @override
  Widget build(BuildContext context) => const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Brand(),
          SizedBox(height: 16),
          Text(
            'Welcome to TGCG-EMCOP',
            style: TextStyle(
              color: TgcgApp.ink,
              fontSize: 24,
              fontWeight: FontWeight.w900,
              height: 1.15,
            ),
          ),
          SizedBox(height: 8),
          Text(
            "The Game Changer Group's election monitoring and collation programme. Sign in to "
            'report from your polling unit, follow results and work with your coordinators. '
            'New members register with their voter card (PVC).',
            style: TextStyle(color: TgcgApp.muted, fontSize: 14, height: 1.45),
          ),
        ],
      );
}
