import 'package:flutter/material.dart';

import 'app.dart';
import 'session.dart';

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
  bool obscurePassword = true;
  bool rememberDevice = true;

  @override
  void dispose() {
    nameController.dispose();
    accessIdController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  void _signIn() {
    TgcgSession.of(context, listen: false).signIn(
      role: selectedRole,
      operatorName: nameController.text,
      accessId: accessIdController.text,
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
                  SizedBox(height: 310, child: _brandPanel(compact: true)),
                  const SizedBox(height: 18),
                  _formPanel(compact: true),
                ],
              );
            },
          ),
        ),
      );

  Widget _brandPanel({bool compact = false}) => Container(
        margin: EdgeInsets.all(compact ? 0 : 18),
        padding: EdgeInsets.all(compact ? 24 : 42),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          gradient: const LinearGradient(
            colors: [Color(0xFF0B2E27), Color(0xFF17614F)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: const Icon(Icons.hub_rounded, color: Colors.white),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('TGCG-EMCOP',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            letterSpacing: .8,
                          )),
                      SizedBox(height: 2),
                      Text('Election Monitoring & Collation Programme',
                          style: TextStyle(color: Colors.white60, fontSize: 11)),
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
                fontSize: 28,
                height: 1.05,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Accreditation, field monitoring, incidents, evidence, result capture, collation and situation-room coordination in one operational workspace.',
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
                const SizedBox(height: 8),
                const Text(
                  'Prototype role selection is temporary. Production access will be resolved from authenticated user credentials and assigned geographic scope.',
                  style: TextStyle(color: TgcgApp.muted, height: 1.5),
                ),
                const SizedBox(height: 24),
                const Text('Select role',
                    style: TextStyle(fontWeight: FontWeight.w900, color: TgcgApp.ink)),
                const SizedBox(height: 12),
                _roleGrid(),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: nameController,
                        decoration: _decoration(
                          'Operator name',
                          'Enter name',
                          Icons.person_outline_rounded,
                        ),
                      ),
                    ),
                    if (!compact) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: accessIdController,
                          decoration: _decoration(
                            'Access ID / phone',
                            'Enter access ID',
                            Icons.badge_outlined,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (compact) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: accessIdController,
                    decoration: _decoration(
                      'Access ID / phone',
                      'Enter access ID',
                      Icons.badge_outlined,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: passwordController,
                  obscureText: obscurePassword,
                  onSubmitted: (_) => _signIn(),
                  decoration: _decoration(
                    'Password',
                    'Enter password',
                    Icons.lock_outline_rounded,
                  ).copyWith(
                    suffixIcon: IconButton(
                      onPressed: () => setState(() => obscurePassword = !obscurePassword),
                      icon: Icon(obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined),
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
                    const Text('Remember this device',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    const Spacer(),
                    TextButton(onPressed: () {}, child: const Text('Access support')),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: FilledButton.icon(
                    onPressed: _signIn,
                    icon: const Icon(Icons.login_rounded),
                    label: Text('Enter as ${roleLabel(selectedRole)}'),
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
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4F7F6),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE0E7E4)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.shield_outlined, size: 18, color: TgcgApp.primary),
                      SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          'Authorized operational personnel only. Production authentication must be enforced server-side.',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );

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
                onTap: () => setState(() => selectedRole = role),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: width,
                  constraints: const BoxConstraints(minHeight: 96),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: active ? const Color(0xFFE7F1EE) : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: active ? TgcgApp.primary : const Color(0xFFDDE5E2),
                      width: active ? 1.5 : 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(roleIcon(role),
                              color: active ? TgcgApp.primary : TgcgApp.muted, size: 21),
                          const Spacer(),
                          if (active)
                            const Icon(Icons.check_circle_rounded,
                                color: TgcgApp.primary, size: 18),
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
          borderSide: const BorderSide(color: Color(0xFFDDE5E2)),
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
            Text(value,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(color: Colors.white60, fontSize: 11)),
          ],
        ),
      );
}
