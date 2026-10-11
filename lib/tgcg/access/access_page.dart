import 'package:flutter/material.dart';

import '../api/backend.dart';
import '../domain/permissions.dart';
import '../session.dart';
import '../ui/tgcg_design.dart';
import 'access_widgets.dart';
import 'administration_tabs.dart';
import 'appointments_tab.dart';
import 'delegations_tab.dart';
import 'roles_tab.dart';

/// Roles, appointments, delegated authority, National Administrators and the
/// audit log, as far as the caller's permissions reach. The server checks
/// every change against the caller's own authority.
class AccessControlPage extends StatelessWidget {
  const AccessControlPage({super.key});

  static const _readers = [
    TgcgCapability.viewRoles,
    TgcgCapability.manageRoles,
    TgcgCapability.assignRoles,
    TgcgCapability.manageAssignments,
    TgcgCapability.delegateAuthority,
  ];

  @override
  Widget build(BuildContext context) {
    if (TgcgBackend.of(context) == null) {
      return const ConnectToServerNotice(
        message:
            'Roles and appointments are kept on the server. Sign in with a server account '
            'to manage them.',
      );
    }
    final session = TgcgSession.of(context);
    final tabs = <(String, IconData, Widget)>[
      if (session.canAny(_readers)) ...[
        ('Roles', Icons.badge_outlined, const RolesTab()),
        ('Appointments', Icons.assignment_ind_outlined, const AppointmentsTab()),
        ('Delegations', Icons.call_split_rounded, const DelegationsTab()),
      ],
      if (session.can(TgcgCapability.appointNationalAdministrator))
        ('Administrators', Icons.admin_panel_settings_outlined, const AdministratorsTab()),
      if (session.can(TgcgCapability.viewAudit))
        ('Audit log', Icons.fact_check_outlined, const AuditTab()),
    ];
    if (tabs.isEmpty) {
      return const Center(
        child: TgcgEmptyState(
          icon: Icons.lock_outline_rounded,
          title: 'No access management here',
          message: 'Your appointments do not include managing roles or appointments.',
        ),
      );
    }
    return DefaultTabController(
      length: tabs.length,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 24, 24, 8),
            child: TgcgPageHeader(
              eyebrow: 'ACCESS CONTROL',
              title: 'Roles & Access',
              subtitle:
                  'Roles, appointments and delegated authority. Every change is checked '
                  'by the server against your own authority, and recorded in the audit log.',
            ),
          ),
          TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              for (final (label, icon, _) in tabs) Tab(icon: Icon(icon, size: 20), text: label),
            ],
          ),
          const Divider(height: 1),
          Expanded(child: TabBarView(children: [for (final (_, _, page) in tabs) page])),
        ],
      ),
    );
  }
}
