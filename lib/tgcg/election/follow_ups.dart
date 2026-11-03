import 'dart:async';

import 'package:flutter/material.dart';

import '../access/access_widgets.dart' show areaLabel, formatMoment;
import '../api/api_client.dart';
import '../api/backend.dart';
import '../api/member_repository.dart' show cardNeeds;
import '../api/projects_repository.dart';
import '../domain/permissions.dart';
import '../groups/my_support_groups_page.dart';
import '../member/member_shell.dart' show MyMembershipCardPage, MyRolesPage;
import '../membership/member_review_page.dart';
import '../projects/project_mode.dart' show hourMinute, openProject, statusNow;
import '../security/security_officer_page.dart';
import '../session.dart';
import '../ui/tgcg_design.dart';
import '../ui/tgcg_figures.dart' show formatCount;

/// One thing waiting for someone, from their own records.
class FollowUp {
  const FollowUp({
    required this.icon,
    required this.title,
    required this.detail,
    required this.open,
  });

  final IconData icon;
  final String title;
  final String detail;

  /// Opens the page where it is dealt with.
  final void Function(BuildContext context) open;
}

/// What someone has to follow up.
class FollowUps {
  const FollowUps(this.items, {required this.complete});

  final List<FollowUp> items;

  /// False when part of it could not be checked: then an empty list does not
  /// mean that nothing is waiting.
  final bool complete;
}

void _openCard(BuildContext context) => Navigator.of(
  context,
).push(MaterialPageRoute<void>(builder: (_) => const MyMembershipCardPage(accountLinks: false)));

void _openRoles(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const MyRolesPage()));

void _openGroups(BuildContext context) => Navigator.of(
  context,
).push(MaterialPageRoute<void>(builder: (_) => const MySupportGroupsPage()));

/// A page made for the shell, with a way back.
void _openModule(BuildContext context, Widget page) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => Scaffold(
      backgroundColor: TgcgColors.canvas,
      appBar: AppBar(),
      body: SafeArea(child: page),
    ),
  ),
);

Future<List<FollowUp>> _dispatches(BackendServices services) async {
  final active = [
    for (final dispatch in await services.security.mine())
      if (dispatch.active) dispatch,
  ];
  if (active.isEmpty) return const [];
  return [
    FollowUp(
      icon: Icons.emergency_share_outlined,
      title: active.length == 1
          ? 'An incident was sent to you'
          : '${active.length} incidents were sent to you',
      detail: active.length == 1 ? active.single.incident.title : 'See them in Security Response',
      open: (context) => _openModule(context, const SecurityOfficerPage()),
    ),
  ];
}

FollowUp? _projectLine(TgcgProject project, DateTime now) {
  final mine = project.myParticipation;
  final status = statusNow(project, now);
  if (mine == null || !const {'scheduled', 'active'}.contains(status)) return null;
  final when = status == 'active'
      ? 'On now, until ${hourMinute(project.endsAt)}'
      : 'From ${formatMoment(project.startsAt)}';
  final detail = '$when · ${areaLabel(mine.place)}';
  void open(BuildContext context) => openProject(context, project);
  if (mine.invited) {
    return FollowUp(
      icon: Icons.mark_email_unread_outlined,
      title: 'You are asked to take part in ${project.name}',
      detail: detail,
      open: open,
    );
  }
  if (!mine.accepted) return null;
  return FollowUp(icon: Icons.flag_outlined, title: project.name, detail: detail, open: open);
}

Future<List<FollowUp>> _projects(BackendServices services, DateTime now) async => [
  for (final project in await services.projects.mine())
    if (_projectLine(project, now) case final line?) line,
];

Future<List<FollowUp>> _appointments(BackendServices services) async {
  final undecided = [
    for (final item in await services.access.myAppointments())
      if (item.acceptedAt == null && item.isCurrent) item,
  ];
  if (undecided.isEmpty) return const [];
  final one = undecided.length == 1;
  return [
    FollowUp(
      icon: Icons.assignment_ind_outlined,
      title: one
          ? 'You are appointed ${undecided.single.roleName}'
          : 'You have ${undecided.length} appointments to answer',
      detail: 'Accept or decline ${one ? 'it' : 'them'} in Roles and access',
      open: _openRoles,
    ),
  ];
}

Future<List<FollowUp>> _groups(BackendServices services) async {
  final asked = (await services.supportGroups.mine()).invitations;
  if (asked.isEmpty) return const [];
  return [
    FollowUp(
      icon: Icons.diversity_3_outlined,
      title: asked.length == 1
          ? '${asked.single.groupName} asks you to confirm'
          : '${asked.length} support groups ask you to confirm',
      detail: 'Say yes or no in Support groups',
      open: _openGroups,
    ),
  ];
}

Future<List<FollowUp>> _reviews(BackendServices services, TgcgSessionController session) async {
  final members = services.members;
  final identity = session.can(TgcgCapability.verifyMemberIdentity);
  final units = session.can(TgcgCapability.reviewPollingUnitChanges);
  final waiting = await Future.wait([
    identity ? members.identitiesWaiting() : Future.value(0),
    identity ? members.pvcUpdatesWaiting() : Future.value(0),
    units ? members.unitChangesWaiting() : Future.value(0),
  ]);
  final total = waiting.fold(0, (sum, count) => sum + count);
  if (total == 0) return const [];
  String count(int number, String one, String many) =>
      '${formatCount(number)} ${number == 1 ? one : many}';
  return [
    FollowUp(
      icon: Icons.fact_check_outlined,
      title: '${count(total, 'review is', 'reviews are')} waiting',
      detail: [
        if (waiting[0] > 0) count(waiting[0], 'identity', 'identities'),
        if (waiting[1] > 0) count(waiting[1], 'PVC update', 'PVC updates'),
        if (waiting[2] > 0) count(waiting[2], 'polling unit change', 'polling unit changes'),
      ].join(' · '),
      open: (context) => _openModule(context, const MemberReviewPage()),
    ),
  ];
}

Future<List<FollowUp>> _card(BackendServices services) async {
  final card = await services.member.own.card();
  final missing = [
    for (final need in card.cardMissing)
      // Not theirs to add.
      if (need != 'active_membership') cardNeeds[need] ?? need,
  ];
  if (missing.isEmpty) return const [];
  return [
    FollowUp(
      icon: Icons.badge_outlined,
      title: 'Complete your membership card',
      detail: 'Add ${missing.join(', ')}',
      open: _openCard,
    ),
  ];
}

/// What [session]'s account has to follow up, the most pressing first. Each
/// part is checked on its own, so a problem with one never hides the others.
Future<FollowUps> loadFollowUps(
  BackendServices services,
  TgcgSessionController session,
  DateTime now,
) async {
  var complete = true;
  Future<List<FollowUp>> checked(Future<List<FollowUp>> Function() load) async {
    try {
      return await load().timeout(const Duration(seconds: 8));
    } on ApiException catch (error) {
      // 403 and 404: nothing of the kind is this account's to answer.
      if (!const {403, 404}.contains(error.statusCode)) complete = false;
    } catch (_) {
      complete = false;
    }
    return const [];
  }

  final member = session.membershipNumber != null;
  final reviews = session.canAny(const [
    TgcgCapability.verifyMemberIdentity,
    TgcgCapability.reviewPollingUnitChanges,
  ]);
  final parts = await Future.wait([
    if (session.can(TgcgCapability.respondToSecurity)) checked(() => _dispatches(services)),
    if (member) checked(() => _projects(services, now)),
    checked(() => _appointments(services)),
    if (member) checked(() => _groups(services)),
    if (reviews) checked(() => _reviews(services, session)),
    if (member) checked(() => _card(services)),
  ]);
  return FollowUps([
    if (session.waitingRole case final role?)
      FollowUp(
        icon: Icons.hourglass_top_rounded,
        title: 'You are listed as a $role',
        detail: 'That work starts once a coordinator has checked your identity',
        open: _openCard,
      ),
    for (final part in parts) ...part,
  ], complete: complete);
}
