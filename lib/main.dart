import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';


// ============================================================
// SMART BLIND STICK
// ============================================================

// BLE
const String stickName = 'Smart Blind Stick';

const String serviceUuid =
    '4fafc201-1fb5-459e-8fcc-c5c9c331914b';

const String characteristicUuid =
    'beb5483e-36e1-4688-b7f5-ea07361b26a8';


// ============================================================
// NOTIFICATION
// ============================================================

final FlutterLocalNotificationsPlugin notifications =
    FlutterLocalNotificationsPlugin();


// ============================================================
// DATABASE
// ============================================================

class DatabaseHelper {
  static Database? _database;

  static Future<Database> get database async {
    if (_database != null) {
      return _database!;
    }

    final dbPath = await getDatabasesPath();

    final path = p.join(
      dbPath,
      'smart_blind_stick.db',
    );

    _database = await openDatabase(
  path,
  version: 3,

  onCreate: (db, version) async {
    await _createTables(db);
  },

  onUpgrade: (db, oldVersion, newVersion) async {
    if (oldVersion < 3) {
      await db.execute(
        'ALTER TABLE locations ADD COLUMN timestamp TEXT',
      );
    }
  },
);

    return _database!;
  }


  static Future<void> _createTables(Database db) async {

    // LOCATION
    await db.execute('''
      CREATE TABLE IF NOT EXISTS locations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        timestamp TEXT NOT NULL
      )
    ''');


    // SOS
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sos_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        latitude REAL,
        longitude REAL,
        timestamp TEXT NOT NULL,
        status TEXT NOT NULL
      )
    ''');
  }


  // ==========================================================
  // SAVE LOCATION
  // ==========================================================

 static Future<int> saveLocation(
  double latitude,
  double longitude,
) async {
  final db = await database;

  final id = await db.insert(
    'locations',
    {
      'latitude': latitude,
      'longitude': longitude,
      'timestamp': DateTime.now().toIso8601String(),
    },
  );

  print(
    'LOCATION SAVED TO DATABASE: $id',
  );

  return id;
}

  static Future<List<Map<String, Object?>>> getLocations() async {
  final db = await database;

  return await db.query(
    'locations',
    orderBy: 'timestamp DESC',
  );
  }
  // ==========================================================
  // GET LAST LOCATION
  // ==========================================================

  static Future<Map<String, dynamic>?>
      getLastLocation() async {

    final db = await database;

    final result = await db.query(
      'locations',
      orderBy: 'timestamp DESC',
      limit: 1,
    );

    if (result.isEmpty) {
      return null;
    }

    return result.first;
  }


  // ==========================================================
  // SAVE SOS
  // ==========================================================

  static Future<void> saveSOS(
    double? latitude,
    double? longitude,
  ) async {

    final db = await database;

    await db.insert(
      'sos_logs',
      {
        'latitude': latitude,
        'longitude': longitude,
        'timestamp':
            DateTime.now().toIso8601String(),
        'status': 'SOS Emergency',
      },
    );

    print('SOS SAVED TO DATABASE');
  }
}


// ============================================================
// MAIN
// ============================================================

Future<void> main() async {

  WidgetsFlutterBinding.ensureInitialized();

  await DatabaseHelper.database;

  const androidSettings =
      AndroidInitializationSettings(
    '@mipmap/ic_launcher',
  );

  const iosSettings =
      DarwinInitializationSettings();

  const settings =
      InitializationSettings(
    android: androidSettings,
    iOS: iosSettings,
  );

  await notifications.initialize(
    settings: settings,
  );

  await notifications
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.requestNotificationsPermission();

  runApp(
    const SmartBlindStickApp(),
  );
}


// ============================================================
// APP
// ============================================================

class SmartBlindStickApp
    extends StatelessWidget {

  const SmartBlindStickApp({
    super.key,
  });

  @override
  Widget build(BuildContext context) {

    return MaterialApp(
      debugShowCheckedModeBanner: false,

      title: 'Smart Blind Stick',

      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0B1420),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF55D6B3),
          brightness: Brightness.dark,
          surface: const Color(0xFF172638),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF101C2C),
          foregroundColor: Colors.white,
          centerTitle: true,
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF172638),
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0xFF263B50)),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF287C73),
            foregroundColor: Colors.white,
            minimumSize: const Size(0, 48),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ),

      home:
          const DashboardPage(),
    );
  }
}


// ============================================================
// DASHBOARD
// ============================================================

class DashboardPage
    extends StatefulWidget {

  const DashboardPage({
    super.key,
  });

  @override
  State<DashboardPage> createState() =>
      _DashboardPageState();
}


class _DashboardPageState
    extends State<DashboardPage> {


  // ==========================================================
  // BLE
  // ==========================================================

  BluetoothDevice? bleDevice;

  BluetoothCharacteristic?
      distanceCharacteristic;

  StreamSubscription<
          BluetoothConnectionState>?
      bleConnectionSubscription;

  StreamSubscription<List<int>>?
      bleDataSubscription;

  bool bleConnected = false;

  bool bleConnecting = false;


  // ==========================================================
  // GPS
  // ==========================================================

  Position? currentPosition;

  Position? stickLocation;

  StreamSubscription<Position>?
      gpsSubscription;

  GoogleMapController?
      googleMapController;


  // ==========================================================
  // LOCATION DATABASE
  // ==========================================================

  Timer? locationTimer;

  Map<String, dynamic>?
      lastSavedLocation;

  DateTime? lastSavedTime;


  // ==========================================================
  // BATTERY
  // ==========================================================

  double batteryPercent = 70.0;

  bool isCharging = false;

  double batteryVoltage = 0;

  int batteryPercentage = 70;


  // ==========================================================
  // SENSOR
  // ==========================================================

  double obstacleDistance = 999;

  String obstacleStatus =
      'Tiada halangan';


  // ==========================================================
  // EMERGENCY
  // ==========================================================

  List<String> emergencyLogs = [];


  // ==========================================================
  // INIT
  // ==========================================================

  @override
  void initState() {

    super.initState();

    startGPS();

    loadLastLocation();

    startLocationTimer();
  }


  // ==========================================================
  // LOAD LAST LOCATION
  // ==========================================================

  Future<void> loadLastLocation() async {

    final data =
        await DatabaseHelper.getLastLocation();

    if (!mounted) return;

    setState(() {

      lastSavedLocation = data;

      if (data != null) {

        lastSavedTime =
            DateTime.tryParse(
          data['timestamp'].toString(),
        );
      }
    });
  }


  // ==========================================================
  // LOCATION TIMER
  // ==========================================================

  void startLocationTimer() {
  locationTimer?.cancel();

  locationTimer = Timer.periodic(
    const Duration(minutes: 10),
    (Timer timer) async {
      try {
        if (!mounted) {
          timer.cancel();
          return;
        }

        if (currentPosition == null) {
          debugPrint(
            'AUTO SAVE: GPS belum mendapatkan lokasi.',
          );
          return;
        }

        final Position position = currentPosition!;

        await DatabaseHelper.saveLocation(
          position.latitude,
          position.longitude,
        );

        await loadLastLocation();

        debugPrint(
          'AUTO SAVE BERJAYA\n'
          'Latitude: ${position.latitude}\n'
          'Longitude: ${position.longitude}\n'
          'Time: ${DateTime.now()}',
        );

        if (mounted) {
          setState(() {});
        }
      } catch (e) {
        debugPrint(
          'AUTO SAVE ERROR: $e',
        );
      }
    },
  );

  debugPrint(
    'Location auto-save timer started: setiap 10 minit',
  );
}

  // ==========================================================
  // SAVE LOCATION NOW
  // ==========================================================

  Future<void> saveLocationNow() async {
  try {
    if (currentPosition == null) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'GPS belum dapat lokasi. Sila tunggu GPS mendapatkan lokasi.',
          ),
          duration: Duration(seconds: 3),
        ),
      );

      return;
    }

    final Position position = currentPosition!;

    await DatabaseHelper.saveLocation(
      position.latitude,
      position.longitude,
    );

    await loadLastLocation();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Lokasi berjaya disimpan!\n'
          'Lat: ${position.latitude.toStringAsFixed(6)}\n'
          'Lng: ${position.longitude.toStringAsFixed(6)}',
        ),
        duration: const Duration(seconds: 3),
      ),
    );

    setState(() {});
  } catch (e) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Gagal simpan lokasi: $e'),
        duration: const Duration(seconds: 4),
      ),
    );
  }
}


  // ==========================================================
  // GPS
  // ==========================================================

  Future<void> startGPS() async {

    bool serviceEnabled =
        await Geolocator
            .isLocationServiceEnabled();

    if (!serviceEnabled) {

      print(
        'GPS SERVICE OFF',
      );

      return;
    }


    LocationPermission permission =
        await Geolocator.checkPermission();


    if (permission ==
        LocationPermission.denied) {

      permission =
          await Geolocator
              .requestPermission();
    }


    if (permission ==
            LocationPermission.denied ||
        permission ==
            LocationPermission
                .deniedForever) {

      print(
        'GPS PERMISSION DENIED',
      );

      return;
    }


    gpsSubscription =
        Geolocator.getPositionStream(
      locationSettings:
          const LocationSettings(
        accuracy:
            LocationAccuracy.high,
        distanceFilter: 1,
      ),
    ).listen(
      (position) {

        if (!mounted) return;

        setState(() {

          currentPosition =
              position;

          // Simulasi stick
          // ±5 meter dari phone
          stickLocation =
              Position(
            longitude:
                position.longitude,
            latitude:
                position.latitude +
                    0.000045,
            timestamp:
                position.timestamp,
            accuracy:
                position.accuracy,
            altitude:
                position.altitude,
            altitudeAccuracy:
                position.altitudeAccuracy,
            heading:
                position.heading,
            headingAccuracy:
                position.headingAccuracy,
            speed:
                position.speed,
            speedAccuracy:
                position.speedAccuracy,
            floor:
                position.floor,
            isMocked:
                position.isMocked,
          );
        });


        // Gerakkan map ikut phone

        if (googleMapController != null) {

          googleMapController!
              .animateCamera(
            CameraUpdate
                .newCameraPosition(
              CameraPosition(
                target: LatLng(
                  position.latitude,
                  position.longitude,
                ),
                zoom: 16,
              ),
            ),
          );
        }


        // Hantar lokasi phone
        // kepada XIAO

        sendLocationToStick(
          position,
        );
      },
    );
  }


  // ==========================================================
  // SEND GPS TO XIAO
  // ==========================================================

  Future<void> sendLocationToStick(
    Position position,
  ) async {

    if (!bleConnected ||
        distanceCharacteristic ==
            null) {

      return;
    }


    final location =
        'LOCATION:${position.latitude},${position.longitude}';


    try {

      await distanceCharacteristic!
          .write(
        location.codeUnits,
      );

      print(
        'LOCATION DIHANTAR KE XIAO: $location',
      );

    } catch (e) {

      print(
        'Gagal hantar lokasi: $e',
      );
    }
  }


  // ==========================================================
  // BLE CONNECT
  // ==========================================================

  Future<void>
      connectToBlindStick() async {

    if (bleConnecting) {
      return;
    }


    setState(() {
      bleConnecting = true;
    });


    try {

      print(
        'Mencari Smart Blind Stick...',
      );


      await FlutterBluePlus
          .startScan(
        timeout:
            const Duration(seconds: 10),
        androidUsesFineLocation:
            true,
      );


      await Future.delayed(
        const Duration(seconds: 10),
      );


      final results =
          FlutterBluePlus.lastScanResults;


      ScanResult? foundDevice;


      for (final result
          in results) {

        final name =
            result.device.platformName;

        print(
          'BLE DEVICE: $name',
        );


        if (name == stickName) {

          foundDevice = result;

          break;
        }
      }


      if (foundDevice == null) {

        print(
          'Smart Blind Stick tak jumpa',
        );

        if (mounted) {

          setState(() {
            bleConnecting = false;
          });
        }

        return;
      }


      bleDevice =
          foundDevice.device;


      print(
        'Device dijumpai: ${bleDevice!.platformName}',
      );


      await bleDevice!.connect(
        license:
            License.nonprofit,
        timeout:
            const Duration(seconds: 15),
        autoConnect: false,
      );


      print(
        'BLE CONNECTED',
      );


      bleConnectionSubscription =
          bleDevice!.connectionState
              .listen(
        (state) {

          if (!mounted) return;


          if (state ==
              BluetoothConnectionState
                  .connected) {

            setState(() {

              bleConnected =
                  true;

              bleConnecting =
                  false;
            });


            print(
              'Smart Blind Stick Connected',
            );

          } else {

            setState(() {

              bleConnected =
                  false;
            });


            print(
              'Smart Blind Stick Disconnected',
            );
          }
        },
      );


      final services =
          await bleDevice!
              .discoverServices();


      for (final service
          in services) {

        if (service.uuid
                .toString()
                .toLowerCase() ==
            serviceUuid
                .toLowerCase()) {

          for (final characteristic
              in service
                  .characteristics) {

            if (characteristic.uuid
                    .toString()
                    .toLowerCase() ==
                characteristicUuid
                    .toLowerCase()) {

              distanceCharacteristic =
                  characteristic;


              print(
                'Characteristic dijumpai',
              );


              if (characteristic
                  .properties
                  .notify) {

                await characteristic
                    .setNotifyValue(
                  true,
                );


                bleDataSubscription =
                    characteristic
                        .lastValueStream
                        .listen(
                  receiveStickData,
                );
              }
            }
          }
        }
      }

    } catch (e) {

      print(
        'BLE ERROR: $e',
      );


      if (mounted) {

        setState(() {
          bleConnected = false;
        });
      }

    } finally {

      if (mounted) {

        setState(() {
          bleConnecting = false;
        });
      }
    }
  }


  // ==========================================================
  // RECEIVE DATA FROM XIAO
  // ==========================================================

  void receiveStickData(
    List<int> value,
  ) {

    if (value.isEmpty) {
      return;
    }


    final data =
        String.fromCharCodes(
      value,
    ).trim();


    print(
      'DATA DARI XIAO: $data',
    );


    // ========================================================
    // SOS
    // ========================================================

    if (data == 'SOS') {

      print(
        'SOS DITERIMA DARI XIAO',
      );

      triggerEmergency();

      return;
    }


    // ========================================================
    // SENSOR
    // ========================================================

    if (data.startsWith(
      'DISTANCE:',
    )) {

      try {

        final parts =
            data.split(',');


        for (final part
            in parts) {

          if (part.startsWith(
            'DISTANCE:',
          )) {

            obstacleDistance =
                double.tryParse(
                  part
                      .replaceFirst(
                        'DISTANCE:',
                        '',
                      )
                      .trim(),
                ) ??
                999;
          }


          if (part.startsWith(
            'BATTERY:',
          )) {

            batteryVoltage =
                double.tryParse(
                  part
                      .replaceFirst(
                        'BATTERY:',
                        '',
                      )
                      .trim(),
                ) ??
                0;
          }
        }


        // Battery percentage

        batteryPercentage =
            (((batteryVoltage - 3.0) /
                        (4.2 - 3.0)) *
                    100)
                .clamp(
                  0,
                  100,
                )
                .round();


        // Obstacle status

        if (obstacleDistance <= 50) {

          obstacleStatus =
              '🔴 BAHAYA - Sangat dekat';

        } else if (
            obstacleDistance <= 100) {

          obstacleStatus =
              '🟡 AWAS - Halangan dekat';

        } else if (
            obstacleDistance <= 200) {

          obstacleStatus =
              '🟠 Berhati-hati';

        } else {

          obstacleStatus =
              '🟢 Tiada halangan';
        }


        if (mounted) {

          setState(() {});
        }

      } catch (e) {

        print(
          'Data sensor error: $e',
        );
      }
    }
  }


  // ==========================================================
  // SOS
  // ==========================================================

  Future<void>
      triggerEmergency() async {

    final now =
        DateTime.now();


    final time =
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}';


    // ========================================================
    // SAVE SOS DATABASE
    // ========================================================

    await DatabaseHelper.saveSOS(
      currentPosition?.latitude,
      currentPosition?.longitude,
    );


    // ========================================================
    // DASHBOARD LOG
    // ========================================================

    if (mounted) {

      setState(() {

        emergencyLogs.insert(
          0,
          'SOS Emergency - $time',
        );
      });
    }


    // ========================================================
    // NOTIFICATION
    // ========================================================

    const androidDetails =
        AndroidNotificationDetails(
      'smart_stick_sos',
      'Smart Blind Stick SOS',
      channelDescription:
          'Emergency notification',
      importance:
          Importance.max,
      priority:
          Priority.high,
      playSound: true,
    );


    const details =
        NotificationDetails(
      android: androidDetails,
    );


    await notifications.show(
      id: 999,
      title: '🚨 EMERGENCY SOS',
      body:
          'Butang SOS Smart Blind Stick telah ditekan!',
      notificationDetails:
          details,
    );


    print(
      'SOS BERJAYA DITERIMA',
    );


    if (currentPosition != null) {

      print(
        'SOS LOCATION: '
        '${currentPosition!.latitude}, '
        '${currentPosition!.longitude}',
      );
    }
  }


  // ==========================================================
  // TEST EMERGENCY
  // ==========================================================

  void testEmergency() {

    triggerEmergency();
  }


  // ==========================================================
  // DISCONNECT
  // ==========================================================

  Future<void>
      disconnectStick() async {

    try {

      await bleDevice?.disconnect();

    } catch (_) {}


    if (!mounted) return;


    setState(() {

      bleConnected = false;

      bleDevice = null;

      distanceCharacteristic =
          null;
    });
  }


  // ==========================================================
  // LOCATION HISTORY
  // ==========================================================

  Future<void>
      openLocationHistory() async {

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            const LocationHistoryPage(),
      ),
    );


    await loadLastLocation();
  }


  // ==========================================================
  // DISPOSE
  // ==========================================================

  @override
  void dispose() {

    locationTimer?.cancel();

    gpsSubscription?.cancel();

    bleConnectionSubscription
        ?.cancel();

    bleDataSubscription
        ?.cancel();


    super.dispose();
  }


  // ==========================================================
  // TRACK SMART BLIND STICK LOCATION
  // ==========================================================

  Future<void> trackStickLocation() async {
    final position = stickLocation;
    if (position == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lokasi tongkat belum tersedia.')),
      );
      return;
    }

    final latitude = position.latitude;
    final longitude = position.longitude;
    final url = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$latitude,$longitude',
    );

    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Google Maps tak dapat dibuka.')),
      );
    }
  }

  // ==========================================================
  // BUILD - MODERN DASHBOARD UI
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    final mapLocation = currentPosition != null
        ? LatLng(currentPosition!.latitude, currentPosition!.longitude)
        : const LatLng(3.1390, 101.6869);

    final savedLat = lastSavedLocation?['latitude'];
    final savedLng = lastSavedLocation?['longitude'];

    Widget sectionTitle(String title, {String? subtitle}) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: 0.4)),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle, style: TextStyle(color: Colors.blueGrey.shade200, fontSize: 12)),
          ],
        ],
      );
    }

    Widget infoCard({required IconData icon, required String title, required String value, required String detail, Color accent = const Color(0xFF55D6B3)}) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, color: accent, size: 25),
            const SizedBox(height: 12),
            Text(title, style: TextStyle(color: Colors.blueGrey.shade200, fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 5),
            Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(detail, style: TextStyle(color: Colors.blueGrey.shade200, fontSize: 11)),
          ]),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Column(
          children: [
            Text('Smart Blind Stick', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
            Text('SMART ASSISTIVE SYSTEM', style: TextStyle(fontSize: 9, letterSpacing: 2, color: Color(0xFF9CB3C8))),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          // BLE CONNECTION - callbacks asal dikekalkan
          Card(child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                sectionTitle('STICK CONNECTION', subtitle: 'Bluetooth device status'),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: (bleConnected ? const Color(0xFF1D554A) : const Color(0xFF49343A)),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Text(bleConnected ? 'CONNECTED' : 'NOT CONNECTED', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: bleConnected ? const Color(0xFF75E2C1) : const Color(0xFFFFA6A6))),
                ),
              ]),
              const SizedBox(height: 15),
              Row(children: [
                Icon(Icons.bluetooth, color: bleConnected ? const Color(0xFF55D6B3) : Colors.blueGrey, size: 25),
                const SizedBox(width: 10),
                Expanded(child: Text(bleConnected ? 'Smart Blind Stick connected' : 'Menunggu sambungan tongkat', style: const TextStyle(fontWeight: FontWeight.w600))),
                if (bleConnecting) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              ]),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(child: ElevatedButton.icon(
                  onPressed: bleConnecting ? null : connectToBlindStick,
                  icon: const Icon(Icons.bluetooth_searching, size: 18),
                  label: Text(bleConnecting ? 'CONNECTING...' : 'CONNECT'),
                )),
                const SizedBox(width: 10),
                Expanded(child: OutlinedButton.icon(
                  onPressed: bleConnected ? disconnectStick : null,
                  icon: const Icon(Icons.bluetooth_disabled, size: 18),
                  label: const Text('DISCONNECT'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48), foregroundColor: Colors.blueGrey.shade100, side: BorderSide(color: Colors.blueGrey.shade600), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                )),
              ]),
            ]),
          )),
          const SizedBox(height: 16),

          // LIVE MAP - marker merah boleh ditekan untuk tracking
          Card(clipBehavior: Clip.antiAlias, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.fromLTRB(16, 15, 16, 10), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              sectionTitle('LIVE GPS TRACKING', subtitle: 'Lokasi telefon dan tongkat'),
              const Icon(Icons.radar, color: Color(0xFF55D6B3)),
            ])),
            SizedBox(height: 280, child: GoogleMap(
              initialCameraPosition: CameraPosition(target: mapLocation, zoom: 16),
              onMapCreated: (controller) { googleMapController = controller; },
              myLocationEnabled: true,
              myLocationButtonEnabled: true,
              zoomControlsEnabled: true,
              markers: {
                if (stickLocation != null)
                  Marker(
                    markerId: const MarkerId('smart_stick'),
                    position: LatLng(stickLocation!.latitude, stickLocation!.longitude),
                    icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
                    infoWindow: const InfoWindow(title: 'Smart Blind Stick', snippet: 'Tekan pin untuk track lokasi'),
                    onTap: () {
                      showModalBottomSheet<void>(
                        context: context,
                        backgroundColor: const Color(0xFF172638),
                        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
                        builder: (sheetContext) => SafeArea(child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                            const Text('SMART BLIND STICK LOCATION', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                            const SizedBox(height: 12),
                            Text('Latitude: ${stickLocation!.latitude.toStringAsFixed(6)}'),
                            Text('Longitude: ${stickLocation!.longitude.toStringAsFixed(6)}'),
                            const SizedBox(height: 16),
                            SizedBox(width: double.infinity, child: ElevatedButton.icon(
                              onPressed: () { Navigator.pop(sheetContext); trackStickLocation(); },
                              icon: const Icon(Icons.near_me),
                              label: const Text('TRACK LOCATION'),
                            )),
                          ]),
                        )),
                      );
                    },
                  ),
              },
            )),
            Padding(padding: const EdgeInsets.all(12), child: Row(children: [
              const Icon(Icons.location_on, color: Color(0xFFFF6868), size: 18),
              const SizedBox(width: 5),
              Text('Tongkat', style: TextStyle(color: Colors.blueGrey.shade100, fontSize: 12)),
              const SizedBox(width: 16),
              const Icon(Icons.my_location, color: Color(0xFF55D6B3), size: 18),
              const SizedBox(width: 5),
              Text('Telefon', style: TextStyle(color: Colors.blueGrey.shade100, fontSize: 12)),
              const Spacer(),
              Text('Tap pin merah untuk track', style: TextStyle(color: Colors.blueGrey.shade300, fontSize: 10)),
            ])),
          ])),
          const SizedBox(height: 16),

          // CURRENT GPS
          Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            sectionTitle('CURRENT GPS LOCATION', subtitle: 'Lokasi semasa telefon'),
            const SizedBox(height: 16),
            if (currentPosition != null) ...[
              _coordinateRow('LATITUDE', currentPosition!.latitude),
              const SizedBox(height: 10),
              _coordinateRow('LONGITUDE', currentPosition!.longitude),
            ] else const Text('Mencari lokasi GPS...', style: TextStyle(color: Colors.orangeAccent)),
          ]))),
          const SizedBox(height: 16),

          // SAVED LOCATION
          Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [const Icon(Icons.bookmark_added, color: Color(0xFF55D6B3)), const SizedBox(width: 9), sectionTitle('SAVED LOCATION')]),
            const SizedBox(height: 14),
            if (lastSavedLocation != null) ...[
              _coordinateRow('LATITUDE', double.tryParse(savedLat.toString()) ?? 0),
              const SizedBox(height: 9),
              _coordinateRow('LONGITUDE', double.tryParse(savedLng.toString()) ?? 0),
              const SizedBox(height: 10),
              Text('Tarikh & Masa: ${formatDateTime(lastSavedTime)}', style: TextStyle(color: Colors.blueGrey.shade200, fontSize: 12)),
            ] else const Text('Belum ada lokasi disimpan.', style: TextStyle(color: Colors.blueGrey)),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: ElevatedButton.icon(onPressed: saveLocationNow, icon: const Icon(Icons.save_outlined), label: const Text('SAVE NOW'))),
              const SizedBox(width: 10),
              Expanded(child: OutlinedButton.icon(onPressed: openLocationHistory, icon: const Icon(Icons.history), label: const Text('HISTORY'), style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48), foregroundColor: const Color(0xFF9DE8D2), side: const BorderSide(color: Color(0xFF438F83)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))))),
            ]),
            const SizedBox(height: 10),
            Row(children: [const Icon(Icons.schedule, size: 15, color: Color(0xFF55D6B3)), const SizedBox(width: 6), Text('Lokasi disimpan secara automatik setiap 10 minit.', style: TextStyle(color: Colors.blueGrey.shade200, fontSize: 11))]),
          ]))),
          const SizedBox(height: 16),

          // SENSOR AND BATTERY
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: infoCard(
              icon: Icons.radar,
              title: 'OBSTACLE',
              value: obstacleDistance >= 900 ? '--' : '${obstacleDistance.toStringAsFixed(0)} cm',
              detail: obstacleStatus,
              accent: obstacleDistance <= 100 ? const Color(0xFFFF7777) : const Color(0xFF55D6B3),
            )),
            const SizedBox(width: 12),
            Expanded(child: infoCard(
              icon: isCharging ? Icons.battery_charging_full : Icons.battery_full,
              title: 'BATTERY',
              value: '$batteryPercentage%',
              detail: isCharging ? 'Charging' : 'Battery status',
              accent: const Color(0xFFFFC66D),
            )),
          ]),
          Align(alignment: Alignment.centerRight, child: TextButton.icon(
            onPressed: () { setState(() { isCharging = !isCharging; }); },
            icon: Icon(isCharging ? Icons.power : Icons.bolt, size: 17),
            label: Text(isCharging ? 'Charging indicator ON' : 'Charging indicator OFF'),
            style: TextButton.styleFrom(foregroundColor: Colors.orangeAccent),
          )),
          const SizedBox(height: 8),

          // SOS
          SizedBox(width: double.infinity, child: ElevatedButton.icon(
            onPressed: testEmergency,
            icon: const Icon(Icons.warning_amber_rounded),
            label: const Text('TEST EMERGENCY', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.6)),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFC83D49), foregroundColor: Colors.white, minimumSize: const Size(0, 58), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
          )),
          const SizedBox(height: 22),

          // EMERGENCY LOG
          sectionTitle('EMERGENCY LOG', subtitle: 'Rekod kecemasan yang diterima'),
          const SizedBox(height: 12),
          if (emergencyLogs.isEmpty)
            const Card(child: Padding(padding: EdgeInsets.all(18), child: Row(children: [Icon(Icons.shield_outlined, color: Color(0xFF55D6B3)), SizedBox(width: 10), Text('Tiada emergency.')])) )
          else
            ...emergencyLogs.map((log) => Card(child: ListTile(
              leading: const CircleAvatar(backgroundColor: Color(0xFF49343A), child: Icon(Icons.warning_amber, color: Color(0xFFFF8C8C))),
              title: Text(log, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('Emergency detected'),
            ))),
        ],
      ),
    );
  }

  Widget _coordinateRow(String label, double value) {
    return Row(children: [
      SizedBox(width: 90, child: Text(label, style: TextStyle(color: Colors.blueGrey.shade300, fontSize: 11, fontWeight: FontWeight.w700))),
      Expanded(child: Text(value.toStringAsFixed(6), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()]))),
    ]);
  }
}


// ============================================================
// LOCATION HISTORY PAGE
// ============================================================

class LocationHistoryPage
    extends StatefulWidget {

  const LocationHistoryPage({
    super.key,
  });

  @override
  State<LocationHistoryPage>
      createState() =>
          _LocationHistoryPageState();
}


class _LocationHistoryPageState
    extends State<LocationHistoryPage> {

  List<Map<String, dynamic>>
      locations = [];

  bool loading = true;


  @override
  void initState() {

    super.initState();

    loadLocations();
  }


  Future<void> loadLocations() async {

    final data =
        await DatabaseHelper
            .getLocations();


    if (!mounted) return;


    setState(() {

      locations = data;

      loading = false;
    });
  }


  // ==========================================================
  // TRACK BACK
  // ==========================================================

  Future<void> trackLocation(
    double latitude,
    double longitude,
  ) async {

    final url = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$latitude,$longitude',
    );


    if (await canLaunchUrl(url)) {

      await launchUrl(
        url,
        mode:
            LaunchMode.externalApplication,
      );

    } else {

      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(
        const SnackBar(
          content:
              Text(
            'Google Maps tak dapat dibuka',
          ),
        ),
      );
    }
  }


  // ==========================================================
  // BUILD
  // ==========================================================

  @override
  Widget build(
    BuildContext context,
  ) {

    return Scaffold(

      appBar: AppBar(

        title:
            const Text(
          'Location History',
        ),
      ),


      body: loading

          ? const Center(
              child:
                  CircularProgressIndicator(),
            )

          : locations.isEmpty

              ? const Center(
                  child:
                      Text(
                    'Belum ada location history.',
                  ),
                )

              : RefreshIndicator(

                  onRefresh:
                      loadLocations,

                  child: ListView.builder(

                    padding:
                        const EdgeInsets.all(12),

                    itemCount:
                        locations.length,

                    itemBuilder:
                        (context, index) {

                      final location =
                          locations[index];


                      final latitude =
                          double.tryParse(
                        location[
                          'latitude'
                        ].toString(),
                      ) ??
                      0;


                      final longitude =
                          double.tryParse(
                        location[
                          'longitude'
                        ].toString(),
                      ) ??
                      0;


                      final timestamp =
                          DateTime.tryParse(
                        location[
                          'timestamp'
                        ].toString(),
                      );


                      return Card(

                        child:
                            ListTile(

                          leading:
                              const CircleAvatar(

                            child:
                                Icon(
                              Icons.location_on,
                            ),
                          ),


                          title:
                              Text(
                            'Location #${locations.length - index}',
                          ),


                          subtitle:
                              Column(

                            crossAxisAlignment:
                                CrossAxisAlignment.start,

                            children: [

                              const SizedBox(
                                height: 5,
                              ),

                              Text(
                                'Latitude: '
                                '${latitude.toStringAsFixed(6)}',
                              ),

                              Text(
                                'Longitude: '
                                '${longitude.toStringAsFixed(6)}',
                              ),

                              Text(
                                'Tarikh & Masa: '
                                '${formatDateTime(timestamp)}',
                              ),
                            ],
                          ),


                          trailing:
                              IconButton(

                            icon:
                                const Icon(
                              Icons.map,
                            ),

                            tooltip:
                                'Track Back',

                            onPressed: () {

                              trackLocation(
                                latitude,
                                longitude,
                              );
                            },
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}


// ============================================================
// FORMAT DATE TIME
// ============================================================

String formatDateTime(
  DateTime? dateTime,
) {

  if (dateTime == null) {
    return '--';
  }


  final local =
      dateTime.toLocal();


  return
      '${local.day.toString().padLeft(2, '0')}/'
      '${local.month.toString().padLeft(2, '0')}/'
      '${local.year} '
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}:'
      '${local.second.toString().padLeft(2, '0')}';
}