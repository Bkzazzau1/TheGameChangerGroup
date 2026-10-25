import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../domain/models.dart';
import 'api_client.dart';
import 'auth_repository.dart' show geographicScopeFromJson;
import 'meetings_repository.dart' show scopeInput;
import 'reference_repository.dart';

/// A member's polling unit, as the member app shows it.
class MemberUnit {
  const MemberUnit({
    required this.code,
    required this.name,
    required this.ward,
    required this.lga,
    required this.state,
    this.location = '',
    this.directions,
  });

  final String code;
  final String name;
  final String location;
  final String ward;
  final String lga;
  final String state;

  /// Where to go on election day; null until the unit is mapped.
  final UnitDirections? directions;

  String get area => '$ward ward, $lga LGA, $state State';

  factory MemberUnit.fromJson(Map<String, dynamic> json) => MemberUnit(
        code: json['code'] as String,
        name: json['name'] as String,
        location: (json['location'] as String?) ?? '',
        ward: json['ward'] as String,
        lga: json['lga'] as String,
        state: json['state'] as String,
        directions: UnitDirections.fromJson(json['navigation']),
      );
}

/// The signed-in member's card and profile (`/me/member/`).
class MemberCard {
  const MemberCard({
    required this.membershipNumber,
    required this.fullName,
    required this.phoneNumber,
    required this.qrToken,
    required this.memberSince,
    this.email = '',
    this.whatsappNumber = '',
    this.vin,
    this.hasPvc = false,
    this.gender = '',
    this.dateOfBirth,
    this.occupation = '',
    this.status = '',
    this.membershipState = 'active',
    this.verificationStatus = '',
    this.pollingUnit,
    this.hasPhoto = false,
    this.hasCardPhoto = false,
    this.disabilities = const [],
    this.disabilityOther = '',
    this.cardMissing = const [],
  });

  final String membershipNumber;
  final String fullName;
  final String phoneNumber;
  final String email;

  /// Empty when WhatsApp is on [phoneNumber].
  final String whatsappNumber;

  /// The PVC's VIN with most characters hidden.
  final String? vin;
  final bool hasPvc;
  final String gender;
  final DateTime? dateOfBirth;
  final String occupation;
  final String status;

  /// active, suspended or deactivated.
  final String membershipState;

  /// Whether a coordinator has checked the member's identity. Membership
  /// needs no check; working as an agent or holding a role does.
  final String verificationStatus;
  final MemberUnit? pollingUnit;
  final DateTime memberSince;

  /// A selfie, and a photo of the PVC, are on record.
  final bool hasPhoto;
  final bool hasCardPhoto;

  /// Codes from [disabilityKinds], and the member's words for "other".
  final List<String> disabilities;
  final String disabilityOther;

  /// What the member must add before downloading the card (codes in
  /// [cardNeeds]); empty when it is ready.
  final List<String> cardMissing;

  bool get identityChecked => verificationStatus == 'verified';

  /// Signed value printed as the card's QR code; staff scan it to verify.
  final String qrToken;

  factory MemberCard.fromJson(Map<String, dynamic> json) {
    final unit = json['polling_unit'];
    return MemberCard(
      membershipNumber: json['membership_number'] as String,
      fullName: json['full_name'] as String,
      phoneNumber: json['phone_number'] as String,
      email: (json['email'] as String?) ?? '',
      whatsappNumber: (json['whatsapp_number'] as String?) ?? '',
      vin: json['vin'] as String?,
      hasPvc: json['has_pvc'] as bool? ?? false,
      gender: (json['gender'] as String?) ?? '',
      dateOfBirth: DateTime.tryParse((json['date_of_birth'] as String?) ?? ''),
      occupation: (json['occupation'] as String?) ?? '',
      status: (json['status'] as String?) ?? '',
      membershipState: (json['membership_state'] as String?) ?? 'active',
      verificationStatus: (json['verification_status'] as String?) ?? '',
      pollingUnit: unit is Map<String, dynamic> ? MemberUnit.fromJson(unit) : null,
      memberSince: DateTime.parse(json['member_since'] as String),
      hasPhoto: json['photo_url'] != null,
      hasCardPhoto: json['has_card_photo'] as bool? ?? false,
      // Not given for a member someone else registered: the card is theirs.
      qrToken: (json['qr_token'] as String?) ?? '',
      disabilities: [for (final kind in (json['disabilities'] as List?) ?? const []) '$kind'],
      disabilityOther: (json['disability_other'] as String?) ?? '',
      cardMissing: [for (final need in (json['card_missing'] as List?) ?? const []) '$need'],
    );
  }
}

/// The kinds of disability a member may record, as the server names them.
const disabilityKinds = [
  ('physical', 'Physical / mobility'),
  ('visual', 'Visual'),
  ('hearing', 'Hearing'),
  ('speech', 'Speech'),
  ('intellectual', 'Intellectual'),
  ('psychosocial', 'Psychosocial (mental health)'),
  ('albinism', 'Albinism'),
  ('other', 'Other'),
];

/// A member's disabilities in words, e.g. "Visual, Other: epilepsy".
String disabilityText(List<String> kinds, String other) => [
      for (final (code, label) in disabilityKinds)
        if (kinds.contains(code)) code == 'other' && other.isNotEmpty ? 'Other: $other' : label,
    ].join(', ');

/// What the card still needs, as the server lists it in `card_missing`.
const cardNeeds = {
  'active_membership': 'an active membership',
  'full_name': 'your full name',
  'photo': 'a photo of you',
  'pvc_photo': 'a photo of your PVC',
  'gender': 'your gender',
  'date_of_birth': 'your date of birth',
};

/// The member's polling unit and how many members share it (`/me/polling-unit/`).
class MyPollingUnit {
  const MyPollingUnit({this.unit, this.membersInUnit = 0, this.membersInWard = 0});

  final MemberUnit? unit;
  final int membersInUnit;
  final int membersInWard;

  factory MyPollingUnit.fromJson(Map<String, dynamic> json) {
    final unit = json['polling_unit'];
    return MyPollingUnit(
      unit: unit is Map<String, dynamic> ? MemberUnit.fromJson(unit) : null,
      membersInUnit: (json['members_in_unit'] as int?) ?? 0,
      membersInWard: (json['members_in_ward'] as int?) ?? 0,
    );
  }
}

class MemberAnnouncement {
  const MemberAnnouncement({
    required this.id,
    required this.title,
    required this.body,
    required this.author,
    this.publishedAt,
  });

  final String id;
  final String title;
  final String body;
  final String author;
  final DateTime? publishedAt;

  factory MemberAnnouncement.fromJson(Map<String, dynamic> json) => MemberAnnouncement(
        id: json['id'] as String,
        title: json['title'] as String,
        body: json['body'] as String,
        author: (json['author'] as String?) ?? '',
        publishedAt: DateTime.tryParse('${json['published_at']}'),
      );
}

/// Kinds of party work a member can offer (matches the server's choices).
/// Volunteering is not a route to becoming an agent: coordinators accredit
/// agents separately.
const volunteerInterests = {
  'mobilisation': 'Mobilisation and door-to-door',
  'campaign': 'Campaign events and rallies',
  'logistics': 'Logistics and transport',
  'publicity': 'Publicity and social media',
  'electionDay': 'Election-day support',
};

/// A member's offer of party work, and what their coordinators said.
class VolunteerOffer {
  const VolunteerOffer({
    required this.id,
    required this.interests,
    required this.status,
    required this.createdAt,
    this.message = '',
    this.decisionReason = '',
  });

  final String id;
  final List<String> interests;

  /// pending, accepted, declined or withdrawn.
  final String status;
  final String message;
  final String decisionReason;
  final DateTime createdAt;

  bool get isOpen => status == 'pending';

  factory VolunteerOffer.fromJson(Map<String, dynamic> json) => VolunteerOffer(
        id: json['id'] as String,
        interests: [...(json['interests'] as List<dynamic>? ?? const []).cast<String>()],
        status: json['status'] as String,
        message: (json['message'] as String?) ?? '',
        decisionReason: (json['decision_reason'] as String?) ?? '',
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

/// Everything collected on the registration screens. As on USSD, joining
/// needs the phone, the VIN and polling unit code, a name and a PIN; the
/// rest may be left out.
class MemberRegistration {
  const MemberRegistration({
    required this.phoneNumber,
    required this.vin,
    required this.fullName,
    required this.pin,
    this.delim = '',
    this.pollingUnit = '',
    this.code = '',
    this.gender,
    this.selfie,
    this.pvcImage,
    this.dateOfBirth,
    this.occupation = '',
    this.email = '',
    this.disabilities = const [],
    this.disabilityOther = '',
    this.referralCode = '',
  });

  final String phoneNumber;

  /// The 7-digit code of the member who invited them, if any.
  final String referralCode;

  /// The SMS code, when the server asked for one.
  final String code;
  final String vin;

  /// The polling unit code from the PVC; or else [pollingUnit], the code of a
  /// unit found by name, which the server records as such.
  final String delim;
  final String pollingUnit;
  final String fullName;

  /// male or female, if given.
  final String? gender;
  final DateTime? dateOfBirth;
  final String occupation;
  final String email;
  final String pin;
  final ({Uint8List bytes, String name})? selfie;
  final ({Uint8List bytes, String name})? pvcImage;

  /// Codes from [disabilityKinds], if the member chose to give them.
  final List<String> disabilities;
  final String disabilityOther;
}

/// A member's referral code and link, and how many joined with them.
class MyReferral {
  const MyReferral({
    required this.code,
    required this.link,
    this.joined = 0,
    this.signedIn = 0,
    this.credited = 0,
  });

  final String code;

  /// Opens joining in the web app with the code filled in.
  final String link;
  final int joined;
  final int signedIn;
  final int credited;

  factory MyReferral.fromJson(Map<String, dynamic> json) => MyReferral(
    code: json['code'] as String,
    link: json['link'] as String? ?? '',
    joined: (json['joined'] as num?)?.toInt() ?? 0,
    signedIn: (json['signed_in'] as num?)?.toInt() ?? 0,
    credited: (json['credited'] as num?)?.toInt() ?? 0,
  );
}

/// The details a member sends from their one PVC scan, checked against the
/// card. A detail the card did not show may be left out; theirs then stays.
class PvcScanDetails {
  const PvcScanDetails({
    required this.photo,
    required this.fullName,
    required this.vin,
    required this.delim,
    this.gender,
    this.dateOfBirth,
    this.occupation = '',
  });

  final ({Uint8List bytes, String name}) photo;
  final String fullName;
  final String vin;

  /// The polling unit code on the card.
  final String delim;
  final String? gender;
  final DateTime? dateOfBirth;
  final String occupation;
}

/// How a member's PVC scan went.
class PvcScanResult {
  const PvcScanResult({
    required this.id,
    required this.status,
    required this.createdAt,
    this.decisionReason = '',
  });

  final String id;

  /// applied (at once), pending (waiting for a coordinator), approved,
  /// rejected or withdrawn.
  final String status;
  final String decisionReason;
  final DateTime createdAt;

  bool get isPending => status == 'pending';

  factory PvcScanResult.fromJson(Map<String, dynamic> json) => PvcScanResult(
        id: json['id'] as String,
        status: json['status'] as String,
        decisionReason: (json['decision_reason'] as String?) ?? '',
        createdAt: DateTime.tryParse((json['created_at'] as String?) ?? '') ?? DateTime.now(),
      );
}

/// Whether the member may make their one PVC scan: not once a card is on
/// record, nor while a scan waits.
class PvcScanState {
  const PvcScanState({required this.canScan, this.latest});

  final bool canScan;
  final PvcScanResult? latest;

  factory PvcScanState.fromJson(Map<String, dynamic> json) => PvcScanState(
        canScan: json['can_scan'] as bool? ?? false,
        latest: json['latest'] is Map<String, dynamic>
            ? PvcScanResult.fromJson(json['latest'] as Map<String, dynamic>)
            : null,
      );
}

/// A date as the server takes it: YYYY-MM-DD.
String _day(DateTime date) => '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

/// The 11 digits people write for a Nigerian number: 08031234567 for
/// +2348031234567. A member someone else registered signs in with it as
/// the password.
String localPhone(String phone) {
  final digits = phone.replaceAll(RegExp(r'\D'), '');
  return digits.length == 13 && digits.startsWith('234') ? '0${digits.substring(3)}' : phone;
}

/// One member's details, photo and PVC scan: the signed-in member's own
/// (`/me/member/`), or those of a member they registered
/// (`/me/registered/<number>/`), which they may complete until the identity
/// is checked.
class MemberProfile {
  const MemberProfile(this.client, this.base);
  final ApiClient client;

  /// Where the details are, ending in a slash.
  final String base;

  Future<MemberCard> card() async => MemberCard.fromJson(await client.get(base) as Map<String, dynamic>);

  Future<MemberCard> _update(Map<String, Object?> fields) async =>
      MemberCard.fromJson(await client.patch(base, body: fields) as Map<String, dynamic>);

  Future<MemberCard> updateEmail(String email) => _update({'email': email});

  /// Empty means WhatsApp is on the member's phone number.
  Future<MemberCard> updateWhatsappNumber(String number) => _update({'whatsapp_number': number.trim()});

  Future<MemberCard> updateOccupation(String occupation) => _update({'occupation': occupation});

  /// male or female. Like the date of birth, it can be added at any time, and
  /// changed until the member's identity is checked.
  Future<MemberCard> updateGender(String gender) => _update({'gender': gender});

  Future<MemberCard> updateDateOfBirth(DateTime date) => _update({'date_of_birth': _day(date)});

  /// Codes from [disabilityKinds] (none to take them back) and the words
  /// for "other". The member may change them at any time.
  Future<MemberCard> updateDisabilities(List<String> kinds, String other) =>
      _update({'disabilities': kinds, 'disability_other': other});

  Future<Uint8List> photo() => client.getBytes('${base}photo/');

  /// Adds the selfie left out when joining. It can be replaced until the
  /// member's identity is checked; after that a coordinator changes it.
  Future<MemberCard> addPhoto(({Uint8List bytes, String name}) photo) async =>
      MemberCard.fromJson(
        await client.postMultipart(
          '${base}photo/',
          fields: const {},
          files: () async => [http.MultipartFile.fromBytes('photo', photo.bytes, filename: photo.name)],
        ) as Map<String, dynamic>,
      );

  /// Whether the member may make their one PVC scan, and how the last went.
  Future<PvcScanState> pvcScan() async =>
      PvcScanState.fromJson(await client.get('${base}pvc-scan/') as Map<String, dynamic>);

  /// Sends the details read off the PVC, which replace the typed ones: at
  /// once, or after a coordinator's second check once the identity is checked.
  Future<PvcScanResult> sendPvcScan(PvcScanDetails scan) async {
    final dob = scan.dateOfBirth;
    return PvcScanResult.fromJson(
      await client.postMultipart(
        '${base}pvc-scan/',
        fields: {
          'full_name': scan.fullName,
          'vin': scan.vin,
          'delim': scan.delim,
          if (scan.gender case final gender? when gender.isNotEmpty) 'gender': gender,
          if (dob != null) 'date_of_birth': _day(dob),
          if (scan.occupation.isNotEmpty) 'occupation': scan.occupation,
        },
        files: () async => [
          http.MultipartFile.fromBytes('pvc_image', scan.photo.bytes, filename: scan.photo.name),
        ],
      ) as Map<String, dynamic>,
    );
  }

  /// Takes back a scan still waiting for a coordinator, to scan again.
  Future<PvcScanResult> withdrawPvcScan(String id) async => PvcScanResult.fromJson(
        await client.post('${base}pvc-scan/$id/withdraw/') as Map<String, dynamic>,
      );
}

/// A member the signed-in person registered, in their list (`/me/registered/`).
class RegisteredMember {
  const RegisteredMember({
    required this.membershipNumber,
    required this.fullName,
    required this.phoneNumber,
    this.place = GeographicScope.nigeria,
    this.verificationStatus = '',
    this.membershipState = 'active',
    this.missing = const [],
    this.canComplete = false,
    this.signedIn = false,
  });

  final String membershipNumber;
  final String fullName;
  final String phoneNumber;

  /// Nigeria until a place is given or their PVC is scanned.
  final GeographicScope place;
  final String verificationStatus;
  final String membershipState;

  /// What their card still needs (codes in [cardNeeds]).
  final List<String> missing;

  /// The person who registered them may complete the registration until the
  /// identity is checked.
  final bool canComplete;
  final bool signedIn;

  factory RegisteredMember.fromJson(Map<String, dynamic> json) => RegisteredMember(
        membershipNumber: json['membership_number'] as String,
        fullName: json['full_name'] as String,
        phoneNumber: json['phone_number'] as String,
        place: json['scope'] is Map<String, dynamic>
            ? geographicScopeFromJson(json['scope'] as Map<String, dynamic>)
            : GeographicScope.nigeria,
        verificationStatus: (json['verification_status'] as String?) ?? '',
        membershipState: (json['membership_state'] as String?) ?? 'active',
        missing: [for (final need in (json['missing'] as List?) ?? const []) '$need'],
        canComplete: json['can_complete'] == true,
        signedIn: json['signed_in'] == true,
      );
}

/// The details of a member the signed-in person registered, to complete.
class RegisteredMemberDetails {
  const RegisteredMemberDetails({
    required this.card,
    this.place = GeographicScope.nigeria,
    this.canChangePhone = false,
  });

  final MemberCard card;
  final GeographicScope place;

  /// Until the member first signs in, their number, which is also their first
  /// password, can be corrected.
  final bool canChangePhone;

  factory RegisteredMemberDetails.fromJson(Map<String, dynamic> json) => RegisteredMemberDetails(
        card: MemberCard.fromJson(json),
        place: json['scope'] is Map<String, dynamic>
            ? geographicScopeFromJson(json['scope'] as Map<String, dynamic>)
            : GeographicScope.nigeria,
        canChangePhone: json['can_change_phone'] == true,
      );
}

/// Member registration, sign-in help and the member home (`/register/...`, `/me/...`).
class MemberRepository {
  MemberRepository(this.client);
  final ApiClient client;

  /// Whether joining needs an SMS code to prove the phone. The server asks for
  /// one only while it can send SMS; a server from before this question
  /// always asked.
  Future<bool> phoneCodeRequired() async {
    try {
      final body = await client.get('register/options/', authenticated: false) as Map<String, dynamic>;
      return body['phone_code_required'] != false;
    } on ApiException catch (error) {
      if (error.statusCode == 404) return true;
      rethrow;
    }
  }

  /// Sends a 6-digit code to [phone]; returns how many seconds it stays valid.
  /// The server first checks the phone, and the VIN if given, are not taken.
  Future<int> requestRegistrationCode({required String phone, String vin = ''}) async {
    final body = await client.post(
      'register/code/',
      body: {'phone_number': phone, if (vin.isNotEmpty) 'vin': vin},
      authenticated: false,
    ) as Map<String, dynamic>;
    return (body['expires_in'] as int?) ?? 600;
  }

  /// The signed-in member's referral code and link.
  Future<MyReferral> referral() async =>
      MyReferral.fromJson(await client.get('me/referral/') as Map<String, dynamic>);

  /// Creates the member and signs them in.
  Future<MemberCard> register(MemberRegistration data) async {
    final dob = data.dateOfBirth;
    final body = await client.postMultipart(
      'register/',
      authenticated: false,
      fields: {
        'phone_number': data.phoneNumber,
        if (data.code.isNotEmpty) 'code': data.code,
        'vin': data.vin,
        if (data.delim.isNotEmpty) 'delim': data.delim,
        if (data.pollingUnit.isNotEmpty) 'polling_unit': data.pollingUnit,
        'full_name': data.fullName,
        if (data.gender case final gender?) 'gender': gender,
        if (dob != null) 'date_of_birth': _day(dob),
        'occupation': data.occupation,
        'email': data.email,
        if (data.disabilities.isNotEmpty) 'disabilities': data.disabilities,
        if (data.disabilityOther.isNotEmpty) 'disability_other': data.disabilityOther,
        'pin': data.pin,
        'consent': 'true',
        if (data.referralCode.isNotEmpty) 'referral_code': data.referralCode,
      },
      files: () async => [
        if (data.selfie case final selfie?)
          http.MultipartFile.fromBytes('photo', selfie.bytes, filename: selfie.name),
        if (data.pvcImage case final card?)
          http.MultipartFile.fromBytes('pvc_image', card.bytes, filename: card.name),
      ],
    ) as Map<String, dynamic>;
    return _session(body);
  }

  /// Reads the text on a PVC photo on the server, for browsers, which cannot
  /// read it themselves. The app picks out the fields; nothing is kept.
  Future<String> readPvcText(({Uint8List bytes, String name}) photo) async {
    final body = await client.postMultipart(
      'register/read-pvc/',
      authenticated: false,
      // Allow time for the server to try both card readers before falling back.
      requestTimeout: const Duration(seconds: 90),
      fields: const {},
      files: () async => [
        http.MultipartFile.fromBytes('image', photo.bytes, filename: photo.name),
      ],
    ) as Map<String, dynamic>;
    return (body['text'] as String?) ?? '';
  }

  /// Sends a code for setting a new PIN (the reply is the same for unknown numbers).
  Future<int> requestPinCode(String phone) async {
    final body = await client.post(
      'register/pin-code/',
      body: {'phone_number': phone},
      authenticated: false,
    ) as Map<String, dynamic>;
    return (body['expires_in'] as int?) ?? 600;
  }

  /// Sets a new PIN with the SMS code and signs the member in.
  Future<MemberCard> setPin({
    required String phone,
    required String code,
    required String pin,
  }) async {
    final body = await client.post(
      'register/pin/',
      body: {'phone_number': phone, 'code': code, 'pin': pin},
      authenticated: false,
    ) as Map<String, dynamic>;
    return _session(body);
  }

  Future<MemberCard> _session(Map<String, dynamic> body) async {
    await client.tokens.write(
      access: body['access'] as String,
      refresh: body['refresh'] as String,
    );
    return MemberCard.fromJson(body['member'] as Map<String, dynamic>);
  }

  /// The signed-in member's own details, photo and PVC scan.
  late final own = MemberProfile(client, 'me/member/');

  /// A member the signed-in person registered: their registration to complete.
  MemberProfile registered(String membershipNumber) =>
      MemberProfile(client, 'me/registered/$membershipNumber/');

  /// The card as a PDF, front and back. The server refuses it while
  /// [MemberCard.cardMissing] lists something.
  Future<Uint8List> cardPdf() => client.getBytes('me/member/card/');

  /// Registers someone with their name and phone number, and their place when
  /// known, on the word that they agreed to join. Anyone signed in may, as
  /// often as they like; the member signs in with their number as the password.
  Future<RegisteredMember> registerSomeone({
    required String fullName,
    required String phone,
    GeographicScope? place,
  }) async =>
      RegisteredMember.fromJson(
        await client.post(
          'me/registered/',
          body: {
            'full_name': fullName.trim(),
            'phone_number': phone.trim(),
            'consent': true,
            if (place != null) 'scope': scopeInput(place),
          },
        ) as Map<String, dynamic>,
      );

  /// The members the signed-in person registered, newest first: a page of
  /// them from [offset], the total, and whether more follow.
  Future<({List<RegisteredMember> members, int count, bool more})> registeredMembers({
    String search = '',
    int offset = 0,
  }) async {
    final body = await client.get(
      'me/registered/',
      query: {
        if (search.trim().isNotEmpty) 'search': search.trim(),
        if (offset > 0) 'offset': '$offset',
      },
    ) as Map<String, dynamic>;
    return (
      members: [
        for (final item in body['results'] as List<dynamic>)
          RegisteredMember.fromJson(item as Map<String, dynamic>),
      ],
      count: (body['count'] as num?)?.toInt() ?? 0,
      more: body['next'] != null,
    );
  }

  Future<RegisteredMemberDetails> registeredDetails(String membershipNumber) async =>
      RegisteredMemberDetails.fromJson(
        await client.get('me/registered/$membershipNumber/') as Map<String, dynamic>,
      );

  /// Corrects what was given when registering them: the name and place until
  /// their PVC is on record, the phone number until they first sign in.
  Future<RegisteredMemberDetails> correctRegistration(
    String membershipNumber, {
    String? fullName,
    String? phone,
    GeographicScope? place,
  }) async =>
      RegisteredMemberDetails.fromJson(
        await client.patch(
          'me/registered/$membershipNumber/',
          body: {
            if (fullName != null) 'full_name': fullName.trim(),
            if (phone != null) 'phone_number': phone.trim(),
            if (place != null) 'scope': scopeInput(place),
          },
        ) as Map<String, dynamic>,
      );

  Future<MyPollingUnit> pollingUnit() async =>
      MyPollingUnit.fromJson(await client.get('me/polling-unit/') as Map<String, dynamic>);

  Future<List<MemberAnnouncement>> announcements() async {
    final body = await client.get('me/announcements/');
    final items = body is Map<String, dynamic> ? body['results'] as List<dynamic> : body as List;
    return [for (final item in items) MemberAnnouncement.fromJson(item as Map<String, dynamic>)];
  }

  Future<List<VolunteerOffer>> volunteering() async {
    final body = await client.get('me/volunteer/') as List<dynamic>;
    return [for (final item in body) VolunteerOffer.fromJson(item as Map<String, dynamic>)];
  }

  /// Offers help with the given kinds of party work ([volunteerInterests] keys).
  Future<VolunteerOffer> volunteer({required List<String> interests, String message = ''}) async =>
      VolunteerOffer.fromJson(
        await client.post('me/volunteer/', body: {'interests': interests, 'message': message})
            as Map<String, dynamic>,
      );

  /// Takes back an offer the coordinators have not answered yet.
  Future<VolunteerOffer> withdrawVolunteering(String id) async => VolunteerOffer.fromJson(
        await client.post('me/volunteer/$id/withdraw/') as Map<String, dynamic>,
      );
}
