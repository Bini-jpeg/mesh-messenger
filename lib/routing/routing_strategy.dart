// FILE: lib/routing/routing_strategy.dart
import '../models/message.dart';
import '../network/peer_model.dart';

abstract class RoutingStrategy {
  /// True if [myId] is the intended recipient of [message].
  bool isDestination(MeshMessage message, String myId);

  /// True if this node should forward [message] to other peers.
  /// Implementations must deduplicate by message ID to prevent loops.
  bool shouldForward(MeshMessage message, String myId);

  /// Returns the list of endpoint IDs to send [message] to next.
  List<String> getNextHops(MeshMessage message, List<Peer> knownPeers);

  /// Pre-populates the seen-message set from persistent storage so that
  /// messages already processed before an app restart are not re-forwarded.
  void seedSeen(Iterable<String> ids);

  /// Returns true if this message ID has already been processed.
  bool hasSeen(String id);

  // ── Fix 12: strategy hot-swap seen-set leakage ────────────────────────────
  /// Returns a snapshot of all message IDs currently in the in-memory
  /// seen set. Used by [RoutingManager.setStrategy] to seed the replacement
  /// strategy with the full union of persisted + in-memory IDs, preventing a
  /// "flood spike" where a freshly-loaded strategy re-forwards messages that
  /// the previous strategy had already processed but not yet persisted.
  Iterable<String> getSeenIds();

  /// Human-readable strategy name used in metrics and the debug UI.
  String get name;
}
