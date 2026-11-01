import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tgcg_emcop/tgcg/api/api_client.dart';
import 'package:tgcg_emcop/tgcg/api/backend.dart';
import 'package:tgcg_emcop/tgcg/session.dart';

import 'redesign_fixtures.dart';

// Names here are made up.

const reviewedNumber = 'TGCG-000300';

/// A one-pixel picture, for screens that only need something to show.
final tinyPicture = Uint8List.fromList(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
  ),
);

const _place = {
  'level': 'pollingUnit',
  'country': 'Nigeria',
  'stateId': 'KD',
  'stateName': 'Kaduna',
  'lgaId': 'KD-ZARIA',
  'lgaName': 'Zaria',
  'wardId': '18-23-01',
  'wardName': 'KWARBAI A',
  'pollingUnitId': '18-23-01-001',
  'pollingUnitName': 'KWARBAI I',
};

/// A server holding one member, and what it was asked.
class ReviewServer {
  ReviewServer({
    this.status = 'pendingReview',
    this.mayDecide = true,
    this.seesPersonal = true,
    this.gaps = const [],
    this.refuseApproval = false,
    Uint8List? selfie,
    Uint8List? card,
  }) : selfie = selfie ?? tinyPicture,
       card = card ?? tinyPicture;

  String status;

  /// The server lets this account decide this member.
  final bool mayDecide;
  final bool seesPersonal;
  final List<String> gaps;

  /// A failed check stops an approval on the server.
  final bool refuseApproval;
  final Uint8List selfie;
  final Uint8List card;

  final requests = <String>[];
  final bodies = <String, Map<String, dynamic>>{};

  bool asked(String path) => requests.any((request) => request.endsWith(path));

  Map<String, dynamic> get person => {
    'membership_number': reviewedNumber,
    'full_name': 'Bala Musa',
    'verification_status': status,
    'membership_state': 'active',
    'scope': _place,
    'sensitive_visible': seesPersonal,
    'photo_url': seesPersonal && !gaps.contains('selfie') ? 'https://api.tgcg.test/p' : null,
    'phone_number': seesPersonal ? '+2348030000300' : null,
    'gaps': gaps,
    'has_pvc': true,
    'signed_in': false,
    'has_app_account': true,
    'registration_channel': 'self',
    'occupation': 'Teacher',
    'gender': 'male',
    'created_at': '2026-10-20T09:00:00Z',
  };

  Map<String, dynamic> get verification => {
    'membership_number': reviewedNumber,
    'verification_status': status,
    'verified_at': null,
    'reviewed_by': null,
    'checks': [
      {'kind': 'pvcCaptured', 'result': 'passed', 'detail': 'VIN read from the card.'},
      {'kind': 'pvcValidated', 'result': 'unsupported', 'detail': 'No INEC source is connected.'},
    ],
  };

  http.Response _answer(http.Request request) {
    final path = request.url.path.replaceFirst('/api/v1/', '');
    final key = '${request.method} $path';
    requests.add(key);
    if (request.body.isNotEmpty) {
      bodies[key] = jsonDecode(request.body) as Map<String, dynamic>;
    }
    return switch (key) {
      'GET members/' => jsonResponse({
        'count': 1,
        'next': null,
        'previous': null,
        'results': [person],
      }),
      'GET members/$reviewedNumber/' => jsonResponse(person),
      'GET members/$reviewedNumber/verification/' =>
        mayDecide
            ? jsonResponse(verification)
            : jsonResponse({'detail': 'The member is outside your area for this.'}, 403),
      'POST members/$reviewedNumber/verification/check/' => jsonResponse(verification),
      'POST members/$reviewedNumber/verification/approve/' when refuseApproval => jsonResponse({
        'detail': 'Resolve the failed checks first: card match.',
      }, 400),
      'POST members/$reviewedNumber/verification/approve/' => () {
        status = 'verified';
        return jsonResponse(verification);
      }(),
      'POST members/$reviewedNumber/verification/reject/' => () {
        status = 'rejected';
        return jsonResponse(verification);
      }(),
      'GET members/$reviewedNumber/photo/' => http.Response.bytes(selfie, 200),
      'GET members/$reviewedNumber/card-photo/' => http.Response.bytes(card, 200),
      _ => jsonResponse({'detail': 'Not found.'}, 404),
    };
  }

  BackendServices connect() => BackendServices.connect(
    'https://api.tgcg.test',
    tokens: MemoryTokenStore(),
    httpClient: MockClient((request) async => _answer(request)),
  );
}

/// Someone appointed with [powers].
TgcgSessionController reviewerSession(Set<String> powers) =>
    TgcgSessionController()..signInFromServer(
      fullName: 'Kaduna Reviewer',
      accessId: 'TGCG-000100',
      scope: GeographicScope.nigeria,
      capabilities: powers,
      membershipNumber: 'TGCG-000100',
    );
