// FILE: lib/core/storage_service.dart
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/message.dart';
import '../models/contact.dart';
import 'app_config.dart';

String _hiveKey(String value) {
  if (value.length <= 64) return value;
  final digest = sha256.convert(utf8.encode(value));
  return digest.toString();
}

class StorageService {
  late Box _sentBox;       
  late Box _inboxBox;      
  late Box _contactsBox;
  late Box _unreadBox;
  late Box _statusBox;     
  late Box _outboxBox;     
  late Box _seenBox;       

  Future<void> init() async {
    _outboxBox   = await Hive.openBox('outbox');
    _inboxBox    = await Hive.openBox('inbox');
    _sentBox     = await Hive.openBox('sent');
    _contactsBox = await Hive.openBox('contacts');
    _unreadBox   = await Hive.openBox('unread');
    _statusBox   = await Hive.openBox('msg_status');
    _seenBox     = await Hive.openBox('seen_ids');
  }

  // ── Outbox ─────────────────────────────────────────────────────────────────

  Future<void> saveToOutbox(MeshMessage message) async {
    if (_outboxBox.length >= AppConfig.maxOutboxSize) {
      final oldestKey = _outboxBox.keys.first;
      await _outboxBox.delete(oldestKey);
      debugPrint(
          'StorageService: outbox at capacity (${AppConfig.maxOutboxSize}), '
          'evicted oldest entry ($oldestKey)');
    }

    final entry = message.toJson();
    entry['outbox_created_at'] = DateTime.now().toIso8601String();
    await _outboxBox.put(message.id, entry);
  }

  List<MeshMessage> getPendingMessages() {
    return _outboxBox.values
        .map((e) => MeshMessage.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<void> removeFromOutbox(String messageId) async {
    await _outboxBox.delete(messageId);
  }

  Future<void> clearOutbox() async => _outboxBox.clear();

  Future<List<String>> expireOutboxMessages(int maxAgeHours) async {
    final cutoff  = DateTime.now().subtract(Duration(hours: maxAgeHours));
    final expired = <String>[];

    for (final key in _outboxBox.keys.toList()) {
      final raw = _outboxBox.get(key);
      if (raw == null) continue;
      final entry = Map<String, dynamic>.from(raw as Map);
      final createdRaw = entry['outbox_created_at'] as String?;

      final createdAt = createdRaw != null
          ? DateTime.tryParse(createdRaw) ?? cutoff.subtract(const Duration(seconds: 1))
          : cutoff.subtract(const Duration(seconds: 1));

      if (createdAt.isBefore(cutoff)) {
        expired.add(key as String);
        await _outboxBox.delete(key);
      }
    }
    return expired;
  }

  // ── Sent messages ───────────────────────────────────────────────────────────

  Future<void> saveSentMessage(MeshMessage message, String plaintext) async {
    await _sentBox.put(message.id, {
      ...message.toJson(),
      'plaintext': plaintext,
    });
  }

  Future<void> updateSentMessageStatus(
      String messageId, MessageStatus status) async {
    final raw = _sentBox.get(messageId);
    if (raw == null) return;
    final map = Map<String, dynamic>.from(raw as Map);
    map['status'] = status.index;
    await _sentBox.put(messageId, map);
  }

  // ── Inbox ───────────────────────────────────────────────────────────────────

  bool hasInboxMessage(String messageId) {
    return _inboxBox.containsKey(messageId);
  }

  Future<void> saveToInbox(MeshMessage message) async {
    if (message.type != MessageType.data) return;
    if (hasInboxMessage(message.id)) return;
    await _inboxBox.put(message.id, message.toJson());
  }

  // ── Conversation view ───────────────────────────────────────────────────────

  List<MeshMessage> getMessagesForContact(String myUserId, String contactId) {
    final results = <MeshMessage>[];

    for (final raw in _sentBox.values) {
      final map = Map<String, dynamic>.from(raw as Map);
      final msg = MeshMessage.fromJson(map);
      if (msg.senderId == myUserId && msg.recipientId == contactId) {
        final statusIdx = _statusBox.get(msg.id) as int?;
        results.add(statusIdx != null
            ? msg.copyWith(status: MessageStatus.values[statusIdx])
            : msg);
      }
    }

    for (final raw in _inboxBox.values) {
      final map = Map<String, dynamic>.from(raw as Map);
      final msg = MeshMessage.fromJson(map);
      if (msg.type == MessageType.data &&
          msg.senderId == contactId &&
          msg.recipientId == myUserId) {
        results.add(msg);
      }
    }

    // Always sort chronologically by local arrival time so the UI is stable
    results.sort((a, b) {
      final aTime = a.localReceivedTime ?? a.timestamp;
      final bTime = b.localReceivedTime ?? b.timestamp;
      return aTime.compareTo(bTime);
    });
    
    return results;
  }

  String? getSentPlaintext(String messageId) {
    final raw = _sentBox.get(messageId);
    if (raw == null) return null;
    return (raw as Map)['plaintext'] as String?;
  }

  // ── Delivery status ─────────────────────────────────────────────────────────

  Future<void> setMessageStatus(
      String messageId, MessageStatus status) async {
    await _statusBox.put(messageId, status.index);
    await updateSentMessageStatus(messageId, status);
  }

  MessageStatus getMessageStatus(String messageId) {
    final idx = _statusBox.get(messageId) as int?;
    if (idx == null) return MessageStatus.pending;
    return MessageStatus.values[idx];
  }

  // ── Unread counts ───────────────────────────────────────────────────────────

  Future<void> incrementUnread(String contactId) async {
    final key     = _hiveKey(contactId);
    final current = (_unreadBox.get(key) as int?) ?? 0;
    await _unreadBox.put(key, current + 1);
  }

  Future<void> clearUnread(String contactId) async {
    await _unreadBox.put(_hiveKey(contactId), 0);
  }

  int getUnreadCount(String contactId) {
    return (_unreadBox.get(_hiveKey(contactId)) as int?) ?? 0;
  }

  // ── Contacts ────────────────────────────────────────────────────────────────

  Future<void> saveContact(Contact contact) async {
    await _contactsBox.put(_hiveKey(contact.id), contact.toJson());
  }

  Contact? getContact(String id) {
    final data = _contactsBox.get(_hiveKey(id));
    if (data == null) return null;
    return Contact.fromJson(Map<String, dynamic>.from(data as Map));
  }

  List<Contact> getAllContacts() {
    return _contactsBox.values
        .map((e) => Contact.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<void> deleteContact(String id) async {
    await _contactsBox.delete(_hiveKey(id));
  }

  // ── Nuclear option ──────────────────────────────────────────────────────────

  Future<void> clearAllData() async {
    await _outboxBox.clear();
    await _inboxBox.clear();
    await _sentBox.clear();
    await _contactsBox.clear();
    await _unreadBox.clear();
    await _statusBox.clear();
    await _seenBox.clear();
  }

  // ── Seen message ID persistence (restart dedup) ─────────────────────────────

  static const int _maxSeenPersisted = 2000;

  Future<void> persistSeenId(String messageId) async {
    if (_seenBox.length >= _maxSeenPersisted) {
      final oldestKey = _seenBox.keys.first;
      await _seenBox.delete(oldestKey);
    }
    await _seenBox.put(messageId, true);
  }

  List<String> getPersistedSeenIds() {
    return _seenBox.keys.cast<String>().toList();
  }
}
