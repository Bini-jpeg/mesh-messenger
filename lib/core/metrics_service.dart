// FILE: lib/core/metrics_service.dart
import 'package:hive_flutter/hive_flutter.dart';

/// Records mesh network events for thesis data collection.
///
/// Three event types:
///   'sent'      — a message was handed to the network by this device
///   'forwarded' — this device relayed a message for someone else
///   'delivery'  — a message reached its destination (success or failure)
///
/// All CSV columns are always written for every row type, with sensible
/// null values (0 / 'n/a' / false) so the export is always well-formed.
///
/// ── Clock-skew warning (Problem 4) ──────────────────────────────────────────
/// The 'LatencyMs' column is derived from two timestamps on DIFFERENT devices:
///   SenderTs   — stamped by the sender when the message was created
///   ReceiverTs — stamped by the recipient when the message was received
/// Android clocks without NTP synchronisation can differ by several seconds.
/// Use 'SenderTs' and 'ReceiverTs' directly for post-processing: compute the
/// clock delta between devices using a known-simultaneous reference event
/// (e.g. a calibration message sent and received at t=0), then subtract that
/// delta from all LatencyMs values in the session.
class MetricsService {
  late Box _logBox;

  Future<void> init() async {
    _logBox = await Hive.openBox('metrics_log');
  }

  Future<void> logMessageSent({
    required String messageId,
    required String routingStrategy,
  }) async {
    await _logBox.add({
      'timestamp':    DateTime.now().toIso8601String(),
      'type':         'sent',
      'msg_id':       messageId,
      'hops':         0,
      'ttl_remaining': 0,
      'strategy':     routingStrategy,
      'latency_ms':   0.0,
      'success':      true,
    });
  }

  Future<void> logMessageForwarded({
    required String messageId,
    required String routingStrategy,
    required int hopCount,
  }) async {
    await _logBox.add({
      'timestamp':    DateTime.now().toIso8601String(),
      'type':         'forwarded',
      'msg_id':       messageId,
      'hops':         hopCount,
      'ttl_remaining': 0,
      'strategy':     routingStrategy,
      'latency_ms':   0.0,
      'success':      true,
    });
  }

  Future<void> logDelivery({
    required String messageId,
    required int hopCount,
    required int ttlRemaining,
    required String routingStrategy,
    required double latencyMs,
    required bool success,
    DateTime? senderTs,   // Problem 4: raw sender timestamp for clock-skew correction
    DateTime? receiverTs, // Problem 4: raw receiver timestamp for clock-skew correction
  }) async {
    await _logBox.add({
      'timestamp':    DateTime.now().toIso8601String(),
      'type':         'delivery',
      'msg_id':       messageId,
      'hops':         hopCount,
      'ttl_remaining': ttlRemaining,
      'strategy':     routingStrategy,
      'latency_ms':   latencyMs,
      'success':      success,
      'sender_ts':    senderTs?.toIso8601String() ?? '',
      'receiver_ts':  receiverTs?.toIso8601String() ?? '',
    });
  }

  /// Exports all log entries as a CSV string.
  /// Every row has the same columns regardless of event type.
  String exportToCSV() {
    final csv = StringBuffer(
        'Timestamp,Type,MsgID,Hops,TTLRemaining,Strategy,LatencyMs,Success,SenderTs,ReceiverTs\n');
    for (final raw in _logBox.values) {
      final e = Map<String, dynamic>.from(raw as Map);
      csv.writeln(
        '"${e['timestamp']}",'
        '${e['type']},'
        '${e['msg_id']},'
        '${e['hops'] ?? 0},'
        '${e['ttl_remaining'] ?? 0},'
        '${e['strategy'] ?? 'unknown'},'
        '${(e['latency_ms'] as num?)?.toStringAsFixed(2) ?? '0.00'},'
        '${e['success'] ?? false},'
        '"${e['sender_ts'] ?? ''}",'
        '"${e['receiver_ts'] ?? ''}"',
      );
    }
    return csv.toString();
  }

  Future<void> clearLogs() async => _logBox.clear();

  int get totalLogEntries => _logBox.length;

  Map<String, dynamic> getStats() {
    int delivered  = 0;
    int failed     = 0;
    int forwarded  = 0;
    int sent       = 0;
    double totalLatency = 0;

    for (final raw in _logBox.values) {
      final e    = Map<String, dynamic>.from(raw as Map);
      final type = e['type'] as String? ?? '';
      switch (type) {
        case 'delivery':
          if (e['success'] == true) {
            delivered++;
            totalLatency +=
                (e['latency_ms'] as num?)?.toDouble() ?? 0.0;
          } else {
            failed++;
          }
          break;
        case 'forwarded':
          forwarded++;
          break;
        case 'sent':
          sent++;
          break;
      }
    }

    return {
      'total_sent':      sent,
      'total_delivered': delivered,
      'total_failed':    failed,
      'total_forwarded': forwarded,
      'avg_latency_ms':
          delivered > 0 ? totalLatency / delivered : 0.0,
      'total_log_entries': _logBox.length,
    };
  }
}
