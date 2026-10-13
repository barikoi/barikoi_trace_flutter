import 'package:barikoi_trace_flutter/barikoi_trace_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TraceModeSource', () {
    test('fromWire maps case-insensitively', () {
      expect(TraceModeSource.fromWire('REMOTE'), TraceModeSource.remote);
      expect(TraceModeSource.fromWire('remote'), TraceModeSource.remote);
      expect(TraceModeSource.fromWire('ReMoTe'), TraceModeSource.remote);
      expect(TraceModeSource.fromWire('LOCAL'), TraceModeSource.local);
      expect(TraceModeSource.fromWire('local'), TraceModeSource.local);
      expect(TraceModeSource.fromWire('Local'), TraceModeSource.local);
    });

    test('fromWire falls back to local on null or unknown value', () {
      expect(TraceModeSource.fromWire(null), TraceModeSource.local);
      expect(TraceModeSource.fromWire(''), TraceModeSource.local);
      expect(TraceModeSource.fromWire('unknown'), TraceModeSource.local);
      expect(TraceModeSource.fromWire('custom'), TraceModeSource.local);
    });

    test('toWire produces uppercase wire strings matching native SDKs', () {
      expect(TraceModeSource.local.toWire(), 'LOCAL');
      expect(TraceModeSource.remote.toWire(), 'REMOTE');
    });
  });
}
