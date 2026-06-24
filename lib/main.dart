// FILE: lib/main.dart
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_foreground_task/models/foreground_task_event_action.dart'; // New import for eventAction
import 'core/crypto_service.dart';
import 'core/metrics_service.dart';
import 'core/storage_service.dart';
import 'network/transport_service.dart';
import 'routing/flooding_strategy.dart';
import 'routing/routing_manager.dart';
import 'ui/home_screen.dart';

final sl = GetIt.instance;

// ── Foreground service task handler ─────────────────────────────────────────
// Updated for v9.x: Renamed onEvent to onRepeatEvent, signatures to Future<void>,
// removed SendPort?, added TaskStarter to onStart, bool isTimeout to onDestroy.

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(_MeshTaskHandler());
}

class _MeshTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint('Foreground service: started');
  }

  @override
  Future<void> onRepeatEvent(DateTime timestamp) async {
    // Heartbeat — keeps the process alive so Nearby Connections stays running.
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    debugPrint('Foreground service: stopped');
  }
}

Future<void> _initForegroundTask() async {
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions( // Removed iconData
      channelId:          'mesh_service',
      channelName:        'Mesh Network Service',
      channelDescription: 'Keeps the mesh network active for message delivery',
      channelImportance:  NotificationChannelImportance.LOW,
      showWhen:           false,
    ),
    iosNotificationOptions: const IOSNotificationOptions(
      showNotification: false,
      playSound:        false,
    ),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction:      ForegroundTaskEventAction.repeat(5000), // Replaced interval
      autoRunOnBoot:    true,
      allowWakeLock:    true,
    ),
  );
}

// ── Permissions ──────────────────────────────────────────────────────────────

Future<void> _requestPermissions() async {
  if (!Platform.isAndroid) return;
  await[
    Permission.bluetooth,
    Permission.bluetoothScan,
    Permission.bluetoothConnect,
    Permission.bluetoothAdvertise,
    Permission.locationWhenInUse,
    Permission.nearbyWifiDevices, // Required for Android 13+
    Permission.notification,
    Permission.camera,            // Prevents crash when opening QR scanner
  ].request();

  // Prevent modern Android flavors from killing the background mesh node
  if (await Permission.ignoreBatteryOptimizations.isDenied) {
    await Permission.ignoreBatteryOptimizations.request();
  }
}

// ── Entry point ───────────────────────────────────────────────────────────────

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await _requestPermissions();
  FlutterForegroundTask.initCommunicationPort();

  if (Platform.isAndroid) {
    await _initForegroundTask();
    await FlutterForegroundTask.startService(
      notificationTitle: 'Mesh Messenger Active',
      notificationText:  'Scanning for nearby devices…',
      callback:          startCallback,
      notificationIcon:  null,
    );
  }

  // Register services — order matters: storage and crypto must be first.
  sl.registerLazySingleton<CryptoService>(() => CryptoService());
  sl.registerLazySingleton<StorageService>(() => StorageService());
  sl.registerLazySingleton<MetricsService>(() => MetricsService());
  sl.registerLazySingleton<RoutingManager>(
      () => RoutingManager(FloodingStrategy()));
  sl.registerLazySingleton<TransportService>(
      () => TransportService(sl<RoutingManager>()));

  await sl<StorageService>().init();
  await sl<MetricsService>().init();
  await sl<CryptoService>().init();

  if (Platform.isAndroid) {
    await sl<TransportService>().initialize(sl<CryptoService>().userId);
  }

  runApp(const MeshApp());
}

// ── App root ──────────────────────────────────────────────────────────────────

class MeshApp extends StatelessWidget {
  const MeshApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mesh Messenger',
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor:  Colors.blue,
          brightness: Brightness.dark,
        ),
      ),
      home:                       const HomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
