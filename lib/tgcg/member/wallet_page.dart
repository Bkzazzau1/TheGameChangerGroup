import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../access/access_widgets.dart';
import '../api/api_client.dart';
import '../api/backend.dart';
import '../api/wallet_repository.dart';
import '../ui/tgcg_design.dart';

/// The member's wallet: what TGCG owes them, the credits they earned for
/// registering members, their withdrawals, the history, and the account it
/// is paid into, which is always in the name on their PVC.
class MyWalletPage extends StatefulWidget {
  const MyWalletPage({super.key});

  @override
  State<MyWalletPage> createState() => _MyWalletPageState();
}

typedef _Loaded = ({MemberWallet wallet, List<Withdrawal> withdrawals});

class _MyWalletPageState extends State<MyWalletPage> {
  Future<_Loaded>? _loaded;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loaded ??= _load();
  }

  Future<_Loaded> _load() async {
    final wallets = TgcgBackend.of(context)!.wallets;
    final wallet = await wallets.myWallet();
    // Only a verified member withdraws, so only they have withdrawals to list.
    final withdrawals = wallet.hasWallet ? (await wallets.myWithdrawals()).items : <Withdrawal>[];
    return (wallet: wallet, withdrawals: withdrawals);
  }

  void _reload() => setState(() {
    _loaded = _load();
  });

  /// Shows the wallet the server answered with, keeping the withdrawals.
  Future<void> _show(MemberWallet wallet) async {
    final withdrawals = (await _loaded)?.withdrawals ?? const <Withdrawal>[];
    if (!mounted) return;
    setState(() {
      _loaded = Future.value((wallet: wallet, withdrawals: withdrawals));
    });
  }

  Future<void> _editAccount(MemberWallet wallet) async {
    final saved = await showDialog<MemberWallet>(
      context: context,
      builder: (_) => PayoutAccountDialog(wallet: wallet),
    );
    if (saved != null) await _show(saved);
  }

  Future<void> _convert(MemberWallet wallet) async {
    final converted = await showDialog<MemberWallet>(
      context: context,
      builder: (_) => ConvertCreditsDialog(wallet: wallet),
    );
    if (converted == null || !mounted) return;
    showDone(context, 'TGC tokens converted. Your balance is ${formatNaira(converted.balance)}.');
    await _show(converted);
  }

  Future<void> _withdraw(MemberWallet wallet) async {
    final withdrawal = await showDialog<Withdrawal>(
      context: context,
      builder: (_) => WithdrawDialog(wallet: wallet),
    );
    if (withdrawal == null || !mounted) return;
    showDone(context, 'Withdrawal of ${formatNaira(withdrawal.amount)} sent for approval.');
    _reload();
  }

  Future<void> _cancelWithdrawal(Withdrawal withdrawal) async {
    final wallets = TgcgBackend.of(context)!.wallets;
    final sure = await confirmAction(
      context,
      title: 'Cancel this withdrawal?',
      message: '${formatNaira(withdrawal.amount)} goes back into your wallet.',
      action: 'Cancel withdrawal',
      destructive: true,
    );
    if (!sure) return;
    try {
      await wallets.cancelWithdrawal(withdrawal.id);
      if (!mounted) return;
      showDone(context, 'Withdrawal cancelled.');
      _reload();
    } catch (error) {
      if (mounted) showFailure(context, error);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: TgcgColors.canvas,
    appBar: AppBar(
      title: const Text('My wallet'),
      actions: [
        IconButton(tooltip: 'Refresh', onPressed: _reload, icon: const Icon(Icons.refresh_rounded)),
      ],
    ),
    body: SafeArea(
      child: FutureBuilder<_Loaded>(
        future: _loaded,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            final error = snapshot.error;
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: TgcgEmptyState(
                  icon: Icons.cloud_off_outlined,
                  title: 'Could not load your wallet',
                  message: error is ApiException
                      ? error.message
                      : 'Check your connection, then tap refresh at the top.',
                ),
              ),
            );
          }
          final loaded = snapshot.data;
          if (loaded == null) return const Center(child: CircularProgressIndicator());
          final wallet = loaded.wallet;
          if (!wallet.hasWallet &&
              wallet.credits == 0 &&
              wallet.entries.isEmpty &&
              wallet.registrations.registered == 0) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: TgcgEmptyState(
                  icon: Icons.account_balance_wallet_outlined,
                  title: 'No wallet yet',
                  message: 'Your wallet opens once your identity is checked.',
                ),
              ),
            );
          }
          return _WalletView(
            wallet: wallet,
            withdrawals: loaded.withdrawals,
            onEditAccount: () => _editAccount(wallet),
            onConvert: () => _convert(wallet),
            onWithdraw: () => _withdraw(wallet),
            onCancelWithdrawal: _cancelWithdrawal,
          );
        },
      ),
    ),
  );
}

/// Why the member cannot withdraw now; null when they can.
String? _withdrawBlocked(MemberWallet wallet, List<Withdrawal> withdrawals) {
  final account = wallet.payoutAccount;
  final minimum = wallet.rate?.minWithdrawal ?? '0.00';
  if (!wallet.hasWallet) return 'Your wallet opens once your identity is checked.';
  if (withdrawals.any((withdrawal) => withdrawal.isOpen)) {
    return 'A withdrawal of yours is still being handled.';
  }
  if (account == null) return 'Add a payout account to withdraw.';
  if (!account.payable) {
    return 'Withdrawals cannot be paid into ${account.bankName}. Choose another bank.';
  }
  if (nairaToKobo(wallet.balance) < nairaToKobo(minimum)) {
    return 'Withdrawals start at ${formatNaira(minimum)}.';
  }
  return null;
}

class _WalletView extends StatelessWidget {
  const _WalletView({
    required this.wallet,
    required this.withdrawals,
    required this.onEditAccount,
    required this.onConvert,
    required this.onWithdraw,
    required this.onCancelWithdrawal,
  });

  final MemberWallet wallet;
  final List<Withdrawal> withdrawals;
  final VoidCallback onEditAccount;
  final VoidCallback onConvert;
  final VoidCallback onWithdraw;
  final ValueChanged<Withdrawal> onCancelWithdrawal;

  @override
  Widget build(BuildContext context) {
    final account = wallet.payoutAccount;
    final blocked = _withdrawBlocked(wallet, withdrawals);
    final rate = wallet.rate;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (wallet.hasWallet) ...[
          TgcgSectionCard(
            title: 'Balance',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  formatNaira(wallet.balance),
                  style: const TextStyle(color: TgcgColors.ink, fontSize: 30, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: blocked == null ? onWithdraw : null,
                  icon: const Icon(Icons.north_east_rounded),
                  label: const Text('Withdraw'),
                ),
                if (blocked != null) ...[
                  const SizedBox(height: 6),
                  Text(blocked, style: const TextStyle(color: TgcgColors.muted)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        TgcgSectionCard(
          title: 'TGC tokens',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tgcTokens(wallet.credits),
                style: const TextStyle(color: TgcgColors.ink, fontSize: 24, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              Text(
                [
                  'Worth ${formatNaira(wallet.creditsWorth)} today',
                  if (rate != null) '${formatNaira(rate.nairaPerCredit)} each',
                ].join(' · '),
                style: const TextStyle(color: TgcgColors.muted),
              ),
              if (wallet.registrations.registered > 0) ...[
                const SizedBox(height: 10),
                _RegistrationLine(counts: wallet.registrations),
              ],
              if (wallet.hasWallet && wallet.credits > 0) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: onConvert,
                  icon: const Icon(Icons.swap_horiz_rounded),
                  label: const Text('Convert to naira'),
                ),
              ],
              if (!wallet.hasWallet) ...[
                const SizedBox(height: 8),
                const Text(
                  'Your wallet opens once your identity is checked.',
                  style: TextStyle(color: TgcgColors.muted),
                ),
              ],
            ],
          ),
        ),
        if (withdrawals.isNotEmpty) ...[
          const SizedBox(height: 12),
          TgcgSectionCard(
            title: 'Withdrawals',
            child: Column(
              children: [
                for (final withdrawal in withdrawals)
                  WithdrawalLine(
                    withdrawal: withdrawal,
                    onCancel: withdrawal.canCancel ? () => onCancelWithdrawal(withdrawal) : null,
                  ),
              ],
            ),
          ),
        ],
        if (wallet.hasWallet) ...[
          const SizedBox(height: 12),
          TgcgSectionCard(
            title: 'Payout account',
            trailing: TextButton(
              onPressed: onEditAccount,
              child: Text(account == null ? 'Add' : 'Change'),
            ),
            child: Column(
              children: [
                _Line('Account name', wallet.accountName),
                _Line('Bank', account?.bankName ?? 'Not added'),
                _Line('Account number', account?.accountNumber ?? 'Not added'),
                if (account != null && !account.payable)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text(
                      'Withdrawals cannot be paid into this bank. Choose another bank.',
                      style: TextStyle(color: TgcgColors.danger),
                    ),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        TgcgSectionCard(
          title: 'History',
          child: wallet.entries.isEmpty
              ? const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Nothing yet.', style: TextStyle(color: TgcgColors.muted)),
                )
              : Column(children: [for (final entry in wallet.entries) WalletEntryTile(entry: entry)]),
        ),
      ],
    );
  }
}

/// The people the member registered: a credit comes as each first signs in.
class _RegistrationLine extends StatelessWidget {
  const _RegistrationLine({required this.counts});

  final RegistrationCounts counts;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'You registered ${counts.registered} ${counts.registered == 1 ? 'person' : 'people'}',
        style: const TextStyle(color: TgcgColors.ink, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 2),
      Text(
        [
          if (counts.withCode > 0) '${counts.withCode} with your code',
          '${counts.signedIn} signed in',
          '${counts.waiting} not signed in yet',
          '${counts.credited} rewarded',
        ].join(' · '),
        style: const TextStyle(color: TgcgColors.muted),
      ),
    ],
  );
}

/// One line of a wallet's history: naira in or out, or TGC tokens earned.
class WalletEntryTile extends StatelessWidget {
  const WalletEntryTile({super.key, required this.entry, this.dense = false});

  final WalletEntry entry;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final kind = entry.kind;
    final out = entry.amount.startsWith('-');
    final (icon, color) = switch (kind) {
      WalletEntryKind.credit => (Icons.south_west_rounded, TgcgColors.success),
      WalletEntryKind.reward => (Icons.person_add_alt_1_rounded, TgcgColors.success),
      WalletEntryKind.conversion => (Icons.swap_horiz_rounded, TgcgColors.success),
      WalletEntryKind.withdrawal => (Icons.north_east_rounded, TgcgColors.ink),
      WalletEntryKind.refund => (Icons.undo_rounded, TgcgColors.success),
    };
    final title = entry.purpose.isNotEmpty
        ? entry.purpose
        : switch (kind) {
            WalletEntryKind.credit => 'Payment from TGCG',
            WalletEntryKind.reward => 'TGC tokens for registering a member',
            WalletEntryKind.conversion => 'TGC tokens converted to naira',
            WalletEntryKind.withdrawal => 'Withdrawal to the bank account',
            WalletEntryKind.refund => 'Withdrawal returned to the wallet',
          };
    final amount = kind == WalletEntryKind.reward
        ? '+${tgcTokens(entry.credits)}'
        : out
        ? formatNaira(entry.amount)
        : '+${formatNaira(entry.amount)}';
    return ListTile(
      dense: dense,
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: color),
      title: Text(title),
      subtitle: Text(
        [
          if (entry.createdAt != null) formatMoment(entry.createdAt!),
          if (kind == WalletEntryKind.reward && entry.creditsAfter != null)
            tgcTokens(entry.creditsAfter!)
          else
            'Balance ${formatNaira(entry.balanceAfter)}',
        ].join(' · '),
      ),
      trailing: Text(
        amount,
        style: TextStyle(color: out ? TgcgColors.ink : TgcgColors.success, fontWeight: FontWeight.w800),
      ),
    );
  }
}

TgcgStatusPill withdrawalPill(WithdrawalStatus status) => TgcgStatusPill(
  compact: true,
  label: withdrawalStatusLabel(status),
  color: switch (status) {
    WithdrawalStatus.paid => TgcgColors.success,
    WithdrawalStatus.pending || WithdrawalStatus.processing => TgcgColors.warning,
    WithdrawalStatus.failed || WithdrawalStatus.reversed || WithdrawalStatus.rejected =>
      TgcgColors.danger,
    WithdrawalStatus.cancelled => TgcgColors.muted,
  },
);

/// A withdrawal: how much, where to, where it stands, and why it was not paid.
class WithdrawalLine extends StatelessWidget {
  const WithdrawalLine({super.key, required this.withdrawal, this.onCancel});

  final Withdrawal withdrawal;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final why = [
      if (withdrawal.failureReason.isNotEmpty) withdrawal.failureReason,
      if (withdrawal.decisionReason.isNotEmpty) withdrawal.decisionReason,
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  formatNaira(withdrawal.amount),
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                ),
              ),
              withdrawalPill(withdrawal.status),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            [
              '${withdrawal.bankName} ${withdrawal.accountNumber}',
              if (withdrawal.createdAt != null) formatMoment(withdrawal.createdAt!),
            ].join(' · '),
            style: const TextStyle(color: TgcgColors.muted),
          ),
          if (why.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(why.join(' · '), style: const TextStyle(color: TgcgColors.muted)),
          ],
          if (onCancel != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(onPressed: onCancel, child: const Text('Cancel withdrawal')),
            ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 130,
          child: Text(label, style: const TextStyle(color: TgcgColors.muted)),
        ),
        Expanded(
          child: Text(value, style: const TextStyle(color: TgcgColors.ink, fontWeight: FontWeight.w700)),
        ),
      ],
    ),
  );
}

/// Turns credits into naira at today's rate.
class ConvertCreditsDialog extends StatefulWidget {
  const ConvertCreditsDialog({super.key, required this.wallet});

  final MemberWallet wallet;

  @override
  State<ConvertCreditsDialog> createState() => _ConvertCreditsDialogState();
}

class _ConvertCreditsDialogState extends State<ConvertCreditsDialog> {
  late final _credits = TextEditingController(text: '${widget.wallet.credits}');
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _credits.dispose();
    super.dispose();
  }

  int get _count => int.tryParse(_credits.text) ?? 0;

  bool get _ready => !_saving && _count >= 1 && _count <= widget.wallet.credits;

  Future<void> _save() async {
    if (!_ready) return;
    final route = ModalRoute.of(context);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final wallet = await TgcgBackend.of(context)!.wallets.convertCredits(_count);
      if (!mounted || route?.isCurrent != true) return;
      Navigator.pop(context, wallet);
    } catch (error) {
      if (!mounted || route?.isCurrent != true) return;
      setState(() {
        _saving = false;
        _error = error is ApiException
            ? error.fieldError('credits') ?? error.message
            : failureMessage(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final each = widget.wallet.rate?.nairaPerCredit ?? '0.00';
    final worth = _count * nairaToKobo(each);
    final naira = '${worth ~/ 100}.${(worth % 100).toString().padLeft(2, '0')}';
    return AlertDialog(
      title: const Text('Convert TGC tokens'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _credits,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: 'TGC tokens',
                helperText: 'You have ${widget.wallet.credits}; ${formatNaira(each)} each',
                errorText: _error,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Text(
              formatNaira(naira),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        FilledButton(onPressed: _ready ? _save : null, child: const Text('Convert')),
      ],
    );
  }
}

/// Asks for naira to be paid into the payout account.
class WithdrawDialog extends StatefulWidget {
  const WithdrawDialog({super.key, required this.wallet});

  final MemberWallet wallet;

  @override
  State<WithdrawDialog> createState() => _WithdrawDialogState();
}

class _WithdrawDialogState extends State<WithdrawDialog> {
  late final _amount = TextEditingController(text: widget.wallet.balance);
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  String get _value => _amount.text.replaceAll(',', '').trim();

  bool get _ready {
    if (_saving || _value.isEmpty) return false;
    final kobo = nairaToKobo(_value);
    final minimum = nairaToKobo(widget.wallet.rate?.minWithdrawal ?? '0.00');
    return kobo >= minimum && kobo > 0 && kobo <= nairaToKobo(widget.wallet.balance);
  }

  Future<void> _save() async {
    if (!_ready) return;
    final route = ModalRoute.of(context);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final withdrawal = await TgcgBackend.of(context)!.wallets.requestWithdrawal(_value);
      if (!mounted || route?.isCurrent != true) return;
      Navigator.pop(context, withdrawal);
    } catch (error) {
      if (!mounted || route?.isCurrent != true) return;
      setState(() {
        _saving = false;
        _error = error is ApiException
            ? error.fieldError('amount') ?? error.message
            : failureMessage(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = widget.wallet.payoutAccount;
    final minimum = widget.wallet.rate?.minWithdrawal ?? '0.00';
    return AlertDialog(
      title: const Text('Withdraw'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (account != null)
              Text(
                '${account.bankName} ${account.accountNumber}\n${widget.wallet.accountName}',
                style: const TextStyle(fontWeight: FontWeight.w700, height: 1.4),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
              decoration: InputDecoration(
                labelText: 'Amount',
                prefixText: '₦',
                helperText:
                    'Balance ${formatNaira(widget.wallet.balance)} · at least ${formatNaira(minimum)}',
                errorText: _error,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        FilledButton(onPressed: _ready ? _save : null, child: const Text('Send for approval')),
      ],
    );
  }
}

/// Names the bank and account number. The account name is shown but cannot
/// be edited: it is always the member's name from their PVC. Banks that
/// withdrawals cannot be paid into are shown but cannot be chosen.
class PayoutAccountDialog extends StatefulWidget {
  const PayoutAccountDialog({super.key, required this.wallet});

  final MemberWallet wallet;

  @override
  State<PayoutAccountDialog> createState() => _PayoutAccountDialogState();
}

class _PayoutAccountDialogState extends State<PayoutAccountDialog> {
  Future<List<Bank>>? _banks;
  String? _bank;
  late final TextEditingController _number;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final account = widget.wallet.payoutAccount;
    _bank = account != null && account.payable ? account.bank : null;
    _number = TextEditingController(text: account?.accountNumber ?? '');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _banks ??= TgcgBackend.of(context)!.wallets.banks();
  }

  @override
  void dispose() {
    _number.dispose();
    super.dispose();
  }

  bool get _ready => _bank != null && _number.text.length == 10 && !_saving;

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final wallet = await TgcgBackend.of(context)!.wallets.setPayoutAccount(
        bank: _bank!,
        accountNumber: _number.text,
      );
      if (mounted) Navigator.pop(context, wallet);
    } on ApiException catch (error) {
      setState(() {
        _saving = false;
        _error = error.fieldError('account_number') ?? error.fieldError('bank') ?? error.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Payout account'),
    content: SizedBox(
      width: 380,
      child: FutureBuilder<List<Bank>>(
        future: _banks,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Text('Could not load the banks. Try again later.');
          }
          final banks = snapshot.data;
          if (banks == null) {
            return const SizedBox(height: 80, child: Center(child: CircularProgressIndicator()));
          }
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                initialValue: widget.wallet.accountName,
                enabled: false,
                decoration: const InputDecoration(labelText: 'Account name'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _bank,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Bank'),
                items: [
                  for (final bank in banks)
                    DropdownMenuItem(
                      value: bank.code,
                      enabled: bank.payable,
                      child: Text(
                        bank.payable ? bank.name : '${bank.name} (cannot receive withdrawals)',
                        overflow: TextOverflow.ellipsis,
                        style: bank.payable ? null : const TextStyle(color: TgcgColors.muted),
                      ),
                    ),
                ],
                onChanged: (value) => setState(() => _bank = value),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _number,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(10),
                ],
                decoration: InputDecoration(labelText: 'Account number', errorText: _error),
                onChanged: (_) => setState(() {}),
              ),
            ],
          );
        },
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(onPressed: _ready ? _save : null, child: const Text('Save')),
    ],
  );
}
