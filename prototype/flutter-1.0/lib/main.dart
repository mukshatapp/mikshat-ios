import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/engine.dart';

const green = Color(0xff164e3f);
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MukshatApp());
}

class MukshatApp extends StatelessWidget {
  const MukshatApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'مكشات 1.0',
    debugShowCheckedModeBanner: false,
    locale: const Locale('ar'),
    supportedLocales: const [Locale('ar'), Locale('en')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: green),
      fontFamily: 'Zain',
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xfff8f8ef),
    ),
    home: const MapScreen(),
  );
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final engine = MapEngine();
  DateTime? _lastBack;
  @override
  void initState() {
    super.initState();
    engine.initialize();
  }

  @override
  void dispose() {
    engine.dispose();
    super.dispose();
  }

  void message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  Widget nativeMap() {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return const UiKitView(viewType: 'com.mikshat.prototype/map');
    }
    return PlatformViewLink(
      viewType: 'com.mikshat.prototype/map',
      surfaceFactory: (context, controller) => AndroidViewSurface(
        controller: controller as AndroidViewController,
        gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
        hitTestBehavior: PlatformViewHitTestBehavior.opaque,
      ),
      onCreatePlatformView: (params) {
        return PlatformViewsService.initExpensiveAndroidView(
            id: params.id,
            viewType: 'com.mikshat.prototype/map',
            layoutDirection: TextDirection.ltr,
            onFocus: () => params.onFocusChanged(true),
          )
          ..addOnPlatformViewCreatedListener(params.onPlatformViewCreated)
          ..create();
      },
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: engine,
    builder: (context, _) => PopScope(
      canPop: !engine.navigating,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || !engine.navigating) return;
        final now = DateTime.now();
        if (_lastBack != null &&
            now.difference(_lastBack!) < const Duration(seconds: 2)) {
          engine.stopNavigation();
          _lastBack = null;
        } else {
          _lastBack = now;
          message('اضغط الرجوع مرة أخرى للخروج من الملاحة');
        }
      },
      child: Scaffold(
        body: Stack(
          children: [
            Positioned.fill(
              child: engine.ready ? nativeMap() : const SizedBox(),
            ),
            SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 6,
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.terrain, color: green),
                            const SizedBox(width: 8),
                            const Text(
                              'مكشات 1.0',
                              style: TextStyle(fontSize: 22),
                            ),
                            const Spacer(),
                            Flexible(
                              child: Text(
                                engine.recording
                                    ? 'جارٍ تسجيل المسار'
                                    : engine.status,
                                style: const TextStyle(fontSize: 14),
                                maxLines: 2,
                              ),
                            ),
                            IconButton(
                              onPressed: about,
                              icon: const Icon(Icons.info_outline),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (engine.error != null)
                    Material(
                      color: Colors.red.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(
                          engine.error!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    ),
                  if (!engine.ready)
                    const Expanded(
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  if (engine.ready)
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(10),
                                  child: Text(
                                    '${engine.speed.round()}\nكم/س',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 23,
                                      color: green,
                                    ),
                                  ),
                                ),
                              ),
                              control(
                                Icons.add,
                                'تكبير',
                                () => engine.command('zoomIn'),
                              ),
                              control(
                                Icons.remove,
                                'تصغير',
                                () => engine.command('zoomOut'),
                              ),
                              control(
                                Icons.my_location,
                                'موقعي',
                                () => engine.command('locate'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (engine.ready)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (engine.navigating)
                                Row(
                                  children: [
                                    IconButton(
                                      onPressed: engine.stopNavigation,
                                      icon: const Icon(Icons.close),
                                      tooltip: 'إنهاء الملاحة',
                                    ),
                                    Expanded(
                                      child: Text(
                                        formatDistance(engine.distance),
                                        style: const TextStyle(fontSize: 26),
                                      ),
                                    ),
                                    Transform.rotate(
                                      angle:
                                          (engine.bearing - engine.heading) *
                                          math.pi /
                                          180,
                                      child: const Icon(
                                        Icons.navigation,
                                        color: green,
                                        size: 36,
                                      ),
                                    ),
                                  ],
                                )
                              else if (engine.selected != null) ...[
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        engine.selected!.name,
                                        style: const TextStyle(fontSize: 20),
                                      ),
                                    ),
                                    IconButton(
                                      onPressed: () => engine.command('share'),
                                      icon: const Icon(Icons.share),
                                    ),
                                  ],
                                ),
                                Wrap(
                                  alignment: WrapAlignment.spaceEvenly,
                                  spacing: 8,
                                  children: [
                                    TextButton.icon(
                                      onPressed: () =>
                                          engine.navigate('vehicle'),
                                      icon: const Icon(Icons.directions_car),
                                      label: const Text('بالسيارة'),
                                    ),
                                    TextButton.icon(
                                      onPressed: () =>
                                          engine.navigate('direct'),
                                      icon: const Icon(Icons.north),
                                      label: const Text('مباشر'),
                                    ),
                                    TextButton.icon(
                                      onPressed: () =>
                                          engine.navigate('compass'),
                                      icon: const Icon(Icons.explore),
                                      label: const Text('بالبوصلة'),
                                    ),
                                  ],
                                ),
                              ],
                              if (engine.recording)
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '${formatDistance(engine.trackLength)} · ${engine.trackPoints} نقطة',
                                      ),
                                    ),
                                    FilledButton.icon(
                                      onPressed: finishRecording,
                                      icon: const Icon(Icons.stop),
                                      label: const Text('إيقاف'),
                                    ),
                                  ],
                                ),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceEvenly,
                                children: [
                                  TextButton.icon(
                                    onPressed: search,
                                    icon: const Icon(Icons.search),
                                    label: const Text('البحث'),
                                  ),
                                  TextButton.icon(
                                    onPressed: engine.recording
                                        ? finishRecording
                                        : engine.record,
                                    icon: Icon(
                                      engine.recording
                                          ? Icons.stop_circle
                                          : Icons.fiber_manual_record,
                                      color: Colors.red,
                                    ),
                                    label: const Text('المسار'),
                                  ),
                                  TextButton.icon(
                                    onPressed: tracks,
                                    icon: const Icon(Icons.route),
                                    label: const Text('مساراتي'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (engine.ready)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: InkWell(
                        onTap: () => engine.command('attribution'),
                        child: const Text(
                          'Map data © OpenStreetMap and Organic Maps',
                          textDirection: TextDirection.ltr,
                          style: TextStyle(
                            fontSize: 11,
                            backgroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
  Widget control(IconData icon, String label, VoidCallback action) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: FloatingActionButton.small(
      heroTag: label,
      tooltip: label,
      onPressed: action,
      backgroundColor: Colors.white,
      child: Icon(icon, color: green),
    ),
  );
  Future<void> search() async {
    final text = TextEditingController();
    Timer? debounce;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => ListenableBuilder(
        listenable: engine,
        builder: (context, _) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              20,
              16,
              MediaQuery.viewInsetsOf(context).bottom + 12,
            ),
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * .6,
              child: Column(
                children: [
                  TextField(
                    controller: text,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'ابحث في الخرائط المحفوظة',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      debounce?.cancel();
                      debounce = Timer(
                        const Duration(milliseconds: 300),
                        () => engine.search(value),
                      );
                    },
                    onSubmitted: engine.search,
                  ),
                  if (engine.searching) const LinearProgressIndicator(),
                  Expanded(
                    child: ListView.builder(
                      itemCount: engine.results.length,
                      itemBuilder: (context, i) {
                        final point = engine.results[i];
                        return ListTile(
                          title: Text(point.name),
                          leading: const Icon(Icons.place_outlined),
                          onTap: () {
                            engine.select(point);
                            Navigator.pop(context);
                          },
                        );
                      },
                    ),
                  ),
                  if (!engine.searching && engine.results.isEmpty)
                    const Text('اكتب اسمًا للبحث دون اتصال'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    debounce?.cancel();
    text.dispose();
  }

  Future<void> finishRecording() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('إيقاف تسجيل المسار'),
      content: const Text('حفظ المسار المسجّل؟'),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(context);
            engine.finishRecording(false);
          },
          child: const Text('حذف'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.pop(context);
            engine.finishRecording(true);
          },
          child: const Text('حفظ'),
        ),
      ],
    ),
  );
  Future<void> tracks() async {
    await engine.perform(engine.refreshTracks);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('مساراتي', style: TextStyle(fontSize: 24)),
            if (engine.tracks.isEmpty)
              const ListTile(title: Text('لا توجد مسارات محفوظة بعد')),
            for (final track in engine.tracks)
              ListTile(
                title: Text(track['name'] as String),
                subtitle: Text('${track['points']} نقطة'),
                leading: const Icon(Icons.route),
                onTap: () async {
                  Navigator.pop(context);
                  await MapEngine.channel.invokeMethod('showTrack', {
                    'id': track['id'],
                  });
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> about() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('نبذة عن مكشات 1.0'),
      content: const SingleChildScrollView(
        child: Text(
          'نموذج تجريبي بواجهة Flutter ومحرك Organic Maps، لعرض الخرائط العربية والبحث والتوجيه وتسجيل المسارات دون اتصال.\n\nتمت برمجته بواسطة شركة الهدف القابضة.\n\nMap data © OpenStreetMap and Organic Maps\n\nتُقارن نتائج هذا النموذج بإصدار 4.6 بعد الاختبار على الأجهزة.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => engine.command('attribution'),
          child: const Text('مصادر الخرائط والتراخيص'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إغلاق'),
        ),
      ],
    ),
  );
}
