import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ESP32 Monitor',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const BluetoothConnectPage(),
    );
  }
}

class BluetoothConnectPage extends StatefulWidget {
  const BluetoothConnectPage({super.key});

  @override
  _BluetoothConnectPageState createState() => _BluetoothConnectPageState();
}

class _BluetoothConnectPageState extends State<BluetoothConnectPage> with WidgetsBindingObserver {
  BluetoothConnection? connection;
  String status = "Belum terhubung";
  final TextEditingController ssidController = TextEditingController();
  final TextEditingController passController = TextEditingController();
  WebSocketChannel? wsChannel;
  bool showPassword = false; // <--- Tambahkan ini

  Map<String, dynamic>? espData;
  String wifiStatus = "Belum diketahui"; // <--- Tambahkan ini

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); // Tambahkan observer lifecycle
    _requestPermissions();
    FlutterBluetoothSerial.instance.state.then((state) {
      if (state == BluetoothState.STATE_OFF) {
        FlutterBluetoothSerial.instance.requestEnable();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this); // Hapus observer
    connection?.dispose();
    wsChannel?.sink.close();
    ssidController.dispose();
    passController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Jika aplikasi kembali ke foreground, cek dan reconnect WebSocket jika perlu
    if (state == AppLifecycleState.resumed) {
      if (espData != null && espData!.containsKey("ip")) {
        final ip = espData!["ip"];
        // Jika wsChannel sudah close, buat ulang
        if (wsChannel == null || wsChannel!.closeCode != null) {
          setState(() {
            wsChannel = WebSocketChannel.connect(Uri.parse('ws://$ip:81/'));
          });
        }
      }
    }
  }

  Future<void> _requestPermissions() async {
    await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();
  }

  Future<void> connectBT(BluetoothDevice device) async {
    setState(() {
      status = "Menghubungkan ke ${device.name}...";
      wsChannel = null;
      espData = null;
      wifiStatus = "Belum diketahui"; // Reset status WiFi
    });

    try {
      connection = await BluetoothConnection.toAddress(device.address);
      setState(() {
        status = "Terhubung ke ${device.name}";
      });

      connection!.input!.listen((Uint8List data) {
        String str = utf8.decode(data);
        str.split('\n').forEach((line) {
          line = line.trim();
          if (line.isEmpty) return;
          try {
            final decoded = json.decode(line);
            if (decoded is Map) {
              setState(() {
                espData = decoded as Map<String, dynamic>;
                // Update status WiFi jika ada info
                if (decoded.containsKey("wifi")) {
                  wifiStatus = decoded["wifi"] == "connected"
                      ? "ESP32 sudah terhubung ke WiFi"
                      : "ESP32 belum terhubung ke WiFi";
                }
              });
              if (decoded.containsKey("ip") && wsChannel == null) {
                final ip = decoded["ip"];
                setState(() {
                  wsChannel = WebSocketChannel.connect(Uri.parse('ws://$ip:81/'));
                });
              }
            }
          } catch (e) {
            print("Pesan non-JSON dari BT: $line");
          }
        });
      }, onDone: () {
        setState(() {
          status = "Koneksi terputus";
          connection = null;
          wsChannel = null;
          wifiStatus = "Belum diketahui";
        });
      });
    } catch (e) {
      setState(() {
        status = "Koneksi gagal: $e";
      });
    }
  }

  void sendBT(String cmd) {
    if (connection != null && connection!.isConnected) {
      connection!.output.add(utf8.encode("$cmd\n"));
      connection!.output.allSent.then((_) {
        print('Terkirim via BT: $cmd');
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Bluetooth tidak terhubung!")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("ESP32 Monitor")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text("Status: $status", textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text("Status WiFi ESP32: $wifiStatus", textAlign: TextAlign.center, style: const TextStyle(color: Colors.blue)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.bluetooth_searching),
              label: const Text("Cari & Hubungkan Perangkat"),
              onPressed: () async {
                final BluetoothDevice? selectedDevice =
                    await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const DiscoveryPage(),
                  ),
                );

                if (selectedDevice != null) {
                  connectBT(selectedDevice);
                }
              },
            ),
            const Divider(height: 32),
            TextField(
              controller: ssidController,
              decoration: const InputDecoration(
                labelText: "WiFi SSID",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: passController,
              decoration: InputDecoration(
                labelText: "WiFi Password",
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(showPassword ? Icons.visibility_off : Icons.visibility),
                  onPressed: () {
                    setState(() {
                      showPassword = !showPassword;
                    });
                  },
                ),
              ),
              obscureText: !showPassword,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: connection == null ? null : () {
                      String ssid = ssidController.text.trim();
                      String pass = passController.text.trim();
                      if (ssid.isEmpty || pass.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("SSID dan Password tidak boleh kosong")),
                        );
                        return;
                      }
                      sendBT("WIFI:$ssid,$pass");
                    },
                    child: const Text("Kirim WiFi"),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: connection == null ? null : () {
                      sendBT("GETIP");
                    },
                    child: const Text("Get IP"),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: connection == null ? null : () {
                      sendBT("RESET");
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                    child: const Text("Reset ESP32"),
                  ),
                ),
              ],
            ),
            const Divider(height: 32),
            const Text("Realtime Data:", style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Expanded(
              child: Card(
                elevation: 2,
                child: StreamBuilder(
                  stream: wsChannel?.stream,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting && wsChannel != null) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(child: Text("Error WebSocket: ${snapshot.error}"));
                    }
                    if (snapshot.hasData) {
                      try {
                        final data = json.decode(snapshot.data.toString()) as Map<String, dynamic>;
                        return ListView(
                          padding: const EdgeInsets.all(8.0),
                          children: [
                            ListTile(title: const Text("Latitude"), subtitle: Text("${data['lat']}")),
                            ListTile(title: const Text("Longitude"), subtitle: Text("${data['lon']}")),
                            ListTile(title: const Text("Temp. Lingkungan"), subtitle: Text("${data['temp_lingkungan']}°C")),
                            ListTile(title: const Text("Temp. Tubuh"), subtitle: Text("${data['temp_tubuh']}°C")),
                            ListTile(title: const Text("Waktu"), subtitle: Text("${data['time']}")),
                            ListTile(
                              title: const Text("Emergency"),
                              subtitle: Text(
                                "${data['emergency']}".toUpperCase(),
                                style: TextStyle(
                                    color: data['emergency'] ? Colors.red : Colors.green,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        );
                      } catch (e) {
                        return Center(child: Text("Data WebSocket tidak valid: ${snapshot.data}"));
                      }
                    }
                    return Center(
                      child: Text(
                        espData != null
                            ? "Data BT diterima. Menunggu koneksi WebSocket..."
                            : "Hubungkan ke perangkat ESP32 untuk memulai.",
                        textAlign: TextAlign.center,
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DiscoveryPage extends StatelessWidget {
  const DiscoveryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pilih Perangkat'),
      ),
      body: FutureBuilder<List<BluetoothDevice>>(
        future: FlutterBluetoothSerial.instance.getBondedDevices(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text("Error: ${snapshot.error}"));
          } else if (snapshot.hasData && snapshot.data!.isNotEmpty) {
            return ListView(
              children: snapshot.data!
                  .map(
                    (device) => ListTile(
                      title: Text(device.name ?? "Perangkat Tidak Dikenal"),
                      subtitle: Text(device.address),
                      leading: const Icon(Icons.bluetooth),
                      onTap: () {
                        Navigator.of(context).pop(device);
                      },
                    ),
                  )
                  .toList(),
            );
          } else {
            return const Center(
              child: Text("Tidak ada perangkat Bluetooth yang ter-pairing."),
            );
          }
        },
      ),
    );
  }
}