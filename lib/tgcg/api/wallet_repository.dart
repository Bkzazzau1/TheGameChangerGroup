import 'access_repository.dart';
import 'api_client.dart';

DateTime? _date(Object? value) => value == null ? null : DateTime.tryParse('$value')?.toLocal();

/// An amount the server sends as naira with two decimals ("5000.50"), shown
/// as "₦5,000.50".
String formatNaira(String amount) {
  final negative = amount.startsWith('-');
  final digits = negative ? amount.substring(1) : amount;
  final dot = digits.indexOf('.');
  final whole = dot < 0 ? digits : digits.substring(0, dot);
  final kobo = dot < 0 ? '00' : digits.substring(dot + 1).padRight(2, '0');
  final grouped = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) grouped.write(',');
    grouped.write(whole[i]);
  }
  return '${negative ? '-' : ''}₦$grouped.$kobo';
}

/// Naira as the server writes it ("5000.50") in kobo, for comparing amounts.
int nairaToKobo(String amount) {
  final negative = amount.startsWith('-');
  final digits = negative ? amount.substring(1) : amount;
  final dot = digits.indexOf('.');
  final whole = int.tryParse(dot < 0 ? digits : digits.substring(0, dot)) ?? 0;
  final kobo = dot < 0 ? 0 : int.tryParse(digits.substring(dot + 1).padRight(2, '0').substring(0, 2)) ?? 0;
  final value = whole * 100 + kobo;
  return negative ? -value : value;
}

class Bank {
  const Bank({required this.code, required this.name, this.payable = true});

  final String code;
  final String name;

  /// Withdrawals can be paid into this bank (Paystack does not pay every bank).
  final bool payable;

  factory Bank.fromJson(Map<String, dynamic> json) => Bank(
    code: json['code'] as String,
    name: json['name'] as String,
    payable: json['payable'] as bool? ?? true,
  );
}

/// Where a wallet is paid. Staff see only the last four digits.
class PayoutAccount {
  const PayoutAccount({
    required this.bank,
    required this.bankName,
    required this.accountNumber,
    this.payable = true,
  });

  final String bank;
  final String bankName;
  final String accountNumber;

  /// Withdrawals can be paid into this account's bank.
  final bool payable;

  factory PayoutAccount.fromJson(Map<String, dynamic> json) => PayoutAccount(
    bank: json['bank'] as String,
    bankName: json['bank_name'] as String? ?? json['bank'] as String,
    accountNumber: json['account_number'] as String,
    payable: json['payable'] as bool? ?? true,
  );
}

/// What registering a member earns, what a credit is worth in naira, and the
/// smallest withdrawal. [setBy] and [createdAt] are null for the starting rates.
class CreditRate {
  const CreditRate({
    required this.creditsPerRegistration,
    required this.nairaPerCredit,
    required this.minWithdrawal,
    this.reason = '',
    this.setBy,
    this.createdAt,
  });

  final int creditsPerRegistration;
  final String nairaPerCredit;
  final String minWithdrawal;
  final String reason;
  final String? setBy;
  final DateTime? createdAt;

  factory CreditRate.fromJson(Map<String, dynamic> json) => CreditRate(
    creditsPerRegistration: (json['credits_per_registration'] as num?)?.toInt() ?? 0,
    nairaPerCredit: json['naira_per_credit'] as String? ?? '0.00',
    minWithdrawal: json['min_withdrawal'] as String? ?? '0.00',
    reason: json['reason'] as String? ?? '',
    setBy: json['set_by'] as String?,
    createdAt: _date(json['created_at']),
  );
}

/// The kinds of change a wallet records (the server's WalletEntry.Kind).
enum WalletEntryKind { credit, reward, conversion, withdrawal, refund }

/// One change to a wallet: naira in (positive) or out (negative), credits
/// earned or converted.
class WalletEntry {
  const WalletEntry({
    required this.id,
    required this.amount,
    required this.balanceAfter,
    required this.purpose,
    this.kind = WalletEntryKind.credit,
    this.credits = 0,
    this.creditsAfter,
    this.createdAt,
  });

  final String id;
  final WalletEntryKind kind;
  final String amount;
  final String balanceAfter;
  final int credits;
  final int? creditsAfter;
  final String purpose;
  final DateTime? createdAt;

  factory WalletEntry.fromJson(Map<String, dynamic> json) => WalletEntry(
    id: json['id'] as String,
    kind: WalletEntryKind.values.asNameMap()[json['kind']] ?? WalletEntryKind.credit,
    amount: json['amount'] as String,
    balanceAfter: json['balance_after'] as String,
    credits: (json['credits'] as num?)?.toInt() ?? 0,
    creditsAfter: (json['credits_after'] as num?)?.toInt(),
    purpose: json['purpose'] as String? ?? '',
    createdAt: _date(json['created_at']),
  );
}

/// What TGCG owes a member, their credits, the history, and the account it
/// is paid into.
class MemberWallet {
  const MemberWallet({
    required this.membershipNumber,
    required this.hasWallet,
    required this.accountName,
    required this.balance,
    this.credits = 0,
    this.creditsWorth = '0.00',
    this.rate,
    this.payoutAccount,
    this.entries = const [],
  });

  final String membershipNumber;

  /// A verified member: may convert credits and withdraw. Credits are kept before.
  final bool hasWallet;

  /// Always the member's name from their PVC; nobody can change it here.
  final String accountName;
  final String balance;

  /// Credits earned for registering members, not yet converted.
  final int credits;

  /// What [credits] are worth in naira at today's [rate].
  final String creditsWorth;
  final CreditRate? rate;
  final PayoutAccount? payoutAccount;
  final List<WalletEntry> entries;

  factory MemberWallet.fromJson(Map<String, dynamic> json) => MemberWallet(
    membershipNumber: json['membership_number'] as String,
    hasWallet: json['has_wallet'] as bool? ?? false,
    accountName: json['account_name'] as String? ?? '',
    balance: json['balance'] as String? ?? '0.00',
    credits: (json['credits'] as num?)?.toInt() ?? 0,
    creditsWorth: json['credits_worth'] as String? ?? '0.00',
    rate: json['rate'] == null ? null : CreditRate.fromJson(json['rate'] as Map<String, dynamic>),
    payoutAccount: json['bank_account'] == null
        ? null
        : PayoutAccount.fromJson(json['bank_account'] as Map<String, dynamic>),
    entries: [
      for (final entry in (json['entries'] as List<dynamic>? ?? const []))
        WalletEntry.fromJson(entry as Map<String, dynamic>),
    ],
  );
}

/// The stages of a withdrawal (the server's Withdrawal.Status).
enum WithdrawalStatus { pending, processing, paid, failed, reversed, rejected, cancelled }

String withdrawalStatusLabel(WithdrawalStatus status) => switch (status) {
  WithdrawalStatus.pending => 'Awaiting approval',
  WithdrawalStatus.processing => 'Being paid',
  WithdrawalStatus.paid => 'Paid',
  WithdrawalStatus.failed => 'Not paid',
  WithdrawalStatus.reversed => 'Returned by the bank',
  WithdrawalStatus.rejected => 'Rejected',
  WithdrawalStatus.cancelled => 'Cancelled',
};

/// Naira a member asked to have paid into their account: approved by a
/// second person, then paid through Paystack. Staff see only the last four
/// digits of the account.
class Withdrawal {
  const Withdrawal({
    required this.id,
    required this.member,
    required this.memberName,
    required this.amount,
    required this.bankName,
    required this.accountNumber,
    required this.status,
    this.createdAt,
    this.decidedBy,
    this.decidedAt,
    this.decisionReason = '',
    this.bankAccountName = '',
    this.failureReason = '',
    this.finishedAt,
    this.canDecide = false,
    this.canCancel = false,
  });

  final String id;
  final String member;
  final String memberName;
  final String amount;
  final String bankName;
  final String accountNumber;
  final WithdrawalStatus status;
  final DateTime? createdAt;
  final String? decidedBy;
  final DateTime? decidedAt;
  final String decisionReason;

  /// The bank's own name for the account, once asked.
  final String bankAccountName;

  /// Why it was not paid.
  final String failureReason;
  final DateTime? finishedAt;

  /// This account may approve or reject it: a different person with the power.
  final bool canDecide;

  /// The member's own, not yet approved.
  final bool canCancel;

  /// Still awaiting approval or being paid.
  bool get isOpen => status == WithdrawalStatus.pending || status == WithdrawalStatus.processing;

  factory Withdrawal.fromJson(Map<String, dynamic> json) => Withdrawal(
    id: json['id'] as String,
    member: json['member'] as String? ?? '',
    memberName: json['member_name'] as String? ?? '',
    amount: json['amount'] as String,
    bankName: json['bank_name'] as String? ?? json['bank'] as String? ?? '',
    accountNumber: json['account_number'] as String? ?? '',
    status: WithdrawalStatus.values.asNameMap()[json['status']] ?? WithdrawalStatus.pending,
    createdAt: _date(json['created_at']),
    decidedBy: json['decided_by'] as String?,
    decidedAt: _date(json['decided_at']),
    decisionReason: json['decision_reason'] as String? ?? '',
    bankAccountName: json['bank_account_name'] as String? ?? '',
    failureReason: json['failure_reason'] as String? ?? '',
    finishedAt: _date(json['finished_at']),
    canDecide: json['can_decide'] as bool? ?? false,
    canCancel: json['can_cancel'] as bool? ?? false,
  );
}

/// A payment to a member's wallet: requested by one person, decided by another.
class WalletPayment {
  const WalletPayment({
    required this.id,
    required this.member,
    required this.memberName,
    required this.amount,
    required this.purpose,
    required this.status,
    required this.requestedBy,
    this.createdAt,
    this.decidedBy,
    this.decidedAt,
    this.decisionReason = '',
    this.canDecide = false,
    this.canCancel = false,
  });

  final String id;
  final String member;
  final String memberName;
  final String amount;
  final String purpose;

  /// pending, approved, rejected or cancelled.
  final String status;
  final String requestedBy;
  final DateTime? createdAt;
  final String? decidedBy;
  final DateTime? decidedAt;
  final String decisionReason;

  /// This account may approve or reject it: a different person with the power.
  final bool canDecide;

  /// This account requested it, and it is still pending.
  final bool canCancel;

  factory WalletPayment.fromJson(Map<String, dynamic> json) => WalletPayment(
    id: json['id'] as String,
    member: json['member'] as String,
    memberName: json['member_name'] as String? ?? '',
    amount: json['amount'] as String,
    purpose: json['purpose'] as String? ?? '',
    status: json['status'] as String,
    requestedBy: json['requested_by'] as String? ?? '',
    createdAt: _date(json['created_at']),
    decidedBy: json['decided_by'] as String?,
    decidedAt: _date(json['decided_at']),
    decisionReason: json['decision_reason'] as String? ?? '',
    canDecide: json['can_decide'] as bool? ?? false,
    canCancel: json['can_cancel'] as bool? ?? false,
  );
}

/// Members' wallets: the member's own, and payments for finance staff.
class WalletRepository {
  WalletRepository(this.client);

  final ApiClient client;

  Future<MemberWallet> myWallet() async =>
      MemberWallet.fromJson(await client.get('me/wallet/') as Map<String, dynamic>);

  /// The account name is not sent: the server always uses the member's own.
  Future<MemberWallet> setPayoutAccount({required String bank, required String accountNumber}) async =>
      MemberWallet.fromJson(
        await client.put(
          'me/wallet/bank-account/',
          body: {'bank': bank, 'account_number': accountNumber.replaceAll(' ', '')},
        ) as Map<String, dynamic>,
      );

  Future<List<Bank>> banks() async => [
    for (final bank in await client.get('wallets/banks/') as List<dynamic>)
      Bank.fromJson(bank as Map<String, dynamic>),
  ];

  Future<MemberWallet> memberWallet(String membershipNumber) async => MemberWallet.fromJson(
    await client.get('wallets/${membershipNumber.trim()}/') as Map<String, dynamic>,
  );

  Future<ApiPage<WalletPayment>> payments({String? status, String search = '', int offset = 0}) async =>
      ApiPage.fromJson(
        await client.get(
          'wallet-payments/',
          query: {
            if (status != null) 'status': status,
            if (search.trim().isNotEmpty) 'search': search.trim(),
            if (offset > 0) 'offset': '$offset',
          },
        ),
        WalletPayment.fromJson,
      );

  Future<WalletPayment> requestPayment({
    required String member,
    required String amount,
    required String purpose,
  }) async => WalletPayment.fromJson(
    await client.post(
      'wallet-payments/',
      body: {'member': member.trim(), 'amount': amount.trim(), 'purpose': purpose.trim()},
    ) as Map<String, dynamic>,
  );

  Future<WalletPayment> _decide(String id, String decision, String reason) async =>
      WalletPayment.fromJson(
        await client.post('wallet-payments/$id/$decision/', body: {'reason': reason.trim()})
            as Map<String, dynamic>,
      );

  Future<WalletPayment> approve(String id) => _decide(id, 'approve', '');

  Future<WalletPayment> reject(String id, String reason) => _decide(id, 'reject', reason);

  Future<WalletPayment> cancel(String id) => _decide(id, 'cancel', '');

  // --- Credits and withdrawals -------------------------------------------------

  /// Converts [credits] to naira at today's rate (a verified member only).
  Future<MemberWallet> convertCredits(int credits) async => MemberWallet.fromJson(
    await client.post('me/wallet/convert/', body: {'credits': credits}) as Map<String, dynamic>,
  );

  /// The member's own withdrawals, newest first.
  Future<ApiPage<Withdrawal>> myWithdrawals() async =>
      ApiPage.fromJson(await client.get('me/wallet/withdrawals/'), Withdrawal.fromJson);

  /// Takes [amount] naira out of the wallet at once, to be paid into the
  /// payout account once someone approves. One at a time.
  Future<Withdrawal> requestWithdrawal(String amount) async => Withdrawal.fromJson(
    await client.post('me/wallet/withdrawals/', body: {'amount': amount.trim()})
        as Map<String, dynamic>,
  );

  /// Takes back the member's own withdrawal, until it is approved.
  Future<Withdrawal> cancelWithdrawal(String id) async => Withdrawal.fromJson(
    await client.post('me/wallet/withdrawals/$id/cancel/') as Map<String, dynamic>,
  );

  /// Withdrawals by members in this account's areas.
  Future<ApiPage<Withdrawal>> withdrawals({
    String? status,
    String search = '',
    int offset = 0,
  }) async => ApiPage.fromJson(
    await client.get(
      'withdrawals/',
      query: {
        if (status != null) 'status': status,
        if (search.trim().isNotEmpty) 'search': search.trim(),
        if (offset > 0) 'offset': '$offset',
      },
    ),
    Withdrawal.fromJson,
  );

  Future<Withdrawal> _decideWithdrawal(String id, String decision, String reason) async =>
      Withdrawal.fromJson(
        await client.post('withdrawals/$id/$decision/', body: {'reason': reason.trim()})
            as Map<String, dynamic>,
      );

  /// Approves, and the server pays it through Paystack at once if the bank
  /// holds the account in the member's name.
  Future<Withdrawal> approveWithdrawal(String id) => _decideWithdrawal(id, 'approve', '');

  Future<Withdrawal> rejectWithdrawal(String id, String reason) =>
      _decideWithdrawal(id, 'reject', reason);

  /// The current credit rates and the earlier ones, newest first.
  Future<({CreditRate current, List<CreditRate> history})> creditRates() async {
    final json = await client.get('wallets/credit-rates/') as Map<String, dynamic>;
    return (
      current: CreditRate.fromJson(json['current'] as Map<String, dynamic>),
      history: [
        for (final rate in json['history'] as List<dynamic>? ?? const [])
          CreditRate.fromJson(rate as Map<String, dynamic>),
      ],
    );
  }

  /// New rates, from now on (National Administrators). 0 credits per
  /// registration pauses the incentive.
  Future<CreditRate> setCreditRates({
    required int creditsPerRegistration,
    required String nairaPerCredit,
    required String minWithdrawal,
    required String reason,
  }) async => CreditRate.fromJson(
    await client.post(
      'wallets/credit-rates/',
      body: {
        'credits_per_registration': creditsPerRegistration,
        'naira_per_credit': nairaPerCredit.trim(),
        'min_withdrawal': minWithdrawal.trim(),
        'reason': reason.trim(),
      },
    ) as Map<String, dynamic>,
  );
}
