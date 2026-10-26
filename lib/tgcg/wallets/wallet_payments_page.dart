import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../access/access_widgets.dart';
import '../api/access_repository.dart';
import '../api/api_client.dart';
import '../api/backend.dart';
import '../api/wallet_repository.dart';
import '../domain/permissions.dart';
import '../member/wallet_page.dart' show WalletEntryTile, withdrawalPill;
import '../session.dart';
import '../ui/tgcg_design.dart';

/// Members' wallets in the account's areas: payments (requested by one
/// person, approved or rejected by another), withdrawals to members' bank
/// accounts (approved by a second person, then paid through Paystack), the
/// credit rates a National Administrator sets, and who registers members and
/// how far their people got.
class WalletPaymentsPage extends StatefulWidget {
  const WalletPaymentsPage({super.key});

  @override
  State<WalletPaymentsPage> createState() => _WalletPaymentsPageState();
}

const _filters = <(String?, String)>[
  ('pending', 'Awaiting approval'),
  ('approved', 'Approved'),
  ('rejected', 'Rejected'),
  ('cancelled', 'Cancelled'),
  (null, 'All'),
];

enum _Section { payments, withdrawals, rates, registrars }

/// The sections this account may open: each needs the powers its list asks for.
List<_Section> _sectionsFor(TgcgSessionController session) => [
  if (session.canAny(const [
    TgcgCapability.viewWallets,
    TgcgCapability.creditWallets,
    TgcgCapability.approveWalletCredits,
  ]))
    _Section.payments,
  if (session.canAny(const [TgcgCapability.viewWallets, TgcgCapability.approveWithdrawals]))
    _Section.withdrawals,
  if (session.canAny(const [TgcgCapability.viewWallets, TgcgCapability.manageCreditRates]))
    _Section.rates,
  if (session.canAny(const [
    TgcgCapability.viewWallets,
    TgcgCapability.creditWallets,
    TgcgCapability.approveWalletCredits,
    TgcgCapability.approveWithdrawals,
    TgcgCapability.manageCreditRates,
  ]))
    _Section.registrars,
];

class _WalletPaymentsPageState extends State<WalletPaymentsPage> {
  int _filter = 0;
  _Section? _section;
  Future<ApiPage<WalletPayment>>? _payments;

  Future<ApiPage<WalletPayment>> _load() =>
      TgcgBackend.of(context)!.wallets.payments(status: _filters[_filter].$1);

  void _reload() => setState(() {
    _payments = _load();
  });

  Future<void> _newPayment() async {
    final payment = await showDialog<WalletPayment>(
      context: context,
      builder: (_) => const _NewPaymentDialog(),
    );
    if (payment == null || !mounted) return;
    showDone(context, 'Payment to ${payment.memberName} sent for approval.');
    _reload();
  }

  Future<void> _lookUp() async {
    final number = await promptText(
      context,
      title: "A member's wallet",
      label: 'Membership number',
      action: 'Open',
      required: true,
    );
    if (number == null || !mounted) return;
    try {
      final wallet = await TgcgBackend.of(context)!.wallets.memberWallet(number);
      if (!mounted) return;
      await showDialog<void>(context: context, builder: (_) => _WalletDialog(wallet: wallet));
    } catch (error) {
      if (mounted) showFailure(context, error);
    }
  }

  Future<void> _act(Future<WalletPayment> Function() action, String done) async {
    try {
      await action();
      if (!mounted) return;
      showDone(context, done);
      _reload();
    } catch (error) {
      if (mounted) showFailure(context, error);
    }
  }

  Future<void> _approve(WalletPayment payment) async {
    final wallets = TgcgBackend.of(context)!.wallets;
    final sure = await confirmAction(
      context,
      title: 'Approve this payment?',
      message: '${formatNaira(payment.amount)} to ${payment.memberName} (${payment.member}) '
          'for ${payment.purpose}.',
      action: 'Approve',
    );
    if (sure) await _act(() => wallets.approve(payment.id), 'Payment approved.');
  }

  Future<void> _reject(WalletPayment payment) async {
    final wallets = TgcgBackend.of(context)!.wallets;
    final reason = await promptText(
      context,
      title: 'Reject this payment?',
      label: 'Reason',
      action: 'Reject',
      required: true,
      destructive: true,
    );
    if (reason != null) await _act(() => wallets.reject(payment.id, reason), 'Payment rejected.');
  }

  Future<void> _cancel(WalletPayment payment) async {
    final wallets = TgcgBackend.of(context)!.wallets;
    final sure = await confirmAction(
      context,
      title: 'Cancel this payment?',
      message: '${formatNaira(payment.amount)} to ${payment.memberName}.',
      action: 'Cancel payment',
      destructive: true,
    );
    if (sure) await _act(() => wallets.cancel(payment.id), 'Payment cancelled.');
  }

  @override
  Widget build(BuildContext context) {
    if (TgcgBackend.of(context) == null) {
      return const ConnectToServerNotice(
        message: 'Payments are made on the server. Sign in with a server account to make them.',
      );
    }
    final session = TgcgSession.of(context);
    final sections = _sectionsFor(session);
    final section = sections.contains(_section) ? _section! : sections.firstOrNull;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('Wallets', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
        if (sections.length > 1) ...[
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<_Section>(
              showSelectedIcon: false,
              segments: [
                for (final each in sections)
                  ButtonSegment(
                    value: each,
                    label: Text(switch (each) {
                      _Section.registrars => 'Registrars',
                      _Section.payments => 'Payments',
                      _Section.withdrawals => 'Withdrawals',
                      _Section.rates => 'Token rates',
                    }),
                  ),
              ],
              selected: {?section},
              onSelectionChanged: (chosen) => setState(() => _section = chosen.first),
            ),
          ),
        ],
        const SizedBox(height: 12),
        ...switch (section) {
          _Section.registrars => const [_RegistrarsSection()],
          _Section.payments => _paymentsSection(session),
          _Section.withdrawals => const [_WithdrawalsSection()],
          _Section.rates => const [_CreditRatesSection()],
          null => const <Widget>[],
        },
      ],
    );
  }

  List<Widget> _paymentsSection(TgcgSessionController session) {
    _payments ??= _load();
    return [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (session.can(TgcgCapability.creditWallets))
              FilledButton.icon(
                onPressed: _newPayment,
                icon: const Icon(Icons.add_rounded),
                label: const Text('New payment'),
              ),
            if (session.can(TgcgCapability.viewWallets))
              OutlinedButton.icon(
                onPressed: _lookUp,
                icon: const Icon(Icons.account_balance_wallet_outlined),
                label: const Text("A member's wallet"),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < _filters.length; i++)
              ChoiceChip(
                label: Text(_filters[i].$2),
                selected: _filter == i,
                onSelected: (_) {
                  _filter = i;
                  _reload();
                },
              ),
          ],
        ),
        const SizedBox(height: 16),
        FutureBuilder<ApiPage<WalletPayment>>(
          future: _payments,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return TgcgEmptyState(
                icon: Icons.error_outline_rounded,
                title: 'Payments could not be loaded',
                message: failureMessage(snapshot.error!),
                action: OutlinedButton(onPressed: _reload, child: const Text('Try again')),
              );
            }
            final page = snapshot.data;
            if (page == null) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (page.items.isEmpty) {
              return const TgcgEmptyState(
                icon: Icons.payments_outlined,
                title: 'No payments here',
                message: 'Payments in your areas appear here.',
              );
            }
            return Column(
              children: [
                for (final payment in page.items)
                  _PaymentTile(
                    payment: payment,
                    onApprove: payment.canDecide ? () => _approve(payment) : null,
                    onReject: payment.canDecide ? () => _reject(payment) : null,
                    onCancel: payment.canCancel ? () => _cancel(payment) : null,
                  ),
              ],
            );
          },
        ),
    ];
  }
}

TgcgStatusPill paymentPill(String status) => TgcgStatusPill(
  compact: true,
  label: switch (status) {
    'pending' => 'Awaiting approval',
    'approved' => 'Approved',
    'rejected' => 'Rejected',
    'cancelled' => 'Cancelled',
    _ => status,
  },
  color: switch (status) {
    'approved' => TgcgColors.success,
    'pending' => TgcgColors.warning,
    'rejected' => TgcgColors.danger,
    _ => TgcgColors.muted,
  },
);

class _PaymentTile extends StatelessWidget {
  const _PaymentTile({required this.payment, this.onApprove, this.onReject, this.onCancel});

  final WalletPayment payment;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${payment.memberName} (${payment.member})',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                formatNaira(payment.amount),
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(payment.purpose),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              paymentPill(payment.status),
              Text(
                [
                  'Requested by ${payment.requestedBy}',
                  if (payment.createdAt != null) formatMoment(payment.createdAt!),
                  if (payment.decidedBy != null) 'decided by ${payment.decidedBy}',
                ].join(' · '),
                style: const TextStyle(color: TgcgColors.muted, fontSize: 12),
              ),
            ],
          ),
          if (payment.decisionReason.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(payment.decisionReason, style: const TextStyle(color: TgcgColors.muted)),
          ],
          if (onApprove != null || onCancel != null) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                if (onApprove != null)
                  FilledButton(onPressed: onApprove, child: const Text('Approve')),
                if (onReject != null)
                  OutlinedButton(onPressed: onReject, child: const Text('Reject')),
                if (onCancel != null)
                  TextButton(onPressed: onCancel, child: const Text('Cancel payment')),
              ],
            ),
          ],
        ],
      ),
    ),
  );
}

class _NewPaymentDialog extends StatefulWidget {
  const _NewPaymentDialog();

  @override
  State<_NewPaymentDialog> createState() => _NewPaymentDialogState();
}

class _NewPaymentDialogState extends State<_NewPaymentDialog> {
  final _member = TextEditingController();
  final _amount = TextEditingController();
  final _purpose = TextEditingController();
  Map<String, String> _errors = const {};
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _member.dispose();
    _amount.dispose();
    _purpose.dispose();
    super.dispose();
  }

  bool get _ready =>
      !_saving &&
      _member.text.trim().isNotEmpty &&
      _amount.text.trim().isNotEmpty &&
      _purpose.text.trim().isNotEmpty;

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _errors = const {};
      _error = null;
    });
    try {
      final payment = await TgcgBackend.of(context)!.wallets.requestPayment(
        member: _member.text,
        amount: _amount.text.replaceAll(',', ''),
        purpose: _purpose.text,
      );
      if (mounted) Navigator.pop(context, payment);
    } catch (error) {
      final fields = <String, String>{
        if (error is ApiException)
          for (final field in const ['member', 'amount', 'purpose'])
            if (error.fieldError(field) case final message?) field: message,
      };
      setState(() {
        _saving = false;
        _errors = fields;
        _error = fields.isEmpty ? failureMessage(error) : null;
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('New payment'),
    content: SizedBox(
      width: 400,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _member,
            decoration: InputDecoration(
              labelText: 'Membership number',
              hintText: 'TGCG-000123',
              errorText: _errors['member'],
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            decoration: InputDecoration(
              labelText: 'Amount',
              prefixText: '₦',
              errorText: _errors['amount'],
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _purpose,
            maxLength: 200,
            decoration: InputDecoration(labelText: 'What it is for', errorText: _errors['purpose']),
            onChanged: (_) => setState(() {}),
          ),
          if (_error != null)
            Text(_error!, style: const TextStyle(color: TgcgColors.danger)),
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
      FilledButton(onPressed: _ready ? _save : null, child: const Text('Send for approval')),
    ],
  );
}

class _WalletDialog extends StatelessWidget {
  const _WalletDialog({required this.wallet});

  final MemberWallet wallet;

  @override
  Widget build(BuildContext context) {
    final account = wallet.payoutAccount;
    return AlertDialog(
      title: Text('${wallet.accountName} (${wallet.membershipNumber})'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!wallet.hasWallet)
                const Text('No wallet: the identity is not verified.')
              else ...[
                Text(
                  formatNaira(wallet.balance),
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                Text(
                  account == null
                      ? 'No payout account'
                      : '${account.bankName} ${account.accountNumber}',
                  style: const TextStyle(color: TgcgColors.muted),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                '${tgcTokens(wallet.credits)}, worth ${formatNaira(wallet.creditsWorth)} today',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              for (final entry in wallet.entries) WalletEntryTile(entry: entry, dense: true),
            ],
          ),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
    );
  }
}

/// Everyone who registered members in the account's areas, most first: how
/// many, how many have signed in (each first sign-in earns the registrar a
/// credit) and how many have not yet.
class _RegistrarsSection extends StatefulWidget {
  const _RegistrarsSection();

  @override
  State<_RegistrarsSection> createState() => _RegistrarsSectionState();
}

const _registrarOrders = <(RegistrarOrder, String)>[
  (RegistrarOrder.mostRegistered, 'Most registered'),
  (RegistrarOrder.mostWaiting, 'Most not signed in yet'),
  (RegistrarOrder.mostSignedIn, 'Most signed in'),
  (RegistrarOrder.latest, 'Latest registration'),
  (RegistrarOrder.name, 'Name'),
];

class _RegistrarsSectionState extends State<_RegistrarsSection> {
  final _search = TextEditingController();
  var _order = RegistrarOrder.mostRegistered;
  final _registrars = <Registrar>[];
  ({int registrars, RegistrationCounts counts})? _totals;
  var _hasMore = false;
  var _loading = false;
  Object? _error;
  var _started = false;
  var _generation = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _load(reset: true);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    final wallets = TgcgBackend.of(context)!.wallets;
    final generation = reset ? ++_generation : _generation;
    final search = _search.text;
    setState(() {
      if (reset) {
        _registrars.clear();
        _hasMore = false;
      }
      _loading = true;
      _error = null;
    });
    try {
      final page = await wallets.registrars(
        search: search,
        order: _order,
        offset: _registrars.length,
      );
      final totals = reset ? await wallets.registrarTotals(search: search) : _totals;
      if (!mounted || generation != _generation) return;
      setState(() {
        _registrars.addAll(page.items);
        _hasMore = page.hasMore;
        _totals = totals;
      });
    } catch (error) {
      if (mounted && generation == _generation) setState(() => _error = error);
    } finally {
      if (mounted && generation == _generation) setState(() => _loading = false);
    }
  }

  void _open(Registrar registrar) => Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => RegistrarPeoplePage(registrar: registrar)),
  );

  @override
  Widget build(BuildContext context) {
    final totals = _totals;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (totals != null) ...[
          _RegistrarTotals(registrars: totals.registrars, counts: totals.counts),
          const SizedBox(height: 12),
        ],
        TextField(
          controller: _search,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _load(reset: true),
          decoration: InputDecoration(
            labelText: 'Search by name or membership number',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: IconButton(
              tooltip: 'Search',
              onPressed: () => _load(reset: true),
              icon: const Icon(Icons.arrow_forward_rounded),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (order, label) in _registrarOrders)
              ChoiceChip(
                label: Text(label),
                selected: _order == order,
                onSelected: (_) {
                  _order = order;
                  _load(reset: true);
                },
              ),
          ],
        ),
        const SizedBox(height: 16),
        for (final registrar in _registrars)
          _RegistrarTile(
            key: ValueKey(registrar.accessId),
            registrar: registrar,
            onOpen: () => _open(registrar),
          ),
        if (_error != null)
          TgcgEmptyState(
            icon: Icons.error_outline_rounded,
            title: 'Registrars could not be loaded',
            message: failureMessage(_error!),
            action: OutlinedButton(
              onPressed: () => _load(reset: _registrars.isEmpty),
              child: const Text('Try again'),
            ),
          )
        else if (!_loading && _registrars.isEmpty)
          const TgcgEmptyState(
            icon: Icons.group_add_outlined,
            title: 'No registrars here',
            message: 'People who register members in your areas appear here.',
          ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_hasMore && _error == null)
          OutlinedButton(onPressed: _load, child: const Text('Show more')),
      ],
    );
  }
}

class _RegistrarTotals extends StatelessWidget {
  const _RegistrarTotals({required this.registrars, required this.counts});

  final int registrars;
  final RegistrationCounts counts;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final (label, value, color) in [
        ('Registrars', registrars, TgcgColors.ink),
        ('Registered', counts.registered, TgcgColors.ink),
        ('Signed in', counts.signedIn, TgcgColors.success),
        ('Not signed in yet', counts.waiting, TgcgColors.warning),
        ('Rewarded', counts.credited, TgcgColors.primary),
      ])
        Container(
          constraints: const BoxConstraints(minWidth: 100),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: TgcgColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: TgcgColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$value',
                style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.w900),
              ),
              Text(label, style: const TextStyle(color: TgcgColors.muted, fontSize: 12)),
            ],
          ),
        ),
    ],
  );
}

class _RegistrarTile extends StatelessWidget {
  const _RegistrarTile({super.key, required this.registrar, required this.onOpen});

  final Registrar registrar;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final counts = registrar.counts;
    final number = registrar.membershipNumber;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          registrar.fullName,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          [number ?? 'Staff account, earns no TGC tokens', areaLabel(registrar.scope)]
                              .join(' · '),
                          style: const TextStyle(color: TgcgColors.muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${counts.registered}',
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  TgcgStatusPill(
                    compact: true,
                    label: '${counts.signedIn} signed in',
                    color: TgcgColors.success,
                  ),
                  TgcgStatusPill(
                    compact: true,
                    label: '${counts.waiting} not signed in yet',
                    color: counts.waiting == 0 ? TgcgColors.muted : TgcgColors.warning,
                  ),
                  TgcgStatusPill(
                    compact: true,
                    label: '${counts.credited} rewarded',
                    color: TgcgColors.primary,
                  ),
                  if (counts.withCode > 0)
                    TgcgStatusPill(
                      compact: true,
                      label: '${counts.withCode} with their code',
                      color: TgcgColors.muted,
                    ),
                  if (number != null && !registrar.identityVerified)
                    const TgcgStatusPill(
                      compact: true,
                      label: 'ID not checked',
                      color: TgcgColors.muted,
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                [
                  if (number != null) 'TGC tokens now: ${registrar.credits}',
                  if (registrar.lastRegisteredAt != null)
                    'last registered ${formatMoment(registrar.lastRegisteredAt!)}',
                ].join(' · '),
                style: const TextStyle(color: TgcgColors.muted, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The people one registrar registered, newest first: whether each has
/// signed in and earned the registrar a credit. No phone numbers.
class RegistrarPeoplePage extends StatefulWidget {
  const RegistrarPeoplePage({super.key, required this.registrar});

  final Registrar registrar;

  @override
  State<RegistrarPeoplePage> createState() => _RegistrarPeoplePageState();
}

const _peopleFilters = <(bool?, String)>[
  (null, 'All'),
  (false, 'Not signed in yet'),
  (true, 'Signed in'),
];

class _RegistrarPeoplePageState extends State<RegistrarPeoplePage> {
  var _filter = 0;
  final _people = <RegisteredPerson>[];
  var _count = 0;
  var _hasMore = false;
  var _loading = false;
  Object? _error;
  var _started = false;
  var _generation = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    final wallets = TgcgBackend.of(context)!.wallets;
    final generation = reset ? ++_generation : _generation;
    setState(() {
      if (reset) {
        _people.clear();
        _hasMore = false;
      }
      _loading = true;
      _error = null;
    });
    try {
      final page = await wallets.registeredBy(
        widget.registrar.accessId,
        signedIn: _peopleFilters[_filter].$1,
        offset: _people.length,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _people.addAll(page.items);
        _hasMore = page.hasMore;
        _count = page.count;
      });
    } catch (error) {
      if (mounted && generation == _generation) setState(() => _error = error);
    } finally {
      if (mounted && generation == _generation) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final registrar = widget.registrar;
    final counts = registrar.counts;
    final shownAll = _filter == 0 && !_loading && _error == null;
    final elsewhere = counts.registered - _count;
    return Scaffold(
      backgroundColor: TgcgColors.canvas,
      appBar: AppBar(title: Text(registrar.fullName)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _RegistrarTotals(registrars: 1, counts: counts),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < _peopleFilters.length; i++)
                ChoiceChip(
                  label: Text(_peopleFilters[i].$2),
                  selected: _filter == i,
                  onSelected: (_) {
                    _filter = i;
                    _load(reset: true);
                  },
                ),
            ],
          ),
          if (shownAll && elsewhere > 0) ...[
            const SizedBox(height: 8),
            Text(
              '$elsewhere registered in other areas are not listed here.',
              style: const TextStyle(color: TgcgColors.muted),
            ),
          ],
          const SizedBox(height: 12),
          for (final person in _people) _PersonTile(key: ValueKey(person.membershipNumber), person: person),
          if (_error != null)
            TgcgEmptyState(
              icon: Icons.error_outline_rounded,
              title: 'The list could not be loaded',
              message: failureMessage(_error!),
              action: OutlinedButton(
                onPressed: () => _load(reset: _people.isEmpty),
                child: const Text('Try again'),
              ),
            )
          else if (!_loading && _people.isEmpty)
            const TgcgEmptyState(
              icon: Icons.person_search_outlined,
              title: 'Nobody here',
              message: 'Nobody matches this choice.',
            ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_hasMore && _error == null)
            OutlinedButton(onPressed: _load, child: const Text('Show more')),
        ],
      ),
    );
  }
}

class _PersonTile extends StatelessWidget {
  const _PersonTile({super.key, required this.person});

  final RegisteredPerson person;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 8),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${person.fullName} (${person.membershipNumber})',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          Text(
            [
              if (person.scope.level != GeographyLevel.country) areaLabel(person.scope),
              if (person.registeredAt != null) 'registered ${formatMoment(person.registeredAt!)}',
            ].join(' · '),
            style: const TextStyle(color: TgcgColors.muted, fontSize: 12),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              TgcgStatusPill(
                compact: true,
                label: person.signedIn ? 'Signed in' : 'Not signed in yet',
                color: person.signedIn ? TgcgColors.success : TgcgColors.warning,
              ),
              if (person.credited)
                const TgcgStatusPill(compact: true, label: 'Rewarded', color: TgcgColors.primary),
            ],
          ),
        ],
      ),
    ),
  );
}

/// Withdrawals by members in the account's areas. A different person with
/// approveWithdrawals approves one (Paystack then pays it, if the bank holds
/// the account in the member's name) or rejects it.
class _WithdrawalsSection extends StatefulWidget {
  const _WithdrawalsSection();

  @override
  State<_WithdrawalsSection> createState() => _WithdrawalsSectionState();
}

const _withdrawalFilters = <(WithdrawalStatus?, String)>[
  (WithdrawalStatus.pending, 'Awaiting approval'),
  (WithdrawalStatus.processing, 'Being paid'),
  (WithdrawalStatus.paid, 'Paid'),
  (WithdrawalStatus.failed, 'Not paid'),
  (WithdrawalStatus.reversed, 'Returned by the bank'),
  (WithdrawalStatus.rejected, 'Rejected'),
  (WithdrawalStatus.cancelled, 'Cancelled'),
  (null, 'All'),
];

class _WithdrawalsSectionState extends State<_WithdrawalsSection> {
  int _filter = 0;
  Future<ApiPage<Withdrawal>>? _withdrawals;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _withdrawals ??= _load();
  }

  Future<ApiPage<Withdrawal>> _load() =>
      TgcgBackend.of(context)!.wallets.withdrawals(status: _withdrawalFilters[_filter].$1?.name);

  void _reload() => setState(() {
    _withdrawals = _load();
  });

  Future<void> _approve(Withdrawal withdrawal) async {
    final wallets = TgcgBackend.of(context)!.wallets;
    final sure = await confirmAction(
      context,
      title: 'Approve and pay this withdrawal?',
      message: '${formatNaira(withdrawal.amount)} to ${withdrawal.memberName} '
          '(${withdrawal.member}), into ${withdrawal.bankName} ${withdrawal.accountNumber}. '
          "It is paid only if the bank's name for the account is the member's.",
      action: 'Approve and pay',
    );
    if (!sure) return;
    try {
      final done = await wallets.approveWithdrawal(withdrawal.id);
      if (!mounted) return;
      showDone(context, switch (done.status) {
        WithdrawalStatus.paid => 'Withdrawal paid.',
        WithdrawalStatus.failed || WithdrawalStatus.reversed =>
          'Not paid${done.failureReason.isEmpty ? '' : ': ${done.failureReason}'}. '
              "The money is back in the member's wallet.",
        _ => 'Withdrawal approved; the payment is on its way.',
      });
      _reload();
    } catch (error) {
      if (mounted) showFailure(context, error);
    }
  }

  Future<void> _reject(Withdrawal withdrawal) async {
    final wallets = TgcgBackend.of(context)!.wallets;
    final reason = await promptText(
      context,
      title: 'Reject this withdrawal?',
      label: 'Reason',
      action: 'Reject',
      required: true,
      destructive: true,
    );
    if (reason == null) return;
    try {
      await wallets.rejectWithdrawal(withdrawal.id, reason);
      if (!mounted) return;
      showDone(context, "Withdrawal rejected; the money is back in the member's wallet.");
      _reload();
    } catch (error) {
      if (mounted) showFailure(context, error);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (var i = 0; i < _withdrawalFilters.length; i++)
            ChoiceChip(
              label: Text(_withdrawalFilters[i].$2),
              selected: _filter == i,
              onSelected: (_) {
                _filter = i;
                _reload();
              },
            ),
        ],
      ),
      const SizedBox(height: 16),
      FutureBuilder<ApiPage<Withdrawal>>(
        future: _withdrawals,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return TgcgEmptyState(
              icon: Icons.error_outline_rounded,
              title: 'Withdrawals could not be loaded',
              message: failureMessage(snapshot.error!),
              action: OutlinedButton(onPressed: _reload, child: const Text('Try again')),
            );
          }
          final page = snapshot.data;
          if (page == null) {
            return const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (page.items.isEmpty) {
            return const TgcgEmptyState(
              icon: Icons.account_balance_outlined,
              title: 'No withdrawals here',
              message: 'Withdrawals by members in your areas appear here.',
            );
          }
          return Column(
            children: [
              for (final withdrawal in page.items)
                _WithdrawalTile(
                  withdrawal: withdrawal,
                  onApprove: withdrawal.canDecide ? () => _approve(withdrawal) : null,
                  onReject: withdrawal.canDecide ? () => _reject(withdrawal) : null,
                ),
            ],
          );
        },
      ),
    ],
  );
}

class _WithdrawalTile extends StatelessWidget {
  const _WithdrawalTile({required this.withdrawal, this.onApprove, this.onReject});

  final Withdrawal withdrawal;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${withdrawal.memberName} (${withdrawal.member})',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                formatNaira(withdrawal.amount),
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('${withdrawal.bankName} ${withdrawal.accountNumber}'),
          if (withdrawal.bankAccountName.isNotEmpty)
            Text(
              "Bank's name for the account: ${withdrawal.bankAccountName}",
              style: const TextStyle(color: TgcgColors.muted),
            ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              withdrawalPill(withdrawal.status),
              Text(
                [
                  if (withdrawal.createdAt != null) 'Asked ${formatMoment(withdrawal.createdAt!)}',
                  if (withdrawal.decidedBy != null) 'decided by ${withdrawal.decidedBy}',
                ].join(' · '),
                style: const TextStyle(color: TgcgColors.muted, fontSize: 12),
              ),
            ],
          ),
          for (final why in [withdrawal.failureReason, withdrawal.decisionReason])
            if (why.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(why, style: const TextStyle(color: TgcgColors.muted)),
            ],
          if (onApprove != null) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                FilledButton(onPressed: onApprove, child: const Text('Approve')),
                if (onReject != null)
                  OutlinedButton(onPressed: onReject, child: const Text('Reject')),
              ],
            ),
          ],
        ],
      ),
    ),
  );
}

/// What registering a member earns, what a credit is worth and the smallest
/// withdrawal, now and before. National Administrators set new rates.
class _CreditRatesSection extends StatefulWidget {
  const _CreditRatesSection();

  @override
  State<_CreditRatesSection> createState() => _CreditRatesSectionState();
}

class _CreditRatesSectionState extends State<_CreditRatesSection> {
  Future<({CreditRate current, List<CreditRate> history})>? _rates;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _rates ??= TgcgBackend.of(context)!.wallets.creditRates();
  }

  void _reload() => setState(() {
    _rates = TgcgBackend.of(context)!.wallets.creditRates();
  });

  Future<void> _change(CreditRate current) async {
    final saved = await showDialog<CreditRate>(
      context: context,
      builder: (_) => _CreditRatesDialog(current: current),
    );
    if (saved == null || !mounted) return;
    showDone(context, 'New rates saved.');
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final canSet = TgcgSession.of(context).can(TgcgCapability.manageCreditRates);
    return FutureBuilder<({CreditRate current, List<CreditRate> history})>(
      future: _rates,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return TgcgEmptyState(
            icon: Icons.error_outline_rounded,
            title: 'The token rates could not be loaded',
            message: failureMessage(snapshot.error!),
            action: OutlinedButton(onPressed: _reload, child: const Text('Try again')),
          );
        }
        final rates = snapshot.data;
        if (rates == null) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TgcgSectionCard(
              title: 'Current rates',
              trailing: canSet
                  ? FilledButton(
                      onPressed: () => _change(rates.current),
                      child: const Text('Change rates'),
                    )
                  : null,
              child: _RateFacts(rate: rates.current),
            ),
            if (rates.history.isNotEmpty) ...[
              const SizedBox(height: 12),
              TgcgSectionCard(
                title: 'Earlier rates',
                child: Column(
                  children: [
                    for (final rate in rates.history)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(_rateSummary(rate)),
                        subtitle: Text(
                          [
                            if (rate.createdAt != null) formatMoment(rate.createdAt!),
                            if (rate.setBy != null) 'set by ${rate.setBy}',
                            if (rate.reason.isNotEmpty) rate.reason,
                          ].join(' · '),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

String _rateSummary(CreditRate rate) => [
  rate.creditsPerRegistration == 0
      ? 'No TGC tokens for registering (paused)'
      : '${tgcTokens(rate.creditsPerRegistration)} a member registered',
  '${formatNaira(rate.nairaPerCredit)} a TGC token',
  'withdrawals from ${formatNaira(rate.minWithdrawal)}',
].join(' · ');

class _RateFacts extends StatelessWidget {
  const _RateFacts({required this.rate});

  final CreditRate rate;

  @override
  Widget build(BuildContext context) {
    Widget line(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 170, child: Text(label, style: const TextStyle(color: TgcgColors.muted))),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w800))),
        ],
      ),
    );
    return Column(
      children: [
        line(
          'TGC tokens a member registered',
          rate.creditsPerRegistration == 0 ? 'None (paused)' : '${rate.creditsPerRegistration}',
        ),
        line('Naira a TGC token', formatNaira(rate.nairaPerCredit)),
        line('Smallest withdrawal', formatNaira(rate.minWithdrawal)),
        line(
          'Set',
          rate.createdAt == null
              ? 'Starting rates'
              : [
                  formatMoment(rate.createdAt!),
                  if (rate.setBy != null) 'by ${rate.setBy}',
                  if (rate.reason.isNotEmpty) rate.reason,
                ].join(' · '),
        ),
      ],
    );
  }
}

class _CreditRatesDialog extends StatefulWidget {
  const _CreditRatesDialog({required this.current});

  final CreditRate current;

  @override
  State<_CreditRatesDialog> createState() => _CreditRatesDialogState();
}

class _CreditRatesDialogState extends State<_CreditRatesDialog> {
  late final _credits = TextEditingController(text: '${widget.current.creditsPerRegistration}');
  late final _naira = TextEditingController(text: widget.current.nairaPerCredit);
  late final _minimum = TextEditingController(text: widget.current.minWithdrawal);
  final _reason = TextEditingController();
  Map<String, String> _errors = const {};
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _credits.dispose();
    _naira.dispose();
    _minimum.dispose();
    _reason.dispose();
    super.dispose();
  }

  bool get _ready =>
      !_saving &&
      int.tryParse(_credits.text) != null &&
      _naira.text.trim().isNotEmpty &&
      _minimum.text.trim().isNotEmpty &&
      _reason.text.trim().isNotEmpty;

  Future<void> _save() async {
    if (!_ready) return;
    final route = ModalRoute.of(context);
    setState(() {
      _saving = true;
      _errors = const {};
      _error = null;
    });
    try {
      final rate = await TgcgBackend.of(context)!.wallets.setCreditRates(
        creditsPerRegistration: int.parse(_credits.text),
        nairaPerCredit: _naira.text.replaceAll(',', ''),
        minWithdrawal: _minimum.text.replaceAll(',', ''),
        reason: _reason.text,
      );
      if (!mounted || route?.isCurrent != true) return;
      Navigator.pop(context, rate);
    } catch (error) {
      if (!mounted || route?.isCurrent != true) return;
      final fields = <String, String>{
        if (error is ApiException)
          for (final field in const [
            'credits_per_registration',
            'naira_per_credit',
            'min_withdrawal',
            'reason',
          ])
            if (error.fieldError(field) case final message?) field: message,
      };
      setState(() {
        _saving = false;
        _errors = fields;
        _error = fields.isEmpty ? failureMessage(error) : null;
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Change the token rates'),
    content: SizedBox(
      width: 400,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _credits,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: 'TGC tokens a member registered',
                helperText: '0 pauses them',
                errorText: _errors['credits_per_registration'],
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _naira,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
              decoration: InputDecoration(
                labelText: 'Naira a TGC token',
                prefixText: '₦',
                errorText: _errors['naira_per_credit'],
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _minimum,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
              decoration: InputDecoration(
                labelText: 'Smallest withdrawal',
                prefixText: '₦',
                errorText: _errors['min_withdrawal'],
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reason,
              maxLength: 1000,
              decoration: InputDecoration(labelText: 'Reason', errorText: _errors['reason']),
              onChanged: (_) => setState(() {}),
            ),
            if (_error != null) Text(_error!, style: const TextStyle(color: TgcgColors.danger)),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
      FilledButton(onPressed: _ready ? _save : null, child: const Text('Save rates')),
    ],
  );
}
