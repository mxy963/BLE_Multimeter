// ignore_for_file: non_constant_identifier_names, avoid_print, noop_primitive_operations, deprecated_member_use, avoid_redundant_argument_values, avoid_dynamic_calls

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lottie/lottie.dart';
import 'package:permission_handler/permission_handler.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(const MultimeterApp());
}

class MultimeterApp extends StatelessWidget {
  const MultimeterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Akıllı BLE Multimetre',
      themeMode: ThemeMode.dark,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6C63FF),
          brightness: Brightness.dark,
          background: Colors.black, // Arka plan rengini siyah yap
        ),
        textTheme: GoogleFonts.unboundedTextTheme(
          Theme.of(context).textTheme,
        ),
      ),
      debugShowCheckedModeBanner: false,
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6C63FF),
          brightness: Brightness.dark,
          background: Colors.black, // Arka plan rengini siyah yap
        ),
        textTheme: GoogleFonts.unboundedTextTheme(
          Theme.of(context).textTheme,
        ),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  bool isScanning = false;
  BluetoothDevice? connectedDevice;
  StreamSubscription<List<ScanResult>>? scanSubscription;
  String statusMessage = '';
  Timer? updateTimer;
  late AnimationController _animationController;

  Map<String, dynamic> measurements = {
    'continuity': 0.0,
    'resistance': 0.0,
    'dc_voltage': {'high': 0.0, 'low': 0.0},
    'ac_voltage': 0.0,
    'current': 0.0,
    'lastUpdate': DateTime.now().millisecondsSinceEpoch,
  };

  Map<String, BluetoothCharacteristic> characteristics = {};

  final String SERVICE_UUID = "886c85df-1d55-4732-9bc9-3fe3be8e12ce";
  final Map<String, String> CHARACTERISTIC_UUIDS = {
    'continuity': "19b10001-e8f2-537e-4f6c-d104768a1214",
    'resistance': "c00123f9-6ca2-4813-9b7e-3b4f30c5b1d8",
    'dc_voltage': "b0f25e35-7d85-4d94-8344-9adab7fca38c",
    'ac_voltage': "16518f5e2-b3f7-49d3-905d-b2962a4e26cf",
    'current': "eb777f93-95f2-458f-9083-b045e0b32891",
  };

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    _initBluetooth();
    updateTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (connectedDevice != null) {
        requestUpdates();
      }
    });
  }

  Future<void> _initBluetooth() async {
    if (!(await FlutterBluePlus.isSupported)) {
      setState(() {
        statusMessage = 'Bu cihaz Bluetooth desteklemiyor';
      });
      return;
    }
    await requestPermissions();
  }

  Future<void> requestPermissions() async {
    final Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    bool allGranted = true;
    statuses.forEach((permission, status) {
      if (!status.isGranted) {
        allGranted = false;
        print('${permission.toString()} izni verilmedi: ${status.toString()}');
      }
    });

    if (!allGranted) {
      setState(() {
        statusMessage = 'Gerekli izinler verilmedi';
      });
      return;
    }

    if (!(await FlutterBluePlus.isOn)) {
      try {
        await FlutterBluePlus.turnOn();
      } catch (e) {
        setState(() {
          statusMessage = "Lütfen Bluetooth'u manuel olarak açın";
        });
      }
    }
  }

  // Periyodik veri güncelleme fonksiyonu
  Future<void> requestUpdates() async {
    try {
      for (final char in characteristics.values) {
        // Her karakteristikten veri oku
        final List<int> value = await char.read();
        final String type = characteristics.entries
            .firstWhere((entry) => entry.value == char)
            .key;
        updateMeasurement(type, value);
      }
    } catch (e) {
      print('Ölçümler güncellenirken hata: $e');
    }
  }

  Future<void> startScan() async {
    if (isScanning) return;

    if (await Permission.bluetoothScan.status.isDenied) {
      await requestPermissions();
      return;
    }

    setState(() {
      isScanning = true;
      statusMessage = 'Cihazlar taranıyor...';
    });

    try {
      await FlutterBluePlus.stopScan();

      print("ESP32 Multimetre için tarama başlatılıyor...");

      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 4),
        androidUsesFineLocation: false,
      );

      scanSubscription = FlutterBluePlus.scanResults.listen(
        (results) {
          print("${results.length} cihaz bulundu");
          for (final ScanResult result in results) {
            print("Cihaz bulundu: ${result.device.name}");
            if (result.device.name == "ESP32 Multimeter") {
              print("ESP32 Multimetre bulundu!");
              connectToDevice(result.device);
              FlutterBluePlus.stopScan();
              break;
            }
          }
        },
        onError: (error) {
          print("Tarama hatası: $error");
          setState(() {
            statusMessage = 'Tarama hatası: $error';
          });
        },
      );
    } catch (e) {
      print('Tarama sırasında hata: $e');
      setState(() {
        statusMessage = 'Tarama sırasında hata: $e';
      });
    } finally {
      await Future.delayed(const Duration(seconds: 4));
      await FlutterBluePlus.stopScan();
      setState(() {
        isScanning = false;
      });
    }
  }

  Future<void> connectToDevice(BluetoothDevice device) async {
    try {
      setState(() {
        statusMessage = 'Cihaza bağlanılıyor...';
      });

      await device.connect();
      setState(() {
        connectedDevice = device;
        statusMessage = 'ESP32 Multimetreye bağlı';
      });

      final List<BluetoothService> services = await device.discoverServices();
      for (final BluetoothService service in services) {
        if (service.uuid.toString() == SERVICE_UUID) {
          subscribeToCharacteristics(service);
        }
      }
    } catch (e) {
      print('Cihaza bağlanırken hata: $e');
      setState(() {
        statusMessage = 'Bağlantı hatası: $e';
      });
    }
  }

  void subscribeToCharacteristics(BluetoothService service) {
    for (final BluetoothCharacteristic characteristic
        in service.characteristics) {
      for (final entry in CHARACTERISTIC_UUIDS.entries) {
        if (characteristic.uuid.toString() == entry.value) {
          // Karakteristiği map'e kaydet
          characteristics[entry.key] = characteristic;

          // Notify'ı aktif et
          characteristic.setNotifyValue(true);
          characteristic.value.listen(
            (value) {
              updateMeasurement(entry.key, value);
              setState(() {
                measurements['lastUpdate'] =
                    DateTime.now().millisecondsSinceEpoch;
              });
            },
            onError: (error) => print('Karakteristik hatası: $error'),
          );
        }
      }
    }
  }

  void updateMeasurement(String type, List<int> value) {
    try {
      final String jsonString = String.fromCharCodes(value);
      final Map<String, dynamic> data =
          jsonDecode(jsonString) as Map<String, dynamic>;

      setState(() {
        if (type == 'dc_voltage') {
          measurements[type] = {
            'high': (data['value1'] as num).toDouble(),
            'low': (data['value2'] as num).toDouble(),
          };
        } else {
          measurements[type] = (data['value1'] as num).toDouble();
        }
        measurements['lastUpdate'] = DateTime.now().millisecondsSinceEpoch;
      });
    } catch (e) {
      print('Ölçüm güncellenirken hata: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.background,
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            floating: true,
            pinned: true,
            backgroundColor: colorScheme.background,
            title: Text(
              ' Akıllı BLE Multimetre',
              style: GoogleFonts.unbounded(
                fontWeight: FontWeight.bold,
                color: colorScheme.onBackground,
              ),
            ),
            actions: [
              AnimatedBuilder(
                animation: _animationController,
                builder: (context, child) {
                  return Transform.rotate(
                    angle:
                        isScanning ? _animationController.value * 2 * 3.14 : 0,
                    child: IconButton(
                      icon: Icon(
                        connectedDevice != null
                            ? Icons.bluetooth_connected
                            : Icons.bluetooth_disabled,
                        color: connectedDevice != null
                            ? colorScheme.primary
                            : colorScheme.error,
                      ),
                      onPressed: null,
                    ),
                  );
                },
              ),
            ],
          ),
          if (connectedDevice == null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(100.0),
                child: Column(
                  children: [
                    if (statusMessage.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 16.0),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceVariant,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            statusMessage,
                            style: GoogleFonts.unbounded(
                              color: colorScheme.onSurfaceVariant,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    const SizedBox(height: 36),
                    if (isScanning)
                      SizedBox(
                        height: 400,
                        width: 400,
                        child: Lottie.asset(
                          'assets/loader.json',
                          height: 360,
                          width: 360,
                        ),
                      )
                    else
                      FilledButton.tonalIcon(
                        icon: const Icon(Icons.search),
                        label: Text(
                          'Taramayı Başlat',
                          style: GoogleFonts.unbounded(),
                        ),
                        onPressed: startScan,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.all(20),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          if (connectedDevice != null)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 24),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  // Süreklilik Kartı - Tam Genişlik
                  _buildMeasurementCard(
                    'İletkenlik',
                    measurements['continuity'] == 1 ? 'Bağlı' : 'Bağlı Değil',
                    Icons.power,
                    measurements['continuity'] == 1 ? Colors.green : Colors.red,
                    isFullWidth: true,
                  ),
                  const SizedBox(height: 36),
                  // Direnç ve DC Voltaj aynı satırda
                  Row(
                    children: [
                      Expanded(
                        child: _buildMeasurementCard(
                          'Direnç',
                          '${measurements['resistance'].toStringAsFixed(2)} Ω',
                          Icons.track_changes,
                          const Color(0xFF6C63FF),
                        ),
                      ),
                      const SizedBox(width: 36),
                      Expanded(
                        child: _buildMeasurementCard(
                          'DC Voltaj',
                          'Y: ${(measurements['dc_voltage'] as Map)['high'].toStringAsFixed(2)}V\nA: ${(measurements['dc_voltage'] as Map)['low'].toStringAsFixed(2)}V',
                          Icons.bolt,
                          const Color.fromARGB(255, 255, 23, 185),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 36),
                  // AC Voltaj ve Akım aynı satırda
                  Row(
                    children: [
                      Expanded(
                        child: _buildMeasurementCard(
                          'AC Voltaj',
                          '${measurements['ac_voltage'].toStringAsFixed(2)}V',
                          Icons.electrical_services,
                          const Color(0xFF4ECDC4),
                        ),
                      ),
                      const SizedBox(width: 36),
                      Expanded(
                        child: _buildMeasurementCard(
                          'Akım',
                          '${measurements['current'].toStringAsFixed(3)}A',
                          Icons.waves,
                          const Color(0xFFFFBE0B),
                        ),
                      ),
                    ],
                  ),
                ]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMeasurementCard(
    String title,
    String value,
    IconData icon,
    Color color, {
    bool isFullWidth = false,
  }) {
    return Container(
      height: isFullWidth ? 200 : 180,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.1),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ColorFilter.mode(
            color.withOpacity(0.05),
            BlendMode.srcOver,
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(icon, color: color, size: isFullWidth ? 40 : 32),
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: GoogleFonts.unbounded(
                    fontSize: isFullWidth ? 16 : 14,
                    fontWeight: FontWeight.w500,
                    color: color.withOpacity(0.8),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  value,
                  style: GoogleFonts.unbounded(
                    fontSize: isFullWidth ? 20 : 16,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    updateTimer?.cancel();
    scanSubscription?.cancel();
    connectedDevice?.disconnect();
    super.dispose();
  }
}
