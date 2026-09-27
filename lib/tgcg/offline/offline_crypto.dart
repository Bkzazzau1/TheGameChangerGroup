import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'offline_database_contract.dart';

class OfflineCrypto {
  OfflineCrypto({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  static const _keyName = 'tgcg.offline.aes256.v1';

  final FlutterSecureStorage _secureStorage;
  final AesGcm _algorithm = AesGcm.with256bits();
  SecretKey? _secretKey;

  Future<void> initialize() async {
    if (_secretKey != null) return;
    final stored = await _secureStorage.read(key: _keyName);
    if (stored != null && stored.isNotEmpty) {
      _secretKey = SecretKey(base64Decode(stored));
      return;
    }

    final generated = await _algorithm.newSecretKey();
    final bytes = await generated.extractBytes();
    await _secureStorage.write(
      key: _keyName,
      value: base64Encode(bytes),
    );
    _secretKey = SecretKey(bytes);
  }

  Future<EncryptedPayload> encrypt(
    String plaintext, {
    required String aad,
  }) async {
    final key = await _key();
    final secretBox = await _algorithm.encrypt(
      utf8.encode(plaintext),
      secretKey: key,
      aad: utf8.encode(aad),
    );
    return EncryptedPayload(
      cipherText: Uint8List.fromList(secretBox.cipherText),
      nonce: Uint8List.fromList(secretBox.nonce),
      mac: Uint8List.fromList(secretBox.mac.bytes),
    );
  }

  Future<String> decrypt(
    EncryptedPayload payload, {
    required String aad,
  }) async {
    final key = await _key();
    final clear = await _algorithm.decrypt(
      SecretBox(
        payload.cipherText,
        nonce: payload.nonce,
        mac: Mac(payload.mac),
      ),
      secretKey: key,
      aad: utf8.encode(aad),
    );
    return utf8.decode(clear);
  }

  Future<SecretKey> _key() async {
    await initialize();
    return _secretKey!;
  }
}
