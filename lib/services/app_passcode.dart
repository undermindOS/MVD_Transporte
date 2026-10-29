import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import 'cache_service.dart';

/// What came of a code typed on the keypad.
enum CodeCheck {
  /// The app's code.
  ok,

  /// Another code.
  wrong,

  /// Too many wrong codes in a row: no code is checked until
  /// [AppPasscode.waitUntil]. Also the answer to the wrong code that starts
  /// the wait.
  wait,
}

/// The app's own code of [length] digits, kept on the phone as a salted
/// PBKDF2-HMAC-SHA256 hash in the settings box, never as the code itself.
///
/// Four digits are 10 000 codes: the hash keeps the code out of the app's
/// files, the wait keeps someone with the phone in hand from going through
/// them. [freeTries] wrong codes in a row are free; from then on every
/// wrong code makes the next one wait [wait]. When the code is forgotten,
/// the phone's own lock opens the app (AppLock).
///
/// Its settings are not awaited on their way to the disk: Hive has them in
/// memory at once and writes them in order right after
/// (`CacheService.set`).
abstract final class AppPasscode {
  static const length = 4;
  static const freeTries = 5;
  static const wait = Duration(seconds: 30);

  /// PBKDF2 rounds of a new hash: about 0.1 to 0.3 s on a low-end phone, in
  /// a background isolate. A stored hash keeps its own count.
  static const iterations = 20000;

  /// Derives the hash off the UI isolate. Tests swap it for a quick one.
  @visibleForTesting
  static Future<Uint8List> Function(
      String code, Uint8List salt, int iterations) derive = _deriveInIsolate;

  /// The phone's clock, for the wait and its countdown on the keypad. Tests
  /// move it.
  static DateTime Function() clock = DateTime.now;

  static const _scheme = 'pbkdf2-sha256';
  static const _saltLength = 16;
  static final _random = Random.secure();

  /// A code is set. A value that does not read as a hash still counts:
  /// no code matches it, and the phone's lock opens the app.
  static bool get isSet =>
      CacheService.get<String>(CacheService.keyLockCode) != null;

  /// [length] digits from 0 to 9.
  static bool isValid(String code) =>
      code.length == length &&
      code.codeUnits.every((c) => c >= 0x30 && c <= 0x39);

  /// When the next code can be checked; null when there is no wait.
  ///
  /// The wait trusts the phone's clock: setting it forward ends the wait,
  /// setting it back never makes it longer than twice [wait].
  static DateTime? get waitUntil {
    final fromMs = CacheService.get<int>(CacheService.keyLockWaitFrom);
    if (fromMs == null) return null;
    final from = DateTime.fromMillisecondsSinceEpoch(fromMs);
    final now = clock();
    final until = from.add(wait);
    if (!now.isBefore(until) || now.isBefore(from.subtract(wait))) {
      return null;
    }
    return until;
  }

  /// Saves [code] as the app's code and forgets the wrong codes.
  static Future<void> set(String code) async {
    assert(isValid(code), 'A code is $length digits');
    final salt = Uint8List.fromList(
        List.generate(_saltLength, (_) => _random.nextInt(256)));
    final hash = await derive(code, salt, iterations);
    unawaited(CacheService.set(CacheService.keyLockCode,
        '$_scheme\$$iterations\$${base64.encode(salt)}\$${base64.encode(hash)}'));
    forgetWrongCodes();
  }

  /// Checks [code] against the app's code.
  static Future<CodeCheck> check(String code) async {
    if (waitUntil != null) return CodeCheck.wait;
    // Counted before the hash: closing the app while it is worked out does
    // not skip a wrong code
    final wrongCodes =
        (CacheService.get<int>(CacheService.keyLockFailures) ?? 0) + 1;
    unawaited(CacheService.set(CacheService.keyLockFailures, wrongCodes));

    final stored = _stored;
    if (stored != null && isValid(code)) {
      final hash = await derive(code, stored.salt, stored.iterations);
      if (_same(hash, stored.hash)) {
        forgetWrongCodes();
        return CodeCheck.ok;
      }
    }
    if (wrongCodes < freeTries) return CodeCheck.wrong;
    unawaited(CacheService.set(
        CacheService.keyLockWaitFrom, clock().millisecondsSinceEpoch));
    return CodeCheck.wait;
  }

  /// Forgets the code and the wrong codes.
  static void clear() {
    unawaited(CacheService.remove(CacheService.keyLockCode));
    forgetWrongCodes();
  }

  /// Forgets the wrong codes and the wait: the right code does it, and so
  /// does the phone's own lock in place of a forgotten code (AppLock).
  static void forgetWrongCodes() {
    unawaited(CacheService.remove(CacheService.keyLockFailures));
    unawaited(CacheService.remove(CacheService.keyLockWaitFrom));
  }

  /// The stored hash: `pbkdf2-sha256$<iterations>$<salt>$<hash>`, salt and
  /// hash in base64. Null when there is none or it does not read.
  static ({int iterations, Uint8List salt, Uint8List hash})? get _stored {
    final parts =
        CacheService.get<String>(CacheService.keyLockCode)?.split(r'$');
    if (parts == null || parts.length != 4 || parts[0] != _scheme) {
      return null;
    }
    final iterations = int.tryParse(parts[1]);
    if (iterations == null || iterations < 1) return null;
    try {
      return (
        iterations: iterations,
        salt: base64.decode(parts[2]),
        hash: base64.decode(parts[3]),
      );
    } on FormatException {
      return null;
    }
  }

  /// Same bytes, in a time that does not depend on where they differ.
  static bool _same(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  static Future<Uint8List> _deriveInIsolate(
          String code, Uint8List salt, int iterations) =>
      compute(_derive, (code: code, salt: salt, iterations: iterations));

  static Uint8List _derive(
          ({String code, Uint8List salt, int iterations}) input) =>
      pbkdf2Sha256(utf8.encode(input.code), input.salt, input.iterations);
}

/// PBKDF2 with HMAC-SHA256 (RFC 8018, section 5.2): [length] bytes from
/// [password] and [salt] after [iterations] rounds.
Uint8List pbkdf2Sha256(List<int> password, List<int> salt, int iterations,
    {int length = 32}) {
  final hmac = Hmac(sha256, password);
  final out = Uint8List(length);
  var offset = 0;
  for (var block = 1; offset < length; block++) {
    var u = hmac.convert([
      ...salt,
      block >> 24 & 0xff,
      block >> 16 & 0xff,
      block >> 8 & 0xff,
      block & 0xff,
    ]).bytes;
    final t = Uint8List.fromList(u);
    for (var i = 1; i < iterations; i++) {
      u = hmac.convert(u).bytes;
      for (var j = 0; j < t.length; j++) {
        t[j] ^= u[j];
      }
    }
    final n = min(t.length, length - offset);
    out.setRange(offset, offset + n, t);
    offset += n;
  }
  return out;
}
