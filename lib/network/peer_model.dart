// FILE: lib/network/peer_model.dart

/// Represents a currently-connected (or recently discovered) nearby peer.
///
/// [endpointId] is the Nearby Connections opaque transport handle.
/// [userId]     is the peer's full RSA public key hex — their identity.
/// [name]       equals [userId] since we advertise the full key as the name.
///
/// Fix 4 — [authDigits]:
/// The 4-digit authentication token provided by the Nearby Connections API
/// (ConnectionInfo.authenticationDigits). Both sides of a connection see the
/// same token, so a user can verbally or visually compare digits with a peer
/// to verify no man-in-the-middle substituted the handshake public key.
/// The field is stored here so a future "Verify contact" UI can surface it
/// without blocking the auto-accept flow required for mesh relay operation.
class Peer {
  final String endpointId;
  final String userId; // full RSA modulus hex — the peer's identity
  final DateTime connectedAt;

  /// Fix 4: Nearby Connections authentication token (4 digits).
  /// Non-null once a connection is established. May be empty string on
  /// older API levels that do not expose this value.
  final String authDigits;

  Peer({
    required this.endpointId,
    required this.userId,
    required this.connectedAt,
    this.authDigits = '',
  });

  /// Visual label: first 16 chars of userId + ellipsis.
  String get shortLabel =>
      userId.length > 16 ? '${userId.substring(0, 16)}…' : userId;
}

enum PeerEventType { discovered, connected, lost }

class PeerEvent {
  final PeerEventType type;
  final String endpointId;
  final String? userId;

  const PeerEvent(this.type, this.endpointId, this.userId);

  factory PeerEvent.discovered(String endpointId, String userId) =>
      PeerEvent(PeerEventType.discovered, endpointId, userId);

  factory PeerEvent.connected(String endpointId, String userId) =>
      PeerEvent(PeerEventType.connected, endpointId, userId);

  factory PeerEvent.lost(String endpointId) =>
      PeerEvent(PeerEventType.lost, endpointId, null);
}
