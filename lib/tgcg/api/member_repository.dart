import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'api_client.dart';
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
    this.vin,
    this.hasPvc = false,
    this.gender = '',
    this.occupation = '',
    this.status = '',
    this.pollingUnit,
    this.hasPhoto = false,
  });

  final String membershipNumber;
  final String fullName;
  final String phoneNumber;
  final String email;

  /// The PVC's VIN with most characters hidden.
  final String? vin;
  final bool hasPvc;
  final String gender;
  final String occupation;
  final String status;
  final MemberUnit? pollingUnit;
  final DateTime memberSince;
  final bool hasPhoto;

  /// Signed value printed as the card's QR code; staff scan it to verify.
  final String qrToken;

  factory MemberCard.fromJson(Map<String, dynamic> json) {
    final unit = json['polling_unit'];
    return MemberCard(
      membershipNumber: json['membership_number'] as String,
      fullName: json['full_name'] as String,
      phoneNumber: json['phone_number'] as String,
      email: (json['email'] as String?) ?? '',
      vin: json['vin'] as String?,
      hasPvc: json['has_pvc'] as bool? ?? false,
      gender: (json['gender'] as String?) ?? '',
      occupation: (json['occupation'] as String?) ?? '',
      status: (json['status'] as String?) ?? '',
      pollingUnit: unit is Map<String, dynamic> ? MemberUnit.fromJson(unit) : null,
      memberSince: DateTime.parse(json['member_since'] as String),
      hasPhoto: json['photo_url'] != null,
      qrToken: json['qr_token'] as String,
    );
  }
}

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

/// Everything collected on the registration screens.
class MemberRegistration {
  const MemberRegistration({
    required this.phoneNumber,
    required this.code,
    required this.vin,
    required this.delim,
    required this.fullName,
    required this.gender,
    required this.pin,
    required this.selfie,
    required this.pvcImage,
    this.dateOfBirth,
    this.occupation = '',
    this.email = '',
  });

  final String phoneNumber;
  final String code;
  final String vin;
  final String delim;
  final String fullName;

  /// male or female.
  final String gender;
  final DateTime? dateOfBirth;
  final String occupation;
  final String email;
  final String pin;
  final ({Uint8List bytes, String name}) selfie;
  final ({Uint8List bytes, String name}) pvcImage;
}

/// Member registration, sign-in help and the member home (`/register/...`, `/me/...`).
class MemberRepository {
  MemberRepository(this.client);
  final ApiClient client;

  /// Sends a 6-digit code to [phone]; returns how many seconds it stays valid.
  Future<int> requestRegistrationCode({required String phone, required String vin}) async {
    final body = await client.post(
      'register/code/',
      body: {'phone_number': phone, 'vin': vin},
      authenticated: false,
    ) as Map<String, dynamic>;
    return (body['expires_in'] as int?) ?? 600;
  }

  /// Creates the member and signs them in.
  Future<MemberCard> register(MemberRegistration data) async {
    final dob = data.dateOfBirth;
    final body = await client.postMultipart(
      'register/',
      authenticated: false,
      fields: {
        'phone_number': data.phoneNumber,
        'code': data.code,
        'vin': data.vin,
        'delim': data.delim,
        'full_name': data.fullName,
        'gender': data.gender,
        if (dob != null)
          'date_of_birth': '${dob.year.toString().padLeft(4, '0')}-'
              '${dob.month.toString().padLeft(2, '0')}-${dob.day.toString().padLeft(2, '0')}',
        'occupation': data.occupation,
        'email': data.email,
        'pin': data.pin,
        'consent': 'true',
      },
      files: () async => [
        http.MultipartFile.fromBytes('photo', data.selfie.bytes, filename: data.selfie.name),
        http.MultipartFile.fromBytes('pvc_image', data.pvcImage.bytes,
            filename: data.pvcImage.name),
      ],
    ) as Map<String, dynamic>;
    return _session(body);
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

  Future<MemberCard> card() async =>
      MemberCard.fromJson(await client.get('me/member/') as Map<String, dynamic>);

  Future<MemberCard> updateEmail(String email) async => MemberCard.fromJson(
        await client.patch('me/member/', body: {'email': email}) as Map<String, dynamic>,
      );

  Future<Uint8List> photo() => client.getBytes('me/member/photo/');

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
