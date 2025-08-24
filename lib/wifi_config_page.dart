import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class WifiConfigPage extends StatefulWidget {
  const WifiConfigPage({super.key});
  @override
  WifiConfigPageState createState() => WifiConfigPageState();
}

class WifiConfigPageState extends State<WifiConfigPage> {
  final _ssidController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isConnecting = false;
  String _statusMessage = '';

  Future<void> _sendWifiConfig() async {
    if (_ssidController.text.isEmpty) {
      setState(() {
        _statusMessage = 'SSID tidak boleh kosong.';
      });
      return;
    }

    setState(() {
      _isConnecting = true;
      _statusMessage = 'Mengirim konfigurasi ke ESP32...';
    });

    try {
      const String esp32Ip = '192.168.4.1'; // Alamat IP default dari ESP32 Soft AP
      final url = Uri.http(esp32Ip, '/config');
      
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'ssid': _ssidController.text,
          'password': _passwordController.text,
        }),
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final responseBody = json.decode(response.body);
        if (responseBody['status'] == 'success') {
          setState(() {
            _statusMessage = 'Konfigurasi diterima! ESP32 akan restart. Silakan tutup halaman ini, hubungkan ponsel Anda ke jaringan WiFi yang sama, lalu gunakan fitur "Hubungkan ke ESP32" di halaman utama.';
          });
        } else {
          setState(() {
            _statusMessage = 'ESP32 menolak konfigurasi. Coba lagi.';
          });
        }
      } else {
        setState(() {
          _statusMessage = 'Gagal mengirim konfigurasi. Status code: ${response.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Terjadi error: $e. Pastikan Anda terhubung ke AP "ESP32_Config".';
      });
    } finally {
      setState(() {
        _isConnecting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Konfigurasi WiFi ESP32'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '1. Hubungkan ponsel Anda ke WiFi "ESP32_Config" (password: 12345678).\n2. Masukkan kredensial WiFi rumah Anda di bawah ini.',
              style: TextStyle(height: 1.5),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _ssidController,
              decoration: const InputDecoration(
                labelText: 'Nama WiFi (SSID)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Password WiFi',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _isConnecting ? null : _sendWifiConfig,
              child: _isConnecting ? const CircularProgressIndicator(color: Colors.white) : const Text('Kirim Konfigurasi'),
            ),
            const SizedBox(height: 20),
            if (_statusMessage.isNotEmpty)
              Text(
                _statusMessage,
                textAlign: TextAlign.center,
              ),
          ],
        ),
      ),
    );
  }
}