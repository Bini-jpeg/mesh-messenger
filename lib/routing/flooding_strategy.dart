// FILE: lib/routing/flooding_strategy.dart
import 'dart:collection';
import 'routing_strategy.dart';
import '../models/message.dart';
import '../network/peer_model.dart';

/// Flooding: forwards every new message to every connected peer except
/// the original sender.
///
/// Deduplication uses a bounded FIFO set (max 2000 entries).
/// Pre-seeding from storage (to survive restarts) is done by
/// [RoutingStrategy.seedSeen], called by TransportService on init.
class FloodingStrategy implements RoutingStrategy {
  static const int _maxSeen = 2000;
  final Set<String>   _seenIds   = {};
  // Problem 3 fix: Queue gives O(1) removeFirst() vs O(n) removeAt(0) on List.
  final Queue<String> _seenOrder = Queue();

  @override
  String get name => 'Flooding';

  @override
  bool isDestination(MeshMessage message, String myId) =>
      message.recipientId == myId;

  @override
  bool shouldForward(MeshMessage message, String myId) {
    if (isDestination(message, myId)) return false;
    if (message.ttl <= 0) return false;
    if (_seenIds.contains(message.id)) return false;
    _markSeen(message.id);
    return true;
  }

  @override
  List<String> getNextHops(MeshMessage message, List<Peer> knownPeers) {
    return knownPeers
        .where((p) => p.userId != message.senderId)
        .map((p) => p.endpointId)
        .toList();
  }

  @override
  void seedSeen(Iterable<String> ids) {
    for (final id in ids) {
      if (!_seenIds.contains(id)) _markSeen(id);
    }
  }

  @override
  bool hasSeen(String id) => _seenIds.contains(id);

  // ── Fix 12 ────────────────────────────────────────────────────────────────
  @override
  Iterable<String> getSeenIds() => List.unmodifiable(_seenIds);

  void _markSeen(String id) {
    if (_seenIds.length >= _maxSeen) {
      _seenIds.remove(_seenOrder.removeFirst()); // O(1)
    }
    _seenIds.add(id);
    _seenOrder.addLast(id);
  }
}
