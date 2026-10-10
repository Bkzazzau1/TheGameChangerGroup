import 'package:flutter/material.dart';

import 'api/api_client.dart';
import 'api/backend.dart';
import 'app.dart';
import 'membership/membership_store.dart';
import 'session.dart';
import 'ui/tgcg_design.dart';

class TgcgLoginPage extends StatefulWidget {
  const TgcgLoginPage({super.key});

  @override
  State<TgcgLoginPage> createState() => _TgcgLoginPageState();
}

class _TgcgLoginPageState extends State<TgcgLoginPage> {
  final nameController = TextEditingController();
  final accessIdController = TextEditingController();
  final passwordController = TextEditingController();

  TgcgRole selectedRole = TgcgRole.situationRoomDirector;
  String? selectedZoneId;
  String? selectedStateId;
  bool obscurePassword = true;
  bool rememberDevice = true;
  bool signingIn = false;
  String? serverError;

  /// Connected to a TGCG server: the server decides role and scope.
  bool get serverMode => TgcgBackend.of(context) != null;

  @override
  void dispose() {
    nameController.dispose();
    accessIdController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> _serverSignIn() async {
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
      final role = user.role;
      if (!mounted) return;
      if (role == null) {
        await services.auth.logout();
        setState(() => serverError = user.isMember
            ? 'Member accounts sign in on the TGCG member app.'
            : 'This account type cannot use the operations app.');
        return;
      }
      TgcgSession.of(context, listen: false).signInFromServer(
        role: role,
        fullName: user.fullName,
        accessId: user.accessId,
        scope: user.scope,
        capabilities: user.capabilities,
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

  void _signIn() {
    if (serverMode) {
      _serverSignIn();
      return;
    }
    final membership = MembershipOperations.of(context, listen: false);
    var scope = GeographicScope.nigeria;

    if (selectedRole == TgcgRole.zonalCoordinator) {
      final zoneId = selectedZoneId ?? membership.geography.zones.first.id;
      scope = membership.geography.zone(zoneId)?.scope ?? scope;
    } else if (selectedRole == TgcgRole.stateCoordinator) {
      final stateId = selectedStateId ?? membership.geography.states.first.id;
      scope = membership.geography.state(stateId)?.scope ?? scope;
    }

    TgcgSession.of(context, listen: false).signIn(
      role: selectedRole,
      operatorName: nameController.text,
      accessId: accessIdController.text,
      scope: scope,
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 980;
              if (wide) {
                return Row(
                  children: [
                    Expanded(flex: 10, child: _brandPanel()),
                    Expanded(flex: 13, child: _formPanel()),
                  ],
                );
              }
              return ListView(
                padding: const EdgeInsets.all(18),
                children: [
                  SizedBox(height: 300, child: _brandPanel(compact: true)),
                  const SizedBox(height: 18),
                  _formPanel(compact: true),
                ],
              );
            },
          ),
        ),
      );

  Widget _brandPanel({bool compact = false}) =>
      compact ? _textBrandPanel(compact: true) : _posterBrandPanel();

  Widget _posterBrandPanel() => Container(
        margin: const EdgeInsets.all(18),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: const Color(0xFF000E2F),
          borderRadius: BorderRadius.circular(30),
        ),
        child: Image.asset(
          'assets/brand/login_poster.webp',
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
          semanticLabel:
              'TGCG-EMCOP National Election Operations: 36 states and FCT, 774 LGAs, 176,846 polling units',
        ),
      );

  Widget _textBrandPanel({bool compact = false}) => Container(
        margin: EdgeInsets.all(compact ? 0 : 18),
        padding: EdgeInsets.all(compact ? 24 : 42),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          gradient: const LinearGradient(
            colors: [Color(0xFF011238), Color(0xFF032575)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                TgcgLogo(size: compact ? 52 : 64),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'TGCG-EMCOP',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          letterSpacing: .8,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Election Monitoring & Collation Programme',
                        style: TextStyle(color: Colors.white60, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Spacer(),
            const Text(
              'National Election Operations',
              style: TextStyle(
                color: Colors.white,
                fontSize: 29,
                height: 1.05,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Accreditation, field monitoring, incident management, evidence, result capture, collation and nationwide coordination.',
              style: TextStyle(color: Colors.white70, height: 1.5),
            ),
            const SizedBox(height: 22),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: const [
                _Stat('36 + FCT', 'States'),
                _Stat('774', 'LGAs'),
                _Stat('176,846', 'Polling Units'),
              ],
            ),
          ],
        ),
      );

  Widget _formPanel({bool compact = false}) => Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 4 : 48,
            vertical: compact ? 8 : 30,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Secure Operations Access',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    color: TgcgApp.ink,
                    letterSpacing: -.5,
                  ),
                ),
                const SizedBox(height: 7),
                const Text(
                  'Sign in to your assigned operational workspace.',
                  style: TextStyle(color: TgcgApp.muted, fontSize: 13),
                ),
                const SizedBox(height: 24),
                if (!serverMode) ...[
                  const Text(
                    'Operational role',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: TgcgApp.ink,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _roleGrid(),
                  if (selectedRole == TgcgRole.zonalCoordinator ||
                      selectedRole == TgcgRole.stateCoordinator) ...[
                    const SizedBox(height: 14),
                    _roleScopeSelector(),
                  ],
                  const SizedBox(height: 22),
                ],
                LayoutBuilder(
                  builder: (context, constraints) {
                    final stack = constraints.maxWidth < 540;
                    final name = TextField(
                      controller: nameController,
                      decoration: _decoration(
                        'Operator name',
                        'Enter name',
                        Icons.person_outline_rounded,
                      ),
                    );
                    final access = TextField(
                      controller: accessIdController,
                      autofillHints: const [AutofillHints.username],
                      textInputAction: TextInputAction.next,
                      decoration: _decoration(
                        serverMode ? 'Access ID or phone number' : 'Access ID / phone',
                        serverMode ? 'e.g. TGCG-KD-0001 or 0803 123 4567' : 'Enter access ID',
                        Icons.badge_outlined,
                      ),
                    );
                    if (serverMode) return access;
                    if (stack) {
                      return Column(
                        children: [
                          name,
                          const SizedBox(height: 12),
                          access,
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: name),
                        const SizedBox(width: 12),
                        Expanded(child: access),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passwordController,
                  obscureText: obscurePassword,
                  onSubmitted: (_) => _signIn(),
                  autofillHints: const [AutofillHints.password],
                  decoration: _decoration(
                    serverMode ? 'Password or PIN' : 'Password',
                    serverMode ? 'Members use their 6-digit PIN' : 'Enter password',
                    Icons.lock_outline_rounded,
                  ).copyWith(
                    suffixIcon: IconButton(
                      onPressed: () =>
                          setState(() => obscurePassword = !obscurePassword),
                      icon: Icon(
                        obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Checkbox(
                      value: rememberDevice,
                      onChanged: (value) =>
                          setState(() => rememberDevice = value ?? false),
                    ),
                    const Text(
                      'Remember this device',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () {},
                      child: const Text('Access support'),
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
                    label: Text(
                      serverMode
                          ? (signingIn ? 'Signing in…' : 'Sign in')
                          : 'Enter as ${roleLabel(selectedRole)}',
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: TgcgApp.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      textStyle: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _roleScopeSelector() {
    final geography =
        MembershipOperations.of(context, listen: false).geography;

    if (selectedRole == TgcgRole.zonalCoordinator) {
      final value = selectedZoneId ?? geography.zones.first.id;
      selectedZoneId ??= value;
      return DropdownButtonFormField<String>(
        initialValue: value,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Assigned geopolitical zone',
          prefixIcon: Icon(Icons.public_outlined),
        ),
        items: geography.zones
            .map(
              (zone) => DropdownMenuItem(
                value: zone.id,
                child: Text(zone.name),
              ),
            )
            .toList(),
        onChanged: (next) => setState(() => selectedZoneId = next),
      );
    }

    final value = selectedStateId ?? geography.states.first.id;
    selectedStateId ??= value;
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Assigned state / FCT',
        prefixIcon: Icon(Icons.map_outlined),
      ),
      items: geography.states
          .map(
            (state) => DropdownMenuItem(
              value: state.id,
              child: Text('${state.name} • ${state.zoneName}'),
            ),
          )
          .toList(),
      onChanged: (next) => setState(() => selectedStateId = next),
    );
  }

  Widget _roleGrid() => LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth > 680
              ? 4
              : constraints.maxWidth > 430
                  ? 3
                  : 2;
          const gap = 9.0;
          final width = (constraints.maxWidth - gap * (columns - 1)) / columns;

          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: TgcgRole.values.map((role) {
              final active = role == selectedRole;
              return InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => setState(() {
                  selectedRole = role;
                  if (role != TgcgRole.zonalCoordinator) selectedZoneId = null;
                  if (role != TgcgRole.stateCoordinator) selectedStateId = null;
                }),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: width,
                  constraints: const BoxConstraints(minHeight: 94),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: active ? const Color(0xFFE7EAF1) : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: active
                          ? TgcgApp.primary
                          : const Color(0xFFDDDFE5),
                      width: active ? 1.5 : 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            roleIcon(role),
                            color: active ? TgcgApp.primary : TgcgApp.muted,
                            size: 21,
                          ),
                          const Spacer(),
                          if (active)
                            const Icon(
                              Icons.check_circle_rounded,
                              color: TgcgApp.primary,
                              size: 18,
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        roleLabel(role),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: active ? TgcgApp.primary : TgcgApp.ink,
                          fontSize: 11.5,
                          height: 1.15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          );
        },
      );

  InputDecoration _decoration(String label, String hint, IconData icon) =>
      InputDecoration(
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

class _Stat extends StatelessWidget {
  const _Stat(this.value, this.label);

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(color: Colors.white60, fontSize: 11),
            ),
          ],
        ),
      );
}
