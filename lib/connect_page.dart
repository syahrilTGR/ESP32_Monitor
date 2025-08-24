import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:multicast_dns/multicast_dns.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import './channel_manager.dart';
import './monitor_page.dart';

// Kelas sederhana untuk menampung hasil scan
class DiscoveredDevice {
  final String name;
  final String ipAddress;
  DiscoveredDevice(this.name, this.ipAddress);
}

class ConnectPage extends StatefulWidget {
  const ConnectPage({super.key});

  @override
  State<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends State<ConnectPage> {
  final _log = Logger('ConnectPage');
  final _ipController = TextEditingController();
  bool _isConnecting = false;
  bool _isScanning = false;
  List<DiscoveredDevice> _discoveredDevices = [];

  @override
  void dispose() {
    _ipController.dispose();
    super.dispose();
  }

  Future<void> _scanForDevices() async {
    setState(() {
      _isScanning = true;
      _discoveredDevices = [];
    });

    final MDnsClient client = MDnsClient(
      rawDatagramSocketFactory: (dynamic host, int port,
          {bool? reuseAddress, bool? reusePort, int? ttl}) {
        return RawDatagramSocket.bind(host, port,
            reuseAddress: true, ttl: ttl!);
      },
    );

    try {
      await client.start();
      const String name = '_ws._tcp.local';

      await for (final PtrResourceRecord ptr in client
          .lookup<PtrResourceRecord>(ResourceRecordQuery.serverPointer(name))
          .timeout(const Duration(seconds: 5))) {
        await for (final SrvResourceRecord srv in client
            .lookup<SrvResourceRecord>(ResourceRecordQuery.service(ptr.domainName))) {
          await for (final IPAddressResourceRecord ip in client
              .lookup<IPAddressResourceRecord>(
                  ResourceRecordQuery.addressIPv4(srv.target))) {
            if (mounted) {
              setState(() {
                if (!_discoveredDevices
                    .any((d) => d.ipAddress == ip.address.address)) {
                  _discoveredDevices
                      .add(DiscoveredDevice(srv.target, ip.address.address));
                }
              });
            }
          }
        }
      }
    } on TimeoutException {
      _log.info('Scan finished after 5 seconds.');
    } catch (e, s) {
      _log.severe('Error during scan', e, s);
    } finally {
      client.stop();
      if (mounted) {
        setState(() {
          _isScanning = false;
        });
      }
    }
  }

  void _connect(String ip) {
    if (ChannelManager.channel != null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Sudah terhubung. Putuskan koneksi terlebih dahulu.')));
      return;
    }

    setState(() {
      _isConnecting = true;
    });

    final uri = Uri.parse('ws://$ip:81');
    try {
      ChannelManager.channel = WebSocketChannel.connect(uri);
      ChannelManager.broadcastStream = ChannelManager.channel!.stream.asBroadcastStream();
      ChannelManager.channel!.ready.then((_) {
        if (!mounted) return;
        // Use push instead of pushReplacement
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const MonitorPage()),
        ).then((_) => setState((){})); // Refresh UI when returning
      }).catchError((error) {
        if (!mounted) return;
        setState(() => _isConnecting = false);
        ChannelManager.channel = null;
        ChannelManager.broadcastStream = null;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal terhubung: $error')));
      });
    } catch (e) {
      setState(() => _isConnecting = false);
      ChannelManager.channel = null;
      ChannelManager.broadcastStream = null;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Format IP tidak valid: $e')));
    }
  }

  void _disconnect() {
    if (ChannelManager.channel != null) {
      ChannelManager.channel!.sink.close();
      ChannelManager.channel = null;
      ChannelManager.broadcastStream = null;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Koneksi terputus.')));
      setState(() {}); // To rebuild the UI and update button states
    }
  }

  void _openMonitorPage() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const MonitorPage()),
    ).then((_) => setState((){})); // Refresh UI when returning
  }

  @override
  Widget build(BuildContext context) {
    final bool isConnected = ChannelManager.channel != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Hubungkan ke ESP32'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            if (isConnected)
              Card(
                color: Colors.green.shade100,
                child: ListTile(
                  leading: const Icon(Icons.check_circle, color: Colors.green),
                  title: const Text('Terhubung'),
                  subtitle: const Text('Klik untuk membuka live monitor'),
                  onTap: _openMonitorPage,
                ),
              ),
            if (isConnected) const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: _isScanning
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 3))
                  : const Icon(Icons.search),
              label: _isScanning
                  ? const Text('Memindai...')
                  : const Text('Pindai Jaringan'),
              onPressed: isConnected || _isScanning ? null : _scanForDevices,
            ),
            const SizedBox(height: 20),
            if (_discoveredDevices.isNotEmpty)
              Expanded(
                child: ListView.builder(
                  itemCount: _discoveredDevices.length,
                  itemBuilder: (context, index) {
                    final device = _discoveredDevices[index];
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.lan_outlined),
                        title: Text(device.name.replaceAll('.local', '')),
                        subtitle: Text(device.ipAddress),
                        onTap: isConnected ? null : () => _connect(device.ipAddress),
                      ),
                    );
                  },
                ),
              )
            else if (!_isScanning && !isConnected)
              const Text('Tidak ada perangkat ditemukan. Coba pindai lagi.'),
            if (!isConnected) const Divider(height: 40),
            if (!isConnected)
              Text('Atau masukkan IP secara manual:',
                  style: Theme.of(context).textTheme.bodySmall),
            if (!isConnected) const SizedBox(height: 10),
            if (!isConnected)
              TextField(
                controller: _ipController,
                keyboardType: TextInputType.phone,
                enabled: !isConnected,
                decoration: const InputDecoration(
                    labelText: 'Alamat IP ESP32',
                    border: OutlineInputBorder()),
              ),
            if (!isConnected) const SizedBox(height: 10),
            if (!isConnected)
              ElevatedButton(
                onPressed: _isConnecting ? null : () => _connect(_ipController.text),
                child: _isConnecting
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Hubungkan Manual'),
              ),
            const Spacer(), // Pushes the disconnect button to the bottom
            ElevatedButton.icon(
              icon: const Icon(Icons.power_off),
              label: const Text('Putuskan Koneksi'),
              onPressed: isConnected ? _disconnect : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white
              ),
            ),
          ],
        ),
      ),
    );
  }
}
