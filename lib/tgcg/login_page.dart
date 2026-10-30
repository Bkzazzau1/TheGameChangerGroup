import 'package:flutter/material.dart';

import 'api/api_client.dart';
import 'api/backend.dart';
import 'member/forgot_pin_page.dart';
import 'member/member_registration_page.dart';
import 'member/referral.dart';
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

/// Who is signing in. Both go to the same sign-in on the server; this decides
/// what the form asks for, and the keyboard it opens.
enum _SignInAs { member, staff }

class _TgcgLoginPageState extends State<TgcgLoginPage> {
  final accessIdController = TextEditingController();
  final passwordController = TextEditingController();

  bool showForm = false;
  _SignInAs signInAs = _SignInAs.member;
  bool obscurePassword = true;
  bool rememberDevice = true;
  bool signingIn = false;
  String? serverError;

  @override
  void initState() {
    super.initState();
    // Opened from a member's referral link: go straight to joining.
    final code = referralFromLink();
    if (code != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => MemberRegistrationPage(referralCode: code)),
        );
      });
    }
  }

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
      setState(() => serverError = signInAs == _SignInAs.member
          ? 'Enter your phone number and PIN.'
          : 'Enter your access ID or phone number and password.');
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
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
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
                  const SizedBox(height: 16),
                  _formPanel(),
                ],
              );
            },
          ),
        ),
      );

  /// A phone's first page: the poster and the welcome scroll, and the two
  /// ways in stay on screen, however small the phone.
  Widget _phoneWelcome(BoxConstraints constraints) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: constraints.maxHeight * .5),
                    child: const _Poster(),
                  ),
                ),
                const SizedBox(height: 16),
                const _WelcomeNote(),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            decoration: const BoxDecoration(
              color: TgcgColors.surface,
              border: Border(top: BorderSide(color: TgcgColors.border)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton.icon(
                  onPressed: () => setState(() => showForm = true),
                  icon: const Icon(Icons.login_rounded),
                  label: const Text('Sign in'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _register,
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                  label: const Text('New member? Register with your PVC'),
                ),
              ],
            ),
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
                const Text('Sign in to your account', style: TgcgType.display),
                const SizedBox(height: 14),
                _SignInChoice(
                  value: signInAs,
                  onChanged: (value) => setState(() {
                    signInAs = value;
                    serverError = null;
                  }),
                ),
                const SizedBox(height: 16),
                TextField(
                  key: ValueKey('sign-in-id-${signInAs.name}'),
                  controller: accessIdController,
                  autofillHints: const [AutofillHints.username],
                  keyboardType:
                      signInAs == _SignInAs.member ? TextInputType.phone : TextInputType.text,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: signInAs == _SignInAs.member
                        ? 'Phone number'
                        : 'Access ID or phone number',
                    hintText: signInAs == _SignInAs.member
                        ? 'e.g. 0803 123 4567'
                        : 'e.g. TGCG-KD-0001',
                    prefixIcon: Icon(
                      signInAs == _SignInAs.member ? Icons.phone_outlined : Icons.badge_outlined,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: ValueKey('sign-in-secret-${signInAs.name}'),
                  controller: passwordController,
                  obscureText: obscurePassword,
                  onSubmitted: (_) => _signIn(),
                  autofillHints: const [AutofillHints.password],
                  keyboardType:
                      signInAs == _SignInAs.member ? TextInputType.number : TextInputType.text,
                  decoration: InputDecoration(
                    labelText: signInAs == _SignInAs.member ? 'PIN' : 'Password',
                    hintText: signInAs == _SignInAs.member ? 'Your 6-digit PIN' : null,
                    helperText: signInAs == _SignInAs.member
                        ? 'Registered by someone else? Use your phone number until you set a PIN.'
                        : null,
                    helperMaxLines: 2,
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                    suffixIcon: IconButton(
                      tooltip: obscurePassword ? 'Show' : 'Hide',
                      onPressed: () => setState(() => obscurePassword = !obscurePassword),
                      icon: Icon(
                        obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Checkbox(
                      value: rememberDevice,
                      onChanged: (value) => setState(() => rememberDevice = value ?? false),
                    ),
                    const Expanded(
                      child: Text('Remember this device', style: TgcgType.bodyStrong),
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
                  TgcgNotice(
                    key: const ValueKey('login-error'),
                    icon: Icons.error_outline_rounded,
                    color: TgcgColors.danger,
                    child: Text(serverError!),
                  ),
                ],
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
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
                  ),
                ),
                const SizedBox(height: 10),
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

}

/// Member or agent: two plain choices, saying what each one signs in with.
class _SignInChoice extends StatelessWidget {
  const _SignInChoice({required this.value, required this.onChanged});

  final _SignInAs value;
  final ValueChanged<_SignInAs> onChanged;

  @override
  Widget build(BuildContext context) => IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _Choice(
                title: 'Member',
                detail: 'Phone number and PIN',
                selected: value == _SignInAs.member,
                onTap: () => onChanged(_SignInAs.member),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _Choice(
                title: 'Agent or coordinator',
                detail: 'Access ID and password',
                selected: value == _SignInAs.staff,
                onTap: () => onChanged(_SignInAs.staff),
              ),
            ),
          ],
        ),
      );
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.title,
    required this.detail,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String detail;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: selected,
        child: Material(
          color: selected ? TgcgColors.primary : TgcgColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(TgcgRadius.md),
            side: BorderSide(color: selected ? TgcgColors.primary : TgcgColors.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TgcgType.bodyStrong.copyWith(
                      color: selected ? Colors.white : TgcgColors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    style: TgcgType.caption.copyWith(
                      color: selected ? TgcgColors.onNavyMuted : TgcgColors.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
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
            borderRadius: BorderRadius.circular(TgcgRadius.lg),
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
                    color: TgcgColors.ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .6,
                  ),
                ),
                Text('Election Monitoring & Collation Programme', style: TgcgType.caption),
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
          Text('Welcome to TGCG-EMCOP', style: TgcgType.display),
          SizedBox(height: 8),
          Text(
            "The Game Changer Group's election monitoring and collation programme. Sign in to "
            'report from your polling unit, follow results and work with your coordinators. '
            'New members register with their voter card (PVC).',
            style: TgcgType.support,
          ),
        ],
      );
}
