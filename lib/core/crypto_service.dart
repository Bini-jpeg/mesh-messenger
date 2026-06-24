// FILE: lib/core/crypto_service.dart
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pointycastle/export.dart';

class CryptoService {
  final _storage = const FlutterSecureStorage();

  static const _keyModulus  = 'rsa_modulus';
  static const _keyPubExp   = 'rsa_pub_exp';
  static const _keyPrivExp  = 'rsa_priv_exp';
  static const _keyP        = 'rsa_p';
  static const _keyQ        = 'rsa_q';

  RSAPublicKey?  _publicKey;
  RSAPrivateKey? _privateKey;

  // ── Initialisation ──────────────────────────────────────────────────────────

  Future<void> init() async {
    final stored = await _storage.read(key: _keyModulus);
    if (stored == null) {
      await _generateAndSaveKeys();
    } else {
      await _loadKeys();
    }
  }

  Future<void> _generateAndSaveKeys() async {
    debugPrint('CryptoService: generating new RSA-2048 keypair…');
    final rng    = _buildSecureRandom();
    final keyGen = RSAKeyGenerator()
      ..init(ParametersWithRandom(
          RSAKeyGeneratorParameters(BigInt.from(65537), 2048, 64), rng));

    final pair  = keyGen.generateKeyPair();
    _publicKey  = pair.publicKey  as RSAPublicKey;
    _privateKey = pair.privateKey as RSAPrivateKey;

    await _storage.write(
        key: _keyModulus, value: _publicKey!.modulus!.toRadixString(16));
    await _storage.write(
        key: _keyPubExp,  value: _publicKey!.exponent!.toRadixString(16));
    await _storage.write(
        key: _keyPrivExp, value: _privateKey!.privateExponent!.toRadixString(16));
    await _storage.write(
        key: _keyP,       value: _privateKey!.p!.toRadixString(16));
    await _storage.write(
        key: _keyQ,       value: _privateKey!.q!.toRadixString(16));

    debugPrint('CryptoService: keypair generated. '
        'userId length: ${publicKey.length} chars');
  }

  Future<void> _loadKeys() async {
    try {
      final mod     = await _storage.read(key: _keyModulus);
      final pubExp  = await _storage.read(key: _keyPubExp);
      final privExp = await _storage.read(key: _keyPrivExp);
      final p       = await _storage.read(key: _keyP);
      final q       = await _storage.read(key: _keyQ);

      if (mod == null || pubExp == null || privExp == null ||
          p == null   || q == null) {
        throw Exception('Incomplete key material in secure storage');
      }

      _publicKey = RSAPublicKey(
        BigInt.parse(mod,    radix: 16),
        BigInt.parse(pubExp, radix: 16),
      );
      _privateKey = RSAPrivateKey(
        BigInt.parse(mod,     radix: 16),
        BigInt.parse(privExp, radix: 16),
        BigInt.parse(p,       radix: 16),
        BigInt.parse(q,       radix: 16),
      );
      debugPrint('CryptoService: keypair loaded from secure storage.');
    } catch (e) {
      debugPrint('CryptoService: key load failed ($e) — regenerating.');
      await _generateAndSaveKeys();
    }
  }

  // ── Public identity ─────────────────────────────────────────────────────────

  String get userId {
    if (_publicKey == null) return '';
    return _publicKey!.modulus!.toRadixString(16);
  }

  String get publicKey => userId;

  String get shortDisplayId {
    final id = userId;
    return id.length > 20 ? '${id.substring(0, 20)}…' : id;
  }

  // ── Hybrid encryption ───────────────────────────────────────────────────────

  String encryptMessage(String message, String recipientPublicKeyHex) {
    if (recipientPublicKeyHex.isEmpty) {
      throw Exception('Recipient key is empty');
    }
    if (recipientPublicKeyHex.length < 256) {
      throw Exception('Key too short. A full RSA-2048 modulus must be ≥256 hex chars.');
    }
    if (!RegExp(r'^[0-9a-fA-F]+$').hasMatch(recipientPublicKeyHex)) {
      throw Exception('Key contains non-hex characters');
    }
    
    // Un-suppressed exceptions bubble up freely to the caller
    final recipientModulus = BigInt.parse(recipientPublicKeyHex, radix: 16);
    final recipientKey     = RSAPublicKey(recipientModulus, BigInt.from(65537));

    final rng    = _buildSecureRandom();
    final aesKey = rng.nextBytes(32); 
    final iv     = rng.nextBytes(16); 

    final aes = CBCBlockCipher(AESEngine())
      ..init(true, ParametersWithIV(KeyParameter(aesKey), iv));
    final plainBytes = Uint8List.fromList(utf8.encode(message));
    final padded     = _pkcs7Pad(plainBytes, 16);
    final ciphertext = _processAesBlocks(aes, padded);

    final rsa = OAEPEncoding.withSHA256(RSAEngine())
      ..init(true, PublicKeyParameter<RSAPublicKey>(recipientKey));
    final encryptedKey = rsa.process(aesKey);

    final bundle = jsonEncode({
      'k':  base64Encode(encryptedKey),
      'iv': base64Encode(iv),
      'ct': base64Encode(ciphertext),
    });
    return base64Encode(utf8.encode(bundle));
  }

  String decryptMessage(String encryptedBase64) {
    if (_privateKey == null) {
      throw Exception('Private key not loaded');
    }
    
    final bundleJson = utf8.decode(base64Decode(encryptedBase64));
    final bundle     = jsonDecode(bundleJson) as Map<String, dynamic>;

    final encryptedKey = base64Decode(bundle['k']  as String);
    final iv           = base64Decode(bundle['iv'] as String);
    final ciphertext   = base64Decode(bundle['ct'] as String);

    final rsa = OAEPEncoding.withSHA256(RSAEngine())
      ..init(false, PrivateKeyParameter<RSAPrivateKey>(_privateKey!));
    final aesKey = rsa.process(encryptedKey);

    final aes = CBCBlockCipher(AESEngine())
      ..init(false, ParametersWithIV(KeyParameter(aesKey), iv));
    final padded = _processAesBlocks(aes, ciphertext);
    final plain  = _pkcs7Unpad(padded);

    return utf8.decode(plain);
  }

  // ── Private helpers ─────────────────────────────────────────────────────────

  SecureRandom _buildSecureRandom() {
    final seed     = Uint8List(32);
    final dartRng  = Random.secure();
    for (int i = 0; i < 32; i++) {
      seed[i] = dartRng.nextInt(256);
    }
    return FortunaRandom()..seed(KeyParameter(seed));
  }

  Uint8List _processAesBlocks(BlockCipher cipher, Uint8List input) {
    assert(input.length % cipher.blockSize == 0);
    final output = Uint8List(input.length);
    for (var offset = 0; offset < input.length; offset += cipher.blockSize) {
      cipher.processBlock(input, offset, output, offset);
    }
    return output;
  }

  Uint8List _pkcs7Pad(Uint8List data, int blockSize) {
    final padLen = blockSize - (data.length % blockSize);
    final out    = Uint8List(data.length + padLen);
    out.setAll(0, data);
    out.fillRange(data.length, out.length, padLen);
    return out;
  }

  Uint8List _pkcs7Unpad(Uint8List data) {
    if (data.isEmpty) return data;
    final padLen = data.last;
    if (padLen == 0 || padLen > 16) return data;
    return data.sublist(0, data.length - padLen);
  }
}
