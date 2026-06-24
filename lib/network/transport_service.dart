// FILE: lib/network/transport_service.dart
import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:uuid/uuid.dart';
import '../core/app_config.dart';
import '../core/storage_service.dart';
import '../core/metrics_service.dart';
import '../models/contact.dart';
import '../main.dart';
import '../routing/routing_manager.dart';
import '../models/message.dart';
import 'peer_model.dart';

/// Manages the Nearby Connections transport layer, message forwarding,
/// ACK tracking, and a true Epidemic Delay-Tolerant Network (DTN) outbox.
class TransportService {
  Nearby? _nearby;
  final String _serviceId = AppConfig.serviceId;
  final RoutingManager _routingManager;

  final _peerController    = StreamController<PeerEvent>.broadcast();
  final _messageController = StreamController<MeshMessage>.broadcast();
  final _statusController  =
      StreamController<({String messageId, MessageStatus status})>.broadcast();

  // Peer tracking
  final List<Peer>          _knownPeers        = [];
  final Map<String, String> _endpointToShortId = {};
  final Map<String, String> _shortIdToEndpoint = {};
  final Map<String, String> _shortIdToFullKey  = {};
  final Map<String, String> _fullKeyToEndpoint = {};

  final Map<String, String> _pendingAuthDigits = {};

  String _myId      = '';
  String _myShortId = '';
  bool _isInitialized = false;

  // ACK tracking
  final Map<String, _PendingAck> _pendingAcks = {};

  bool _flushInProgress = false;

  final Set<String>    _completedIds    = {};
  final Queue<String>  _completedOrder  = Queue();
  static const int _maxCompleted = 500;

  final Set<String>   _processedAckIds   = {};
  final Queue<String> _processedAckOrder = Queue();
  static const int _maxProcessedAcks = 500;

  TransportService(this._routingManager);

  Stream<PeerEvent>   get peerStream    => _peerController.stream;
  Stream<MeshMessage> get messageStream => _messageController.stream;
  Stream<({String messageId, MessageStatus status})> get statusStream =>
      _statusController.stream;

  List<Peer> get knownPeers    => List.unmodifiable(_knownPeers);
  String     get myId          => _myId;
  bool       get isInitialized => _isInitialized;

  static String shortIdFromKey(String fullKeyHex) {
    final digest = sha256.convert(utf8.encode(fullKeyHex));
    return digest.toString().substring(0, 32);
  }

  Future<bool> initialize(String myUserId) async {
    if (_isInitialized) return true;
    _myId      = myUserId;
    _myShortId = shortIdFromKey(myUserId);

    if (!Platform.isAndroid) {
      _isInitialized = true;
      return true;
    }

    final persistedSeen = sl<StorageService>().getPersistedSeenIds();
    _routingManager.strategy.seedSeen(persistedSeen);

    await _sweepExpiredOutbox();

    _nearby = Nearby();
    
    try {
      await _nearby!.startAdvertising(
        _myShortId,
        Strategy.P2P_CLUSTER,
        serviceId: _serviceId,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult:    _onConnectionResult,
        onDisconnected:        _onDisconnected,
      );
    } on PlatformException catch (e) {
      if (e.code == '8001') {
        debugPrint('TransportService: Already advertising. Proceeding normally.');
      } else {
        rethrow;
      }
    }

    try {
      await _nearby!.startDiscovery(
        _myShortId,
        Strategy.P2P_CLUSTER,
        serviceId: _serviceId,
        onEndpointFound: _onEndpointFound,
        onEndpointLost:  _onEndpointLost,
      );
    } on PlatformException catch (e) {
      if (e.code == '8002') {
        debugPrint('TransportService: Already discovering. Proceeding normally.');
      } else {
        rethrow;
      }
    }

    _isInitialized = true;
    return true;
  }

  void _onEndpointFound(String endpointId, String endpointName, String serviceId) {
    _endpointToShortId[endpointId] = endpointName;
    _shortIdToEndpoint[endpointName] = endpointId;
    _peerController.add(PeerEvent.discovered(endpointId, endpointName));

    if (_myShortId.compareTo(endpointName) > 0) {
      debugPrint('TransportService: Initiating connection to $endpointId');
      _nearby!.requestConnection(
        _myShortId,
        endpointId,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult:    _onConnectionResult,
        onDisconnected:        _onDisconnected,
      ).catchError((dynamic e, StackTrace stack) {
        debugPrint('TransportService: Failed to request connection to $endpointId. Error: $e\n$stack');
      });
    } else {
      debugPrint('TransportService: Waiting for $endpointId to initiate connection.');
    }
  }

  void _onEndpointLost(String? endpointId) {
    if (endpointId == null) return;
    final shortId = _endpointToShortId.remove(endpointId);
    if (shortId != null) {
      _shortIdToEndpoint.remove(shortId);
      final fullKey = _shortIdToFullKey.remove(shortId);
      if (fullKey != null) _fullKeyToEndpoint.remove(fullKey);
    }
    _pendingAuthDigits.remove(endpointId);
    _knownPeers.removeWhere((p) => p.endpointId == endpointId);
    _peerController.add(PeerEvent.lost(endpointId));
  }

  void _onConnectionInitiated(String endpointId, ConnectionInfo info) {
    _pendingAuthDigits[endpointId] = info.authenticationToken;

    _nearby!.acceptConnection(
      endpointId,
      onPayLoadRecieved:       _onPayloadReceived,
      onPayloadTransferUpdate: _onPayloadTransferUpdate,
    );
  }

  void _onConnectionResult(String endpointId, Status status) {
    if (status == Status.CONNECTED) {
      _peerController.add(PeerEvent.connected(
          endpointId, _endpointToShortId[endpointId] ?? endpointId));
      _sendHandshake(endpointId);
    }
  }

  void _onDisconnected(String endpointId) {
    final shortId = _endpointToShortId.remove(endpointId);
    if (shortId != null) {
      _shortIdToEndpoint.remove(shortId);
      final fullKey = _shortIdToFullKey.remove(shortId);
      if (fullKey != null) _fullKeyToEndpoint.remove(fullKey);
    }
    _pendingAuthDigits.remove(endpointId);
    _knownPeers.removeWhere((p) => p.endpointId == endpointId);
    _peerController.add(PeerEvent.lost(endpointId));
  }

  void _onPayloadReceived(String endpointId, Payload payload) {
    final bytes = payload.bytes;
    if (bytes == null) return;

    if (bytes.length > AppConfig.maxMessageSize) {
      debugPrint('TransportService: oversized payload from $endpointId — dropped');
      return;
    }

    try {
      final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      final msg  = MeshMessage.fromJson(json);

      if (msg.payload.length > AppConfig.maxMessageSize) {
        debugPrint('TransportService: oversized message payload field — dropped');
        return;
      }
      _handleIncomingMessage(msg, endpointId);
    } catch (e, stack) {
      debugPrint('TransportService: CRITICAL payload parse error: $e\n$stack');
      rethrow;
    }
  }

  void _onPayloadTransferUpdate(String endpointId, PayloadTransferUpdate update) {}

  void _sendHandshake(String endpointId) {
    final handshake = MeshMessage(
      id:          const Uuid().v4(),
      senderId:    _myShortId,
      recipientId: '*',
      payload:     _myId,
      ttl:         1,
      timestamp:   DateTime.now(),
      type:        MessageType.handshake,
    );
    _sendToPeer(endpointId, handshake);
  }

  void _handleHandshake(MeshMessage msg, String fromEndpointId) {
    final fullKey = msg.payload;
    final shortId = msg.senderId;

    if (fullKey.isEmpty || fullKey.length < AppConfig.minPublicKeyHexLength) return;

    final expectedShortId = shortIdFromKey(fullKey);
    if (expectedShortId != shortId) return;

    _shortIdToFullKey[shortId]  = fullKey;
    _fullKeyToEndpoint[fullKey] = fromEndpointId;

    final authDigits = _pendingAuthDigits.remove(fromEndpointId) ?? '';

    _knownPeers.removeWhere((p) => p.endpointId == fromEndpointId);
    _knownPeers.add(Peer(
      endpointId:  fromEndpointId,
      userId:      fullKey,
      connectedAt: DateTime.now(),
      authDigits:  authDigits,
    ));
    _peerController.add(PeerEvent.connected(fromEndpointId, fullKey));

    _flushOutbox();
  }

  void _handleIncomingMessage(MeshMessage message, String fromEndpointId) {
    if (message.type == MessageType.handshake) {
      _handleHandshake(message, fromEndpointId);
      return;
    }

    if (message.type == MessageType.ack) {
      final alreadyProcessed = _processedAckIds.contains(message.id);
      if (!alreadyProcessed) {
        _markAckProcessed(message.id);

        final ackForId = message.ackForId;
        if (ackForId != null) {
          sl<StorageService>().removeFromOutbox(ackForId);
          final pending = _pendingAcks.remove(ackForId);
          if (pending != null) {
            pending.timer.cancel();
            _updateStatus(ackForId, MessageStatus.delivered);
          }
        }
      }
    }

    if (_routingManager.strategy.isDestination(message, _myId)) {
      if (message.type == MessageType.data) {

        sl<StorageService>().persistSeenId(message.id);

        if (sl<StorageService>().hasInboxMessage(message.id)) {
          _sendAckDirect(message, fromEndpointId);
          return;
        }

        final latencyMs = message.sentTime != null
            ? DateTime.now().difference(message.sentTime!).inMilliseconds.toDouble()
            : 0.0;

        sl<MetricsService>().logDelivery(
          messageId:       message.id,
          hopCount:        message.hopCount,
          ttlRemaining:    message.ttl,
          routingStrategy: _routingManager.strategy.name,
          latencyMs:       latencyMs,
          senderTs:        message.sentTime,
          receiverTs:      DateTime.now(),
          success:         true,
        );

        final localMsg = message.copyWith(localReceivedTime: DateTime.now());
        sl<StorageService>().saveToInbox(localMsg);
        
        _ensureContactExists(message.senderId);
        _messageController.add(localMsg);
        _sendAckDirect(message, fromEndpointId);

      } else if (message.type == MessageType.ack) {
        _handleAck(message);
      }

    } else if (_routingManager.strategy.shouldForward(message, _myId)) {
      if (message.ttl <= 0) return;

      sl<StorageService>().persistSeenId(message.id);
      sl<MetricsService>().logMessageForwarded(
        messageId:       message.id,
        routingStrategy: _routingManager.strategy.name,
        hopCount:        message.hopCount,
      );

      final forwarded = message.copyWith(
        ttl:      message.ttl - 1,
        hopCount: message.hopCount + 1,
      );

      sl<StorageService>().saveToOutbox(forwarded);
      _forwardToPeers(forwarded, excludeEndpointId: fromEndpointId);
    }
  }

  void _sendAckDirect(MeshMessage original, String directEndpointId) {
    final ack = MeshMessage(
      id:          const Uuid().v4(),
      senderId:    _myId,
      recipientId: original.senderId,
      payload:     '',
      ttl:         AppConfig.defaultTTL,
      hopCount:    0,
      timestamp:   DateTime.now(),
      sentTime:    DateTime.now(),
      type:        MessageType.ack,
      ackForId:    original.id,
    );
    _sendToPeer(directEndpointId, ack);
  }

  void _handleAck(MeshMessage ack) {
    final ackForId = ack.ackForId;
    if (ackForId == null) return;
    if (_completedIds.contains(ackForId)) return;

    sl<StorageService>().removeFromOutbox(ackForId);
    _markCompleted(ackForId);
    _updateStatus(ackForId, MessageStatus.delivered);
  }

  void _markCompleted(String messageId) {
    if (_completedIds.length >= _maxCompleted) {
      _completedIds.remove(_completedOrder.removeFirst());
    }
    _completedIds.add(messageId);
    _completedOrder.addLast(messageId);
  }

  void _markAckProcessed(String ackId) {
    if (_processedAckIds.length >= _maxProcessedAcks) {
      _processedAckIds.remove(_processedAckOrder.removeFirst());
    }
    _processedAckIds.add(ackId);
    _processedAckOrder.addLast(ackId);
  }

  void _updateStatus(String messageId, MessageStatus status) {
    sl<StorageService>().setMessageStatus(messageId, status);
    _statusController.add((messageId: messageId, status: status));
  }

  Future<void> _flushOutbox() async {
    if (_flushInProgress) return;
    _flushInProgress = true;
    try {
      await _sweepExpiredOutbox();

      final pending = sl<StorageService>().getPendingMessages();
      if (pending.isEmpty) return;

      for (final msg in pending) {
        if (msg.ttl <= 0) {
          await sl<StorageService>().removeFromOutbox(msg.id);
          _updateStatus(msg.id, MessageStatus.failed);
          continue;
        }

        final nextHops = _routingManager.strategy.getNextHops(msg, _knownPeers);
        if (nextHops.isEmpty) continue;

        bool sentAtLeastOnce = false;
        for (final endpointId in nextHops) {
          final ok = await _sendToPeer(endpointId, msg);
          if (ok) sentAtLeastOnce = true;
        }

        if (sentAtLeastOnce) {
          _updateStatus(msg.id, MessageStatus.sent);

          if (!_pendingAcks.containsKey(msg.id) && msg.type == MessageType.data) {
            _pendingAcks[msg.id] = _PendingAck(
              msg:     msg,
              retries: 0,
              timer:   _startAckTimer(msg.id),
            );
          }
        }
      }
    } finally {
      _flushInProgress = false;
    }
  }

  Timer _startAckTimer(String msgId) {
    return Timer(
      Duration(milliseconds: AppConfig.ackTimeoutMs),
      () => _handleAckTimeout(msgId),
    );
  }

  void _handleAckTimeout(String msgId) {
    final pending = _pendingAcks[msgId];
    if (pending == null) return;

    if (pending.retries >= AppConfig.maxAckRetries) {
      sl<MetricsService>().logDelivery(
        messageId:       msgId,
        hopCount:        pending.msg.hopCount,
        ttlRemaining:    pending.msg.ttl,
        routingStrategy: _routingManager.strategy.name,
        latencyMs:       0.0,
        success:         false,
      );
      _pendingAcks.remove(msgId);
      _updateStatus(msgId, MessageStatus.failed);
      return;
    }

    final retried = pending.msg.copyWith(sentTime: DateTime.now());
    _sendRaw(retried);
    _pendingAcks[msgId] = _PendingAck(
      msg:     pending.msg,
      retries: pending.retries + 1,
      timer:   _startAckTimer(msgId),
    );
  }

  Future<void> sendMessage(MeshMessage message) async {
    if (message.recipientId == _myId) return;

    sl<StorageService>().persistSeenId(message.id);
    _routingManager.strategy.seedSeen([message.id]);

    await sl<StorageService>().saveToOutbox(message);

    final nextHops = _routingManager.strategy.getNextHops(message, _knownPeers);

    bool sentAtLeastOnce = false;
    for (final endpointId in nextHops) {
      final ok = await _sendToPeer(endpointId, message);
      if (ok) sentAtLeastOnce = true;
    }

    if (sentAtLeastOnce) {
      sl<MetricsService>().logMessageSent(
        messageId:       message.id,
        routingStrategy: _routingManager.strategy.name,
      );
      _updateStatus(message.id, MessageStatus.sent);

      if (message.type == MessageType.data) {
        _pendingAcks[message.id] = _PendingAck(
          msg:     message,
          retries: 0,
          timer:   _startAckTimer(message.id),
        );
      }
    }
  }

  void _sendRaw(MeshMessage message) {
    _forwardToPeers(message);
  }

  void _forwardToPeers(MeshMessage message, {String? excludeEndpointId}) {
    final nextHops = _routingManager.strategy.getNextHops(message, _knownPeers);
    for (final endpointId in nextHops) {
      if (endpointId == excludeEndpointId) continue;
      _sendToPeer(endpointId, message);
    }
  }

  Future<bool> _sendToPeer(String endpointId, MeshMessage message) async {
    if (_nearby == null) return false;
    try {
      final bytes = Uint8List.fromList(utf8.encode(jsonEncode(message.toJson())));
      await _nearby!.sendBytesPayload(endpointId, bytes);
      return true;
    } catch (e, stack) {
      debugPrint('TransportService: CRITICAL error sending to $endpointId: $e\n$stack');
      _nearby!.disconnectFromEndpoint(endpointId);
      _onDisconnected(endpointId);
      return false;
    }
  }

  void _ensureContactExists(String senderId) {
    if (senderId.isEmpty || senderId == _myId) return;
    final storage = sl<StorageService>();
    if (storage.getContact(senderId) != null) return;

    final allContacts  = storage.getAllContacts();
    final unknownCount = allContacts
        .where((c) => c.name.startsWith('Unknown #'))
        .length;

    if (unknownCount >= AppConfig.maxUnknownContacts) {
      debugPrint('TransportService: unknown-contact cap reached '
          '(${AppConfig.maxUnknownContacts}), skipping auto-create for $senderId');
      return;
    }

    storage.saveContact(Contact(
      id:        senderId,
      name:      'Unknown #${unknownCount + 1}',
      createdAt: DateTime.now(),
    ));
  }

  Future<void> _sweepExpiredOutbox() async {
    final expiredIds = await sl<StorageService>()
        .expireOutboxMessages(AppConfig.outboxTtlHours);

    for (final id in expiredIds) {
      sl<MetricsService>().logDelivery(
        messageId:       id,
        hopCount:        0,
        ttlRemaining:    0,
        routingStrategy: _routingManager.strategy.name,
        latencyMs:       0.0,
        success:         false,
      );
      _updateStatus(id, MessageStatus.failed);
    }
  }

  /// Completely stops and cleans up network state.
  Future<void> stopAll() async {
    if (_nearby != null) {
      await _nearby!.stopAllEndpoints();
      await _nearby!.stopAdvertising();
      await _nearby!.stopDiscovery();
    }
    _knownPeers.clear();
    _endpointToShortId.clear();
    _shortIdToEndpoint.clear();
    _shortIdToFullKey.clear();
    _fullKeyToEndpoint.clear();
    _pendingAuthDigits.clear();
    _peerController.add(PeerEvent.lost('*')); // Broadcast mass disconnect
    _isInitialized = false;
  }

  /// Forces a clean restart of the Android Nearby Connections APIs.
  Future<bool> restartNode() async {
    debugPrint('TransportService: Manual network restart triggered.');
    await stopAll();
    // Allow Android's Bluetooth/WiFi Direct hardware stack a moment to clear cached states
    await Future.delayed(const Duration(milliseconds: 1000));
    return await initialize(_myId);
  }

  void dispose() {
    stopAll();
    for (final e in _pendingAcks.values) {
      e.timer.cancel();
    }
    _pendingAcks.clear();
    _peerController.close();
    _messageController.close();
    _statusController.close();
  }
}

class _PendingAck {
  final MeshMessage msg;
  final int retries;
  final Timer timer;
  const _PendingAck({required this.msg, required this.retries, required this.timer});
}
