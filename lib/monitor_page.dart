import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:logging/logging.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_map_compass/flutter_map_compass.dart'; // Added this line
import 'package:dio/dio.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:http_cache_file_store/http_cache_file_store.dart';
import 'package:path_provider/path_provider.dart';
import './channel_manager.dart';
import './user_data_page.dart';

class MonitorPage extends StatefulWidget {
  const MonitorPage({super.key});

  @override
  State<MonitorPage> createState() => _MonitorPageState();
}

class _MonitorPageState extends State<MonitorPage> {
  final _log = Logger('MonitorPage');
  final MapController _mapController = MapController();
  Stream<dynamic>? _broadcastStream;
  LatLng _currentPosition = const LatLng(-7.9462, 112.6154); // Initial position
  String _tempLingkungan = "--";
  String _tempTubuh = "--";
  bool _isEmergency = false;
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _streamSubscription;

  late Dio _dio;
  late CacheStore _cacheStore;
  Future<void>? _initCacheFuture;

  @override
  void initState() {
    super.initState();
    _initCacheFuture = _initCache();
    _channel = ChannelManager.channel;
    _broadcastStream = ChannelManager.broadcastStream;
    if (_channel == null || _broadcastStream == null) {
      _log.severe('MonitorPage entered without a valid WebSocket channel or stream!');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text("Koneksi terputus, silakan sambungkan ulang.")));
          Navigator.of(context).pop();
        }
      });
    } else {
      _streamSubscription = _broadcastStream!.listen((data) {
        _log.info("Received data: $data");
        try {
          final decodedData = json.decode(data.toString()) as Map<String, dynamic>;
          if (mounted) {
            setState(() {
              final lat = decodedData['lat'] as double?;
              final lon = decodedData['lon'] as double?;
              if (lat != null && lon != null) {
                _currentPosition = LatLng(lat, lon);
              }
              _tempLingkungan =
                  decodedData['temp_lingkungan']?.toString() ?? _tempLingkungan;
              _tempTubuh = decodedData['temp_tubuh']?.toString() ?? _tempTubuh;
              _isEmergency = decodedData['emergency'] ?? _isEmergency;
            });
          }
        } catch (e, s) {
          _log.warning('Error parsing snapshot data', e, s);
        }
      }, onError: (error) {
        _log.severe('Error on WebSocket stream', error);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("Terjadi error: $error")));
          Navigator.of(context).pop();
        }
      }, onDone: () {
        _log.info('WebSocket stream closed');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Koneksi ditutup.")));
          Navigator.of(context).pop();
        }
      });
    }
  }

  Future<void> _initCache() async {
    final dir = await getTemporaryDirectory();
    _cacheStore = FileCacheStore(dir.path);
    _dio = Dio();
    _dio.interceptors.add(DioCacheInterceptor(options: CacheOptions(store: _cacheStore)));
  }

  @override
  void dispose() {
    _streamSubscription?.cancel();
    _mapController.dispose();
    _cacheStore.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_channel == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Error')),
        body: const Center(
          child: Text(
              'Koneksi tidak ditemukan. Silakan kembali dan hubungkan ulang.'),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Monitor'),
        actions: [
          IconButton(
            icon: const Icon(Icons.manage_accounts),
            tooltip: 'Ubah Data Pengguna',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const UserDataPage(),
                ),
              );
            },
          ),
        ],
      ),
      body: FutureBuilder<void>(
        future: _initCacheFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            return Column(
              children: [
                Expanded(
                  child: _buildMap(),
                ),
                _buildDataPanel(),
              ],
            );
          }
          return const Center(child: CircularProgressIndicator());
        },
      ),
    );
  }

  Widget _buildMap() {
    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _currentPosition,
            initialZoom: 17.0,
          ),
          children: [
            TileLayer(
              urlTemplate: "https://tile.opentopomap.org/{z}/{x}/{y}.png",
              userAgentPackageName: 'com.example.esp32_monitor',
              tileProvider: CustomTileProvider(dio: _dio),
            ),
            MarkerLayer(
              markers: [
                Marker(
                  width: 80.0,
                  height: 80.0,
                  point: _currentPosition,
                  rotate: false, // Added this line
                  child: const Icon(Icons.location_on, color: Colors.red, size: 40.0),
                ),
              ],
            ),
            MapCompass.cupertino(
              hideIfRotatedNorth: true,
            ),
          ],
        ),
        Positioned(
          right: 16.0,
          bottom: 16.0,
          child: FloatingActionButton(
            onPressed: () {
              _mapController.move(_currentPosition, 17.0);
            },
            tooltip: 'Pusatkan Peta',
            child: const Icon(Icons.my_location),
          ),
        ),
        if (_isEmergency)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 40,
              color: Colors.red,
              child: const Center(
                child: Text(
                  'EMERGENCY',
                  style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildDataPanel() {
    return Container(
      color: Colors.white,
      padding: EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 8.0 + MediaQuery.of(context).padding.bottom),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildInfoCard('Suhu Lingkungan', '$_tempLingkungan °C'),
          _buildInfoCard('Suhu Tubuh', '$_tempTubuh °C'),
        ],
      ),
    );
  }

  Widget _buildInfoCard(String title, String value) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: [
            Text(title, style: const TextStyle(color: Colors.grey, fontSize: 14)),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

class CustomTileProvider extends TileProvider {
  final Dio dio;

  CustomTileProvider({required this.dio});

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    final url = getTileUrl(coordinates, options);
    return NetworkImage(url, headers: headers);
  }
}