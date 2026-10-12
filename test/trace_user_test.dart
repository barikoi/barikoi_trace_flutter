import 'package:barikoi_trace_flutter/barikoi_trace_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TraceUser model', () {
    test('minimal constructor sets defaults', () {
      final DateTime now = DateTime.utc(2026, 1, 1);
      final TraceUser user = TraceUser(userId: 'u-1', updatedAt: now);

      expect(user.userId, 'u-1');
      expect(user.phone, isNull);
      expect(user.companyId, isNull);
      expect(user.group, isNull);
      expect(user.lastLat, 0);
      expect(user.lastLon, 0);
      expect(user.updatedAt, now);
    });

    test('full constructor sets all fields', () {
      final DateTime now = DateTime.utc(2026, 10, 12, 12, 0);
      final TraceUser user = TraceUser(
        userId: 'u-2',
        phone: '01700032522',
        companyId: 'comp-1',
        group: 'group-1',
        lastLat: 23.8103,
        lastLon: 90.4125,
        updatedAt: now,
      );

      expect(user.userId, 'u-2');
      expect(user.phone, '01700032522');
      expect(user.companyId, 'comp-1');
      expect(user.group, 'group-1');
      expect(user.lastLat, 23.8103);
      expect(user.lastLon, 90.4125);
      expect(user.updatedAt, now);
    });

    test('fromMap decodes standard payload', () {
      final Map<String, Object?> map = <String, Object?>{
        'userId': 'u-3',
        'phone': '01800000000',
        'companyId': 'comp-xyz',
        'group': 'grp-abc',
        'lastLat': 23.777,
        'lastLon': 90.399,
        'updatedAt': 1700000000000,
      };

      final TraceUser user = TraceUser.fromMap(map);
      expect(user.userId, 'u-3');
      expect(user.phone, '01800000000');
      expect(user.companyId, 'comp-xyz');
      expect(user.group, 'grp-abc');
      expect(user.lastLat, 23.777);
      expect(user.lastLon, 90.399);
      expect(user.updatedAt.millisecondsSinceEpoch, 1700000000000);
      expect(user.updatedAt.isUtc, isTrue);
    });

    test('fromMap ignores legacy name and email and extraneous keys', () {
      final Map<String, Object?> map = <String, Object?>{
        'userId': 'u-4',
        'name': 'Legacy Name',
        'email': 'legacy@example.com',
        'phone': '01900000000',
        'extra_backend_field': 'some_data',
        'updatedAt': 1600000000000,
      };

      final TraceUser user = TraceUser.fromMap(map);
      expect(user.userId, 'u-4');
      expect(user.phone, '01900000000');
      expect(user.companyId, isNull);
      expect(user.group, isNull);
    });

    test('fromMap handles missing or malformed fields safely', () {
      final TraceUser user = TraceUser.fromMap(<String, Object?>{});
      expect(user.userId, '');
      expect(user.phone, isNull);
      expect(user.companyId, isNull);
      expect(user.group, isNull);
      expect(user.lastLat, 0);
      expect(user.lastLon, 0);
      expect(user.updatedAt.millisecondsSinceEpoch, 0);
    });

    test('toMap does not contain name or email keys', () {
      final TraceUser user = TraceUser(
        userId: 'u-5',
        phone: '01700000000',
        companyId: 'c-5',
        group: 'g-5',
        updatedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000, isUtc: true),
      );

      final Map<String, Object?> map = user.toMap();
      expect(map.containsKey('name'), isFalse);
      expect(map.containsKey('email'), isFalse);
      expect(map['userId'], 'u-5');
      expect(map['phone'], '01700000000');
      expect(map['companyId'], 'c-5');
      expect(map['group'], 'g-5');
      expect(map['updatedAt'], 1700000000000);
    });

    test('equality and hashCode match for identical properties', () {
      final DateTime dt = DateTime.utc(2026, 5, 1);
      final TraceUser a = TraceUser(
        userId: 'u-same',
        phone: '01700000000',
        companyId: 'comp',
        group: 'grp',
        lastLat: 23.0,
        lastLon: 90.0,
        updatedAt: dt,
      );
      final TraceUser b = TraceUser(
        userId: 'u-same',
        phone: '01700000000',
        companyId: 'comp',
        group: 'grp',
        lastLat: 23.0,
        lastLon: 90.0,
        updatedAt: dt,
      );
      final TraceUser c = TraceUser(
        userId: 'u-different',
        phone: '01700000000',
        updatedAt: dt,
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });

    test('toString formats correctly without name and email', () {
      final DateTime dt = DateTime.utc(2026, 1, 1);
      final TraceUser user = TraceUser(userId: 'u-str', phone: '017', updatedAt: dt);

      expect(user.toString(), contains('userId: u-str'));
      expect(user.toString(), contains('phone: 017'));
      expect(user.toString().contains('name:'), isFalse);
      expect(user.toString().contains('email:'), isFalse);
    });
  });
}
