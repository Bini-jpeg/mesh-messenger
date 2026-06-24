// FILE: lib/core/app_config.dart

class AppConfig {
  static const String serviceId = 'com.thesis.mesh.v1';

  /// Default hop limit for new messages.
  static const int defaultTTL = 10;

  /// Maximum payload size in bytes (10 MB).
  static const int maxMessageSize = 10000000;

  /// Max characters per message to guarantee memory stability and avoid OOM crashes.
  static const int maxTextLength = 2048;

  /// How long to wait for an ACK before retrying (ms).
  static const int ackTimeoutMs = 10000;

  /// Maximum number of ACK retries before marking a message failed.
  static const int maxAckRetries = 3;

  /// How long a message may sit in the DTN outbox before being expired (hours).
  static const int outboxTtlHours = 72;

  /// RSA-2048 modulus = 256 bytes = 512 hex characters.
  static const int minPublicKeyHexLength = 512;

  // ── Fix 6: Outbox growth cap ─────────────────────────────────────────────
  /// Maximum number of entries in the DTN outbox.
  /// When this limit is reached, the oldest entry is evicted to make room.
  /// 200 entries × ~2 KB average encrypted message ≈ 400 KB, well within
  /// typical device storage budgets.
  static const int maxOutboxSize = 200;

  // ── Fix 3: Unknown-contact flooding cap ──────────────────────────────────
  /// Maximum number of auto-created "Unknown #N" contacts.
  /// Prevents a rogue node flooding the network with spoofed sender IDs from
  /// filling the local contacts list indefinitely.
  static const int maxUnknownContacts = 50;
}
