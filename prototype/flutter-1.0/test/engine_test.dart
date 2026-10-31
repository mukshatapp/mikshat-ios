import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/core/engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() {
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.mikshat.prototype/events'),
      (_) async => null,
    );
    messenger.setMockMethodCallHandler(MapEngine.channel, (call) async {
      if (call.method == 'tracks') return <Map>[];
      return null;
    });
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.mikshat.prototype/events'),
      null,
    );
    messenger.setMockMethodCallHandler(MapEngine.channel, null);
  });
  test('preserves coordinates in bridge round trips', () {
    const original = MapPoint('وادي', 24.7136, 46.6753);
    final point = MapPoint.fromMap(original.toMap());
    expect(point.latitude, original.latitude);
    expect(point.longitude, original.longitude);
    expect(point.name, original.name);
  });
  test('distance switches to km and preserves metre formatting', () {
    expect(formatDistance(999), '999 متر');
    expect(formatDistance(1000), '1.0 كم');
    expect(formatDistance(9860), '9.9 كم');
  });
  test('location denial never reports recording as started', () async {
    final engine = MapEngine();
    messenger.setMockMethodCallHandler(MapEngine.channel, (call) async {
      throw PlatformException(
        code: 'LOCATION_PERMISSION',
        message: 'GPS denied',
      );
    });
    await engine.record();
    expect(engine.recording, isFalse);
    expect(engine.error, 'GPS denied');
    engine.dispose();
  });
  test('failed route does not start navigation', () async {
    final engine = MapEngine();
    await engine.select(const MapPoint('نقطة', 24, 47));
    messenger.setMockMethodCallHandler(MapEngine.channel, (call) async {
      throw PlatformException(code: 'GPS_PENDING', message: 'انتظر GPS');
    });
    await engine.navigate('vehicle');
    expect(engine.navigating, isFalse);
    expect(engine.error, 'انتظر GPS');
    engine.dispose();
  });
}
