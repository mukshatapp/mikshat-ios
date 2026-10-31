import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class MapPoint {
  const MapPoint(this.name, this.latitude, this.longitude);
  final String name;
  final double latitude;
  final double longitude;
  factory MapPoint.fromMap(Map data) => MapPoint(
    data['name'] as String? ?? 'نقطة الخريطة',
    (data['lat'] as num).toDouble(),
    (data['lon'] as num).toDouble(),
  );
  Map<String, Object> toMap() => {
    'name': name,
    'lat': latitude,
    'lon': longitude,
  };
}

/// Only the native engine produces map, search, route and GPS results.
class MapEngine extends ChangeNotifier {
  static const channel = MethodChannel('com.mikshat.prototype/engine');
  static const events = EventChannel('com.mikshat.prototype/events');
  StreamSubscription<dynamic>? _subscription;
  bool ready = false, searching = false, recording = false, navigating = false;
  String? error;
  String status = 'تجهيز ملفات الخرائط…';
  String mode = 'direct';
  double speed = 0, distance = 0, heading = 0, bearing = 0, trackLength = 0;
  int trackPoints = 0;
  MapPoint? location, selected;
  List<MapPoint> results = [];
  List<Map<String, dynamic>> tracks = [];
  int _queryId = 0;

  Future<void> initialize() async {
    _subscription = events.receiveBroadcastStream().listen(
      _onEvent,
      onError: (Object e) {
        error = '$e';
        notifyListeners();
      },
    );
    await perform(() async {
      await channel.invokeMethod('initialize');
      ready = true;
      status = 'خرائط السعودية جاهزة دون اتصال';
      await refreshTracks();
    });
  }

  Future<void> perform(Future<void> Function() action) async {
    try {
      error = null;
      await action();
    } on PlatformException catch (e) {
      error = e.message ?? e.code;
    } catch (e) {
      error = '$e';
    }
    notifyListeners();
  }

  void _onEvent(dynamic value) {
    final data = Map<String, dynamic>.from(value as Map);
    switch (data['type']) {
      case 'status':
        status = data['message'] as String;
      case 'location':
        location = MapPoint.fromMap(data);
        speed = (data['speed'] as num? ?? 0).toDouble();
      case 'heading':
        heading = (data['heading'] as num).toDouble();
      case 'selection':
        selected = MapPoint.fromMap(data);
      case 'search':
        if (data['id'] != _queryId) return;
        results = (data['items'] as List)
            .map((e) => MapPoint.fromMap(e as Map))
            .toList();
        searching = !(data['done'] as bool? ?? false);
      case 'route':
        distance = (data['distance'] as num? ?? 0).toDouble();
        bearing = (data['bearing'] as num? ?? 0).toDouble();
        status = data['message'] as String? ?? 'الملاحة تعمل';
      case 'recording':
        recording = data['active'] as bool;
        trackLength = (data['distance'] as num? ?? 0).toDouble();
        trackPoints = (data['points'] as num? ?? 0).toInt();
      case 'error':
        error = data['message'] as String;
    }
    notifyListeners();
  }

  Future<void> search(String query) async {
    final id = ++_queryId;
    results = [];
    searching = query.trim().isNotEmpty;
    notifyListeners();
    await perform(() async {
      await channel.invokeMethod('search', {'query': query.trim(), 'id': id});
      if (query.trim().isEmpty) searching = false;
    });
  }

  Future<void> select(MapPoint point) => perform(() async {
    selected = point;
    await channel.invokeMethod('select', point.toMap());
  });
  Future<void> navigate(String value) => perform(() async {
    if (selected == null) return;
    await channel.invokeMethod('navigate', {
      ...selected!.toMap(),
      'mode': value,
    });
    mode = value;
    navigating = true;
  });
  Future<void> stopNavigation() => perform(() async {
    await channel.invokeMethod('stopNavigation');
    navigating = false;
  });
  Future<void> record() => perform(() async {
    await channel.invokeMethod('startRecording');
    recording = true;
  });
  Future<void> finishRecording(bool save) => perform(() async {
    await channel.invokeMethod('stopRecording', {'save': save});
    recording = false;
    await refreshTracks();
  });
  Future<void> refreshTracks() async {
    final list = await channel.invokeListMethod<Map>('tracks') ?? [];
    tracks = list.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<void> command(String name) => perform(() async {
    await channel.invokeMethod(name);
  });
  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

String formatDistance(double metres) => metres >= 1000
    ? '${(metres / 1000).toStringAsFixed(1)} كم'
    : '${metres.round()} متر';
