// The app's code: the PBKDF2-HMAC-SHA256 hash against published vectors and
// Python's hashlib, what is stored, the wrong codes and the wait.
//
// Plain tests, no widgets: Hive in a temp directory, the hash (one round)
// and the clock swapped where it helps.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:stm_app/services/app_passcode.dart';
import 'package:stm_app/services/cache_service.dart';

Uint8List _bytes(String hex) => Uint8List.fromList([
      for (var i = 0; i < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ]);

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

void main() {
  group('pbkdf2Sha256', () {
    // (password, salt, rounds, length, expected), all hex. The first two
    // are RFC 7914 section 11, the next five CPython's test_hashlib; the
    // rest come from Python's hashlib and pycryptodome: the codes of the
    // app, two salts, and keys of 64 and 65 bytes (the HMAC block size).
    const vectors = [
      ('706173737764', '73616c74', 1, 64,
          '55ac046e56e3089fec1691c22544b605f94185216dde0465e68b9d57c20dacbc'
          '49ca9cccf179b645991664b39d77ef317c71b845b1e30bd509112041d3a19783'),
      ('50617373776f7264', '4e61436c', 80000, 64,
          '4ddcd8f60b98be21830cee5ef22701f9641a4418d04c0414aeff08876b34ab56'
          'a1d425a1225833549adb841b51c9b3176a272bdebba1d078478f62b397f33c8d'),
      ('70617373776f7264', '73616c74', 1, 32,
          '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b'),
      ('70617373776f7264', '73616c74', 2, 32,
          'ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43'),
      ('70617373776f7264', '73616c74', 4096, 32,
          'c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a'),
      ('70617373776f726450415353574f524470617373776f7264',
          '73616c7453414c5473616c7453414c5473616c7453414c5473616c7453414c54'
          '73616c74',
          4096, 40,
          '348c89dbcbd32b2f32d814b8116e84cf2b17347ebc1800181c4e2a1fb8dd53e1'
          'c635518c7dac47e9'),
      ('7061737300776f7264', '7361006c74', 4096, 16,
          '89b69d0516f829893c696226650a8687'),
      ('30303030', '000102030405060708090a0b0c0d0e0f', 1, 32,
          '85c7d304622fc0d65d64a6acd65799ecd04672f6c56d56d5119ea1de263c2d5d'),
      ('31323334', '000102030405060708090a0b0c0d0e0f', 2, 32,
          'a0d0ace1e3b9a5e5a965733c30651d45e6ddfd4bfc4c8d110bb090ecd821d0de'),
      ('31323334', '000102030405060708090a0b0c0d0e0f', 20000, 32,
          'dfada071ff247e6bec37736dbed1ba93a58af89aa081176a1a026cac038223be'),
      ('39393939', '000102030405060708090a0b0c0d0e0f', 1000, 32,
          '4972b953b25bfc457bbd5478e61910f3eda01891046d5325aafe020e1b7ba4bd'),
      ('30303030', 'a1b2c3d4e5f60718293a4b5c6d7e8f90', 1, 32,
          'dd757ceea198044fe811681cbdd508f495e3261da465806308586182a1dab5eb'),
      ('31323334', 'a1b2c3d4e5f60718293a4b5c6d7e8f90', 20000, 32,
          'd2a38869d1a9ad0cd3443c737341ad3dc8c62ac51e446162bc4dbce4ec460bfe'),
      ('39393939', 'a1b2c3d4e5f60718293a4b5c6d7e8f90', 1000, 32,
          'c66d6a99370250dedd1845efabbae89a208e16be5d8e6b323e0f4f8663be77c3'),
      ('6161616161616161616161616161616161616161616161616161616161616161'
          '6161616161616161616161616161616161616161616161616161616161616161',
          '000102030405060708090a0b0c0d0e0f', 2, 32,
          'dd97e5f9f2e4f0432e9d82d26f8436e922564f890b378bb1312570c829c9ca42'),
      ('6161616161616161616161616161616161616161616161616161616161616161'
          '616161616161616161616161616161616161616161616161616161616161616161',
          '000102030405060708090a0b0c0d0e0f', 2, 32,
          'b686e06e102be7a38c82c360a8bccda316edd5e8e70555a0eca9178e59647a1b'),
    ];
    for (final (i, (password, salt, rounds, length, expected))
        in vectors.indexed) {
      test('vector ${i + 1}: ${password.length ~/ 2}-byte password, '
          '$rounds rounds, $length bytes', () {
        final key =
            pbkdf2Sha256(_bytes(password), _bytes(salt), rounds, length: length);
        expect(_hex(key), expected);
      });
    }
  });

  group('AppPasscode', () {
    // Before setUp swaps it: the real hash, in a background isolate
    final realDerive = AppPasscode.derive;
    late Directory dir;
    late DateTime now;
    late int derivations;

    setUpAll(() async {
      dir = await Directory.systemTemp.createTemp('mvd_passcode_test');
      await CacheService.init(path: dir.path);
    });

    setUp(() {
      now = DateTime(2026, 10, 29, 9);
      AppPasscode.clock = () => now;
      derivations = 0;
      AppPasscode.derive = (code, salt, iterations) async {
        derivations++;
        return pbkdf2Sha256(utf8.encode(code), salt, 1);
      };
      AppPasscode.clear();
    });

    tearDown(() {
      AppPasscode.derive = realDerive;
      AppPasscode.clock = DateTime.now;
    });

    tearDownAll(() async {
      await Hive.close();
      await dir.delete(recursive: true);
    });

    Future<void> wrongCodes(int count) async {
      for (var i = 0; i < count; i++) {
        await AppPasscode.check('0000');
      }
    }

    test('no code and no wait at first', () {
      expect(AppPasscode.isSet, isFalse);
      expect(AppPasscode.waitUntil, isNull);
    });

    test('a code is stored as a salted hash and its rounds', () async {
      await AppPasscode.set('1234');
      expect(AppPasscode.isSet, isTrue);

      final parts =
          CacheService.get<String>(CacheService.keyLockCode)!.split(r'$');
      expect(parts, hasLength(4));
      expect(parts[0], 'pbkdf2-sha256');
      expect(parts[1], '${AppPasscode.iterations}');
      final salt = base64.decode(parts[2]);
      expect(salt, hasLength(16));
      expect(base64.decode(parts[3]),
          pbkdf2Sha256(utf8.encode('1234'), salt, 1));
    });

    test('the same code gets a new salt every time', () async {
      String salt() =>
          CacheService.get<String>(CacheService.keyLockCode)!.split(r'$')[2];
      await AppPasscode.set('1234');
      final first = salt();
      await AppPasscode.set('1234');
      expect(salt(), isNot(first));
    });

    test('the right code opens, another one does not', () async {
      await AppPasscode.set('1234');
      expect(await AppPasscode.check('1234'), CodeCheck.ok);
      expect(await AppPasscode.check('4321'), CodeCheck.wrong);
      // Not a code at all: wrong, and nothing to hash
      final before = derivations;
      expect(await AppPasscode.check('12'), CodeCheck.wrong);
      expect(derivations, before);
    });

    test('the fifth wrong code in a row starts the wait, which checks nothing',
        () async {
      await AppPasscode.set('1234');
      for (var i = 1; i < AppPasscode.freeTries; i++) {
        expect(await AppPasscode.check('0000'), CodeCheck.wrong);
      }
      expect(await AppPasscode.check('0000'), CodeCheck.wait);
      expect(AppPasscode.waitUntil, now.add(AppPasscode.wait));

      // Even the right code waits, and is not hashed
      final before = derivations;
      now = now.add(const Duration(seconds: 29));
      expect(await AppPasscode.check('1234'), CodeCheck.wait);
      expect(derivations, before);
    });

    test('after the wait every wrong code waits again, the right one ends it',
        () async {
      await AppPasscode.set('1234');
      await wrongCodes(AppPasscode.freeTries);
      expect(AppPasscode.waitUntil, isNotNull);

      now = now.add(AppPasscode.wait);
      expect(AppPasscode.waitUntil, isNull);
      expect(await AppPasscode.check('0000'), CodeCheck.wait);
      expect(AppPasscode.waitUntil, now.add(AppPasscode.wait));

      now = now.add(AppPasscode.wait);
      expect(await AppPasscode.check('1234'), CodeCheck.ok);
      expect(CacheService.get<int>(CacheService.keyLockFailures), isNull);
      expect(AppPasscode.waitUntil, isNull);
      // A fresh start: four free tries again
      expect(await AppPasscode.check('0000'), CodeCheck.wrong);
    });

    test('a clock set back never stretches the wait', () async {
      await AppPasscode.set('1234');
      final start = now;
      await wrongCodes(AppPasscode.freeTries);

      // A little back: the wait ends when it would have
      now = start.subtract(const Duration(seconds: 20));
      expect(AppPasscode.waitUntil, start.add(AppPasscode.wait));
      // Far back: no wait
      now = start.subtract(const Duration(minutes: 5));
      expect(AppPasscode.waitUntil, isNull);
      expect(await AppPasscode.check('1234'), CodeCheck.ok);
    });

    test('the code and the wrong codes survive a restart', () async {
      await AppPasscode.set('1234');
      await wrongCodes(AppPasscode.freeTries - 1);
      // The writes were not awaited: let them reach the disk
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await Hive.close();

      await CacheService.init(path: dir.path);
      expect(AppPasscode.isSet, isTrue);
      expect(await AppPasscode.check('0000'), CodeCheck.wait);
      now = now.add(AppPasscode.wait);
      expect(await AppPasscode.check('1234'), CodeCheck.ok);
    });

    test('a stored value that does not read as a hash opens nothing',
        () async {
      await CacheService.set(CacheService.keyLockCode, 'not a hash');
      expect(AppPasscode.isSet, isTrue);
      expect(await AppPasscode.check('1234'), CodeCheck.wrong);
    });

    test('clear forgets the code, the wrong codes and the wait', () async {
      await AppPasscode.set('1234');
      await wrongCodes(AppPasscode.freeTries);
      AppPasscode.clear();
      expect(AppPasscode.isSet, isFalse);
      expect(AppPasscode.waitUntil, isNull);
      expect(CacheService.get<int>(CacheService.keyLockFailures), isNull);
    });

    test('a code is four digits from 0 to 9', () {
      expect(AppPasscode.isValid('1234'), isTrue);
      expect(AppPasscode.isValid('0000'), isTrue);
      for (final code in ['', '123', '12345', '12a4', '12 4', '١٢٣٤']) {
        expect(AppPasscode.isValid(code), isFalse, reason: code);
      }
    });

    test('the real hash: all its rounds, in a background isolate', () async {
      AppPasscode.derive = realDerive;
      await AppPasscode.set('1234');
      final parts =
          CacheService.get<String>(CacheService.keyLockCode)!.split(r'$');
      expect(
          base64.decode(parts[3]),
          pbkdf2Sha256(utf8.encode('1234'), base64.decode(parts[2]),
              AppPasscode.iterations));
      expect(await AppPasscode.check('1234'), CodeCheck.ok);
      expect(await AppPasscode.check('1235'), CodeCheck.wrong);
    });
  });
}
