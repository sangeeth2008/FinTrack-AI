import 'dart:async';
import 'package:flutter/services.dart';

class SharedIntentPayload {
  final String type; // image | text | pdf
  final String? path;
  final String? text;

  const SharedIntentPayload({
    required this.type,
    this.path,
    this.text,
  });

  factory SharedIntentPayload.fromMap(Map<dynamic, dynamic> map) {
    return SharedIntentPayload(
      type: (map['type'] as String?) ?? 'text',
      path: map['path'] as String?,
      text: map['text'] as String?,
    );
  }
}

class NativeSmsMessage {
  final String body;
  final String address;
  final DateTime date;

  const NativeSmsMessage({
    required this.body,
    required this.address,
    required this.date,
  });

  factory NativeSmsMessage.fromMap(Map<dynamic, dynamic> map) {
    final epochMs = (map['date'] as num?)?.toInt() ??
        DateTime.now().millisecondsSinceEpoch;
    return NativeSmsMessage(
      body: (map['body'] as String?) ?? '',
      address: (map['address'] as String?) ?? '',
      date: DateTime.fromMillisecondsSinceEpoch(epochMs),
    );
  }
}

class NativeBridgeService {
  static const MethodChannel _channel = MethodChannel(
    'com.sangeeth.fintrack/native_bridge',
  );

  final StreamController<SharedIntentPayload> _sharedController =
      StreamController<SharedIntentPayload>.broadcast();
  final StreamController<NativeSmsMessage> _smsController =
      StreamController<NativeSmsMessage>.broadcast();

  NativeBridgeService() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onSharedPayload' && call.arguments is Map) {
        final payload = SharedIntentPayload.fromMap(
          call.arguments as Map<dynamic, dynamic>,
        );
        _sharedController.add(payload);
      } else if (call.method == 'onIncomingSms' && call.arguments is Map) {
        final msg = NativeSmsMessage.fromMap(
          call.arguments as Map<dynamic, dynamic>,
        );
        _smsController.add(msg);
      }
    });
  }

  Stream<SharedIntentPayload> get sharedPayloadStream =>
      _sharedController.stream;

  Stream<NativeSmsMessage> get incomingSmsStream => _smsController.stream;

  Future<SharedIntentPayload?> consumeInitialSharedPayload() async {
    try {
      final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'getInitialSharedPayload',
      );
      if (raw == null) return null;
      return SharedIntentPayload.fromMap(raw);
    } catch (_) {
      return null;
    }
  }

  Future<void> setSecureScreen(bool enabled) async {
    try {
      await _channel.invokeMethod('setSecureScreen', {'enabled': enabled});
    } catch (_) {}
  }

  Future<bool> hasSmsPermission() async {
    try {
      return (await _channel.invokeMethod<bool>('hasSmsPermission')) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> requestSmsPermission() async {
    try {
      return (await _channel.invokeMethod<bool>('requestSmsPermission')) ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<List<NativeSmsMessage>> readRecentBankSms({
    int sinceEpochMs = 0,
    int limit = 80,
  }) async {
    try {
      final rawList = await _channel.invokeMethod<List<dynamic>>(
        'readRecentBankSms',
        {'sinceEpochMs': sinceEpochMs, 'limit': limit},
      );
      if (rawList == null) return const [];
      return rawList
          .whereType<Map<dynamic, dynamic>>()
          .map(NativeSmsMessage.fromMap)
          .where((m) => m.body.trim().isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  void dispose() {
    _sharedController.close();
    _smsController.close();
  }
}
