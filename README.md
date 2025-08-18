# esp32_monitor

A Flutter application for monitoring dummy sensor data from an ESP32 device via Bluetooth and WebSocket.

## Overview

This project consists of:
- **Flutter mobile app**: Connects to ESP32 via Bluetooth Classic, sends WiFi credentials, requests IP address, and receives real-time sensor data via WebSocket.
- **ESP32 firmware**: Receives WiFi credentials via Bluetooth, connects to WiFi, starts a WebSocket server, and sends dummy sensor data (location, temperature, emergency status).

### Main Features

- Scan and connect to ESP32 via Bluetooth.
- Send WiFi SSID and password to ESP32.
- Request ESP32 IP address.
- Remotely reset ESP32.
- Display ESP32 WiFi connection status.
- Show/hide password input for convenience.
- Display real-time sensor data from ESP32 via WebSocket.

### How It Works

1. **Bluetooth**:  
   - The app connects to ESP32 and sends WiFi credentials.
   - ESP32 connects to WiFi and replies with connection status and IP address.
2. **WebSocket**:  
   - The app connects to ESP32's WebSocket server using the received IP address.
   - ESP32 sends dummy sensor data periodically.

### ESP32 Dummy Data

- Latitude & Longitude (randomized ±100m)
- Environment temperature
- Body temperature
- Emergency status (random)
- Timestamp

## ESP32 Dummy Firmware

The ESP32 source code (dummy WiFi + Bluetooth + WebSocket) can be found in this repository:  
[https://github.com/syahrilTGR/hijack-iot/tree/main/dummy-wifi](https://github.com/syahrilTGR/hijack-iot/tree/main/dummy-wifi)

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Requirements

- Flutter SDK
- ESP32 board
- Android device (Bluetooth Classic support)
- Arduino IDE or PlatformIO (for ESP32)

##
