import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../access/access_widgets.dart';
import '../api/access_repository.dart';
import '../api/api_client.dart';
import '../api/backend.dart';
import '../api/wallet_repository.dart';
import '../domain/permissions.dart';
import '../session.dart';
import '../ui/tgcg_design.dart';

/// Payments to members' wallets in the account's areas: requested by one
/// person, approved or rejected by another.
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

class _WalletPaymentsPageState extends State<WalletPaymentsPage> {
  int _filter = 0;
  Future<ApiPage<WalletPayment>>? _payments;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (TgcgBackend.of(context) != null) _payments ??= _load();
  }

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
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('Wallets', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
        const SizedBox(height: 12),
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
      ],
    );
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
                const SizedBox(height: 8),
                for (final entry in wallet.entries)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(entry.purpose.isEmpty ? 'Payment from TGCG' : entry.purpose),
                    subtitle: entry.createdAt == null ? null : Text(formatMoment(entry.createdAt!)),
                    trailing: Text('+${formatNaira(entry.amount)}'),
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
    );
  }
}
