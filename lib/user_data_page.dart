import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import './channel_manager.dart';

class UserDataPage extends StatefulWidget {
  const UserDataPage({super.key});

  @override
  State<UserDataPage> createState() => _UserDataPageState();
}

class _UserDataPageState extends State<UserDataPage> {
  final _log = Logger('UserDataPage');
  final _ageController = TextEditingController();
  String _selectedGender = 'male';
  bool _hijabStatus = false;
  StreamSubscription? _streamSubscription;
  bool _initialDataLoaded = false;
  WebSocketChannel? _channel;
  Stream<dynamic>? _broadcastStream;

  @override
  void initState() {
    super.initState();
    _channel = ChannelManager.channel;
    _broadcastStream = ChannelManager.broadcastStream;

    if (_channel == null || _broadcastStream == null) {
      _log.severe('UserDataPage entered without a valid WebSocket channel or stream!');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if(mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Koneksi tidak ditemukan.")));
          Navigator.of(context).pop();
        }
      });
      return;
    }

    _streamSubscription = _broadcastStream!.listen((data) {
      if (!mounted || _initialDataLoaded) return;

      try {
        final decoded = json.decode(data.toString()) as Map<String, dynamic>;
        if (decoded.containsKey('age')) {
          setState(() {
            _ageController.text = decoded['age'].toString();
            
            final receivedGender = decoded['gender'];
            if (receivedGender == 'male' || receivedGender == 'female') {
              _selectedGender = receivedGender;
            } else {
              _selectedGender = 'male';
            }

            _hijabStatus = decoded['hijab'] ?? false;
            _initialDataLoaded = true;
          });
        }
      } catch (e, s) {
        _log.severe('Error parsing initial user data', e, s);
      }
    });
  }

  @override
  void dispose() {
    _ageController.dispose();
    _streamSubscription?.cancel();
    super.dispose();
  }

  void _sendUserData() {
    if (_channel == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Tidak ada koneksi.")),
      );
      return;
    }

    final age = _ageController.text;
    final gender = _selectedGender;
    final hijab = _hijabStatus;

    final command = {
      "command": "update_user",
      "age": int.tryParse(age) ?? 0,
      "gender": gender,
      "hijab": hijab,
    };

    _channel!.sink.add(json.encode(command));

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Data pengguna berhasil dikirim!")),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Set User Data"),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _ageController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: "Age",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _selectedGender,
              decoration: const InputDecoration(
                labelText: "Gender",
                border: OutlineInputBorder(),
              ),
              items: ['male', 'female'].map((String value) {
                return DropdownMenuItem<String>(
                  value: value,
                  child: Text(value),
                );
              }).toList(),
              onChanged: (String? newValue) {
                setState(() {
                  _selectedGender = newValue!;
                });
              },
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Checkbox(
                  value: _hijabStatus,
                  onChanged: (bool? newValue) {
                    setState(() {
                      _hijabStatus = newValue!;
                    });
                  },
                ),
                const Text("Menggunakan Hijab"),
              ],
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _sendUserData,
              child: const Text("Update User Data"),
            ),
            const SizedBox(height: 32),
            if (!_initialDataLoaded)
              const Center(child: CircularProgressIndicator()),
            const Text(
              "Catatan: Data akan tersimpan di ESP32 dan akan dimuat kembali saat aplikasi terhubung.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}