import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../access/access_widgets.dart';
import '../api/api_client.dart';
import '../api/backend.dart';
import '../api/wallet_repository.dart';
import '../ui/tgcg_design.dart';

/// The member's wallet: what TGCG owes them, its history, and the account it
/// is paid into, which is always in the name on their PVC.
class MyWalletPage extends StatefulWidget {
  const MyWalletPage({super.key});

  @override
  State<MyWalletPage> createState() => _MyWalletPageState();
}

class _MyWalletPageState extends State<MyWalletPage> {
  Future<MemberWallet>? _wallet;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _wallet ??= TgcgBackend.of(context)!.wallets.myWallet();
  }

  void _reload() => setState(() {
    _wallet = TgcgBackend.of(context)!.wallets.myWallet();
  });

  Future<void> _editAccount(MemberWallet wallet) async {
    final saved = await showDialog<MemberWallet>(
      context: context,
      builder: (_) => PayoutAccountDialog(wallet: wallet),
    );
    if (saved == null) return;
    setState(() {
      _wallet = Future.value(saved);
    });
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
      child: FutureBuilder<MemberWallet>(
        future: _wallet,
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
          final wallet = snapshot.data;
          if (wallet == null) return const Center(child: CircularProgressIndicator());
          if (!wallet.hasWallet) {
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
          return _WalletView(wallet: wallet, onEditAccount: () => _editAccount(wallet));
        },
      ),
    ),
  );
}

class _WalletView extends StatelessWidget {
  const _WalletView({required this.wallet, required this.onEditAccount});

  final MemberWallet wallet;
  final VoidCallback onEditAccount;

  @override
  Widget build(BuildContext context) {
    final account = wallet.payoutAccount;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TgcgSectionCard(
          title: 'Balance',
          child: Text(
            formatNaira(wallet.balance),
            style: const TextStyle(color: TgcgColors.ink, fontSize: 30, fontWeight: FontWeight.w900),
          ),
        ),
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
            ],
          ),
        ),
        const SizedBox(height: 12),
        TgcgSectionCard(
          title: 'History',
          child: wallet.entries.isEmpty
              ? const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('No payments yet.', style: TextStyle(color: TgcgColors.muted)),
                )
              : Column(
                  children: [
                    for (final entry in wallet.entries)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.south_west_rounded, color: TgcgColors.success),
                        title: Text(entry.purpose.isEmpty ? 'Payment from TGCG' : entry.purpose),
                        subtitle: Text(
                          [
                            if (entry.createdAt != null) formatMoment(entry.createdAt!),
                            'Balance ${formatNaira(entry.balanceAfter)}',
                          ].join(' · '),
                        ),
                        trailing: Text(
                          '+${formatNaira(entry.amount)}',
                          style: const TextStyle(
                            color: TgcgColors.success,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ],
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

/// Names the bank and account number. The account name is shown but cannot
/// be edited: it is always the member's name from their PVC.
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
    _bank = widget.wallet.payoutAccount?.bank;
    _number = TextEditingController(text: widget.wallet.payoutAccount?.accountNumber ?? '');
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
                    DropdownMenuItem(value: bank.code, child: Text(bank.name, overflow: TextOverflow.ellipsis)),
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
