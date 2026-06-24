// FILE: lib/routing/gossip_strategy.dart
import 'dart:collection';
import 'dart:math';
import 'routing_strategy.dart';
import '../models/message.dart';
import '../network/peer_model.dart';

/// Gossip: forwards each new message to a random subset (fanout) of peers,
/// excluding the original sender.
class GossipStrategy implements RoutingStrategy {
  static const int _maxSeen = 2000;
  final Set<String>   _seenIds   = {};
  // Problem 3 fix: Queue gives O(1) removeFirst() vs O(n) removeAt(0) on List.
  final Queue<String> _seenOrder = Queue();
  final Random _rng = Random();
  final int _fanout;

  GossipStrategy({int fanout = 3}) : _fanout = fanout;

  @override
  String get name => 'Gossip (fanout: $_fanout)';

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
    final candidates = knownPeers
        .where((p) => p.userId != message.senderId)
        .toList();

    if (candidates.length <= _fanout) {
      return candidates.map((p) => p.endpointId).toList();
    }
    candidates.shuffle(_rng);
    return candidates.take(_fanout).map((p) => p.endpointId).toList();
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
