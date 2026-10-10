import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// Backend address, set at build time:
/// `flutter run --dart-define=TGCG_API_URL=http://10.0.2.2:8000`
/// (10.0.2.2 reaches the host machine from the Android emulator.)
/// When empty, the app runs in offline presentation mode.
const tgcgApiUrl = String.fromEnvironment('TGCG_API_URL');

bool get tgcgApiConfigured => tgcgApiUrl.isNotEmpty;

/// A failed API call, with the server's message and per-field errors.
class ApiException implements Exception {
  const ApiException(this.statusCode, this.message, {this.fieldErrors = const {}});

  /// 0 means the server could not be reached.
  final int statusCode;
  final String message;
  final Map<String, List<String>> fieldErrors;

  bool get isOffline => statusCode == 0;
  bool get isUnauthorized => statusCode == 401;

  /// The first error for [field], if any.
  String? fieldError(String field) => fieldErrors[field]?.first;

  @override
  String toString() => message;

  /// Turns a DRF error body into a readable exception.
  factory ApiException.fromResponse(int statusCode, Object? body) {
    final fields = <String, List<String>>{};
    String? message;
    if (body is Map) {
      for (final entry in body.entries) {
        final key = entry.key.toString();
        final value = entry.value;
        final messages = switch (value) {
          final List<dynamic> list => list.map((e) => e.toString()).toList(),
          final Map<dynamic, dynamic> nested =>
            nested.values.expand((v) => v is List ? v : [v]).map((e) => e.toString()).toList(),
          _ => [value.toString()],
        };
        if (key == 'detail' || key == 'non_field_errors') {
          message ??= messages.first;
        } else {
          fields[key] = messages;
        }
      }
    }
    message ??= fields.values.isNotEmpty
        ? fields.values.first.first
        : switch (statusCode) {
            401 => 'Your session has expired. Sign in again.',
            403 => 'Your role does not permit this action.',
            404 => 'Not found.',
            429 => 'Too many attempts. Wait a moment and try again.',
            >= 500 => 'The server had a problem. Try again shortly.',
            _ => 'The request failed ($statusCode).',
          };
    return ApiException(statusCode, message, fieldErrors: fields);
  }
}

/// Where access and refresh tokens are kept between app launches.
abstract interface class TokenStore {
  Future<({String access, String refresh})?> read();
  Future<void> write({required String access, required String refresh});
  Future<void> clear();
}

class SecureTokenStore implements TokenStore {
  SecureTokenStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static const _accessKey = 'tgcg.access';
  static const _refreshKey = 'tgcg.refresh';

  @override
  Future<({String access, String refresh})?> read() async {
    final access = await _storage.read(key: _accessKey);
    final refresh = await _storage.read(key: _refreshKey);
    if (access == null || refresh == null) return null;
    return (access: access, refresh: refresh);
  }

  @override
  Future<void> write({required String access, required String refresh}) async {
    await _storage.write(key: _accessKey, value: access);
    await _storage.write(key: _refreshKey, value: refresh);
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
  }
}

class MemoryTokenStore implements TokenStore {
  ({String access, String refresh})? _tokens;

  @override
  Future<({String access, String refresh})?> read() async => _tokens;

  @override
  Future<void> write({required String access, required String refresh}) async =>
      _tokens = (access: access, refresh: refresh);

  @override
  Future<void> clear() async => _tokens = null;
}

/// JSON client for the TGCG backend (`/api/v1/...`).
///
/// Adds the bearer token, refreshes it once on a 401 (concurrent calls share
/// one refresh), and reports failures as [ApiException].
class ApiClient {
  ApiClient({
    required String baseUrl,
    required this.tokens,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 30),
  })  : _base = Uri.parse(baseUrl.endsWith('/') ? baseUrl : '$baseUrl/'),
        _http = httpClient ?? http.Client();

  final Uri _base;
  final http.Client _http;
  final TokenStore tokens;
  final Duration timeout;

  /// Called when the session can no longer be refreshed (sign the user out).
  void Function()? onSessionExpired;

  Future<void>? _refreshing;

  Uri uri(String path, [Map<String, String>? query]) {
    final resolved = _base.resolve('api/v1/${path.startsWith('/') ? path.substring(1) : path}');
    return query == null ? resolved : resolved.replace(queryParameters: query);
  }

  Future<dynamic> get(String path, {Map<String, String>? query}) =>
      _send('GET', path, query: query);

  Future<dynamic> post(String path, {Object? body, bool authenticated = true}) =>
      _send('POST', path, body: body, authenticated: authenticated);

  Future<dynamic> patch(String path, {Object? body}) => _send('PATCH', path, body: body);

  /// Multipart upload. [fields] values are sent as strings; maps and lists
  /// are JSON-encoded (the backend accepts JSON text for nested fields).
  /// [files] builds fresh file parts, because a request may be re-sent after
  /// a token refresh and file streams can only be read once.
  Future<dynamic> postMultipart(
    String path, {
    required Map<String, Object?> fields,
    Future<List<http.MultipartFile>> Function()? files,
    bool authenticated = true,
  }) =>
      _withAuthRetry(authenticated, () async {
        final request = http.MultipartRequest('POST', uri(path));
        for (final entry in fields.entries) {
          final value = entry.value;
          if (value == null) continue;
          request.fields[entry.key] =
              value is Map || value is List ? jsonEncode(value) : value.toString();
        }
        if (files != null) request.files.addAll(await files());
        await _authorize(request, authenticated);
        return http.Response.fromStream(await _http.send(request).timeout(timeout));
      });

  Future<dynamic> _send(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
    bool authenticated = true,
  }) =>
      _withAuthRetry(authenticated, () async {
        final request = http.Request(method, uri(path, query))
          ..headers['Accept'] = 'application/json';
        if (body != null) {
          request.headers['Content-Type'] = 'application/json';
          request.body = jsonEncode(body);
        }
        await _authorize(request, authenticated);
        return http.Response.fromStream(await _http.send(request).timeout(timeout));
      });

  Future<void> _authorize(http.BaseRequest request, bool authenticated) async {
    if (!authenticated) return;
    final saved = await tokens.read();
    if (saved != null) request.headers['Authorization'] = 'Bearer ${saved.access}';
  }

  Future<dynamic> _withAuthRetry(
    bool authenticated,
    Future<http.Response> Function() send,
  ) async {
    var response = await _guard(send);
    if (authenticated && response.statusCode == 401 && await tokens.read() != null) {
      await _refreshTokens();
      response = await _guard(send);
    }
    return _decode(response);
  }

  Future<http.Response> _guard(Future<http.Response> Function() send) async {
    try {
      return await send();
    } on TimeoutException {
      throw const ApiException(0, 'The TGCG server did not respond in time.');
    } on http.ClientException {
      throw const ApiException(0, 'No connection to the TGCG server. Check your network.');
    }
  }

  Future<void> _refreshTokens() => _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);

  Future<void> _doRefresh() async {
    final saved = await tokens.read();
    if (saved == null) return;
    final response = await _guard(
      () => _http
          .post(
            uri('auth/refresh/'),
            headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
            body: jsonEncode({'refresh': saved.refresh}),
          )
          .timeout(timeout),
    );
    if (response.statusCode != 200) {
      await tokens.clear();
      onSessionExpired?.call();
      throw ApiException.fromResponse(401, _json(response));
    }
    final body = _json(response) as Map<String, dynamic>;
    // The backend rotates refresh tokens; keep the new one when sent.
    await tokens.write(
      access: body['access'] as String,
      refresh: (body['refresh'] as String?) ?? saved.refresh,
    );
  }

  dynamic _decode(http.Response response) {
    final body = _json(response);
    if (response.statusCode >= 200 && response.statusCode < 300) return body;
    if (response.statusCode == 401) onSessionExpired?.call();
    throw ApiException.fromResponse(response.statusCode, body);
  }

  static Object? _json(http.Response response) {
    if (response.bodyBytes.isEmpty) return null;
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      return null;
    }
  }
}
