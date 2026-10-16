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

class Bank {
  const Bank({required this.code, required this.name});

  final String code;
  final String name;

  factory Bank.fromJson(Map<String, dynamic> json) =>
      Bank(code: json['code'] as String, name: json['name'] as String);
}

/// Where a wallet is paid. Staff see only the last four digits.
class PayoutAccount {
  const PayoutAccount({required this.bank, required this.bankName, required this.accountNumber});

  final String bank;
  final String bankName;
  final String accountNumber;

  factory PayoutAccount.fromJson(Map<String, dynamic> json) => PayoutAccount(
    bank: json['bank'] as String,
    bankName: json['bank_name'] as String? ?? json['bank'] as String,
    accountNumber: json['account_number'] as String,
  );
}

/// One change to a wallet's balance.
class WalletEntry {
  const WalletEntry({
    required this.id,
    required this.amount,
    required this.balanceAfter,
    required this.purpose,
    this.createdAt,
  });

  final String id;
  final String amount;
  final String balanceAfter;
  final String purpose;
  final DateTime? createdAt;

  factory WalletEntry.fromJson(Map<String, dynamic> json) => WalletEntry(
    id: json['id'] as String,
    amount: json['amount'] as String,
    balanceAfter: json['balance_after'] as String,
    purpose: json['purpose'] as String? ?? '',
    createdAt: _date(json['created_at']),
  );
}

/// What TGCG owes a member, its history, and the account it is paid into.
class MemberWallet {
  const MemberWallet({
    required this.membershipNumber,
    required this.hasWallet,
    required this.accountName,
    required this.balance,
    this.payoutAccount,
    this.entries = const [],
  });

  final String membershipNumber;

  /// Only a member whose identity is verified has a wallet.
  final bool hasWallet;

  /// Always the member's name from their PVC; nobody can change it here.
  final String accountName;
  final String balance;
  final PayoutAccount? payoutAccount;
  final List<WalletEntry> entries;

  factory MemberWallet.fromJson(Map<String, dynamic> json) => MemberWallet(
    membershipNumber: json['membership_number'] as String,
    hasWallet: json['has_wallet'] as bool? ?? false,
    accountName: json['account_name'] as String? ?? '',
    balance: json['balance'] as String? ?? '0.00',
    payoutAccount: json['bank_account'] == null
        ? null
        : PayoutAccount.fromJson(json['bank_account'] as Map<String, dynamic>),
    entries: [
      for (final entry in (json['entries'] as List<dynamic>? ?? const []))
        WalletEntry.fromJson(entry as Map<String, dynamic>),
    ],
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
}
