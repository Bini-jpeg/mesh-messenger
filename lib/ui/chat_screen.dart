// FILE: lib/ui/chat_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../core/app_config.dart';
import '../core/crypto_service.dart';
import '../core/storage_service.dart';
import '../main.dart';
import '../models/contact.dart';
import '../models/message.dart';
import '../network/transport_service.dart';

class ChatScreen extends StatefulWidget {
  final String contactId;

  const ChatScreen({super.key, required this.contactId});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _msgController    = TextEditingController();
  final _scrollController = ScrollController();
  final _crypto    = sl<CryptoService>();
  final _storage   = sl<StorageService>();
  final _transport = sl<TransportService>();

  List<MeshMessage> _messages = [];
  Contact? _contact;

  bool _isSelfContact = false;

  StreamSubscription<MeshMessage>? _msgSub;
  StreamSubscription<({String messageId, MessageStatus status})>? _statusSub;

  @override
  void initState() {
    super.initState();
    _contact = _storage.getContact(widget.contactId);

    _isSelfContact = widget.contactId == _crypto.userId;

    _loadMessages();
    _subscribeToStreams();
    _storage.clearUnread(widget.contactId);
  }

  // ── Data loading ────────────────────────────────────────────────────────────

  void _loadMessages() {
    _messages = _storage.getMessagesForContact(
        _crypto.userId, widget.contactId);
    if (mounted) setState(() {});
    _scrollToBottom();
  }

  // ── Stream subscriptions ────────────────────────────────────────────────────

  void _subscribeToStreams() {
    _msgSub = _transport.messageStream.listen((message) {
      if (message.type != MessageType.data) return;

      final isFromContact = message.senderId == widget.contactId &&
          message.recipientId == _crypto.userId;
      if (!isFromContact) return;

      if (_messages.any((m) => m.id == message.id)) return;

      setState(() => _messages.add(message));
      _storage.clearUnread(widget.contactId);
      _scrollToBottom();
    });

    _statusSub = _transport.statusStream.listen((event) {
      final idx =
          _messages.indexWhere((m) => m.id == event.messageId);
      if (idx == -1) return;
      setState(() {
        _messages[idx] = _messages[idx].copyWith(status: event.status);
      });
    });
  }

  // ── Send ────────────────────────────────────────────────────────────────────

  Future<void> _sendMessage() async {
    if (_isSelfContact) {
      _showSnack('You cannot send a message to yourself.');
      return;
    }

    final text = _msgController.text.trim();
    if (text.isEmpty) return;

    final contact = _contact;
    if (contact == null) {
      _showSnack('Contact not found.');
      return;
    }

    String encrypted;
    try {
      encrypted = _crypto.encryptMessage(text, contact.id);
    } catch (e) {
      _showSnack('Encryption failed: $e'); 
      return;
    }

    final message = MeshMessage(
      id:                const Uuid().v4(),
      senderId:          _crypto.userId,
      recipientId:       widget.contactId,
      payload:           encrypted,
      ttl:               AppConfig.defaultTTL,
      hopCount:          0,
      timestamp:         DateTime.now(),
      sentTime:          DateTime.now(),
      status:            MessageStatus.pending,
      localReceivedTime: DateTime.now(),
    );

    await _storage.saveSentMessage(message, text);

    setState(() {
      _messages.add(message);
      _msgController.clear();
    });
    _scrollToBottom();

    await _transport.sendMessage(message);
  }

  // ── Display helpers ─────────────────────────────────────────────────────────

  String _getDisplayText(MeshMessage msg) {
    if (msg.senderId == _crypto.userId) {
      return _storage.getSentPlaintext(msg.id) ?? '[Message sent]';
    }
    
    // We catch structural decryption throws here so a single bad message
    // doesn't crash the entire list view build.
    try {
      return _crypto.decryptMessage(msg.payload);
    } catch (e) {
      return '[Unable to decrypt: Data corrupted or key mismatch]';
    }
  }

  String _formatTimestamp(DateTime dt) {
    final now     = DateTime.now();
    final isToday = dt.year == now.year &&
        dt.month == now.month &&
        dt.day == now.day;
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return isToday
        ? '$h:$m'
        : '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} $h:$m';
  }

  Widget _statusIcon(MessageStatus status) {
    switch (status) {
      case MessageStatus.pending:
        return const Icon(Icons.access_time,
            size: 12, color: Colors.white54);
      case MessageStatus.sent:
        return const Icon(Icons.check,
            size: 12, color: Colors.white70);
      case MessageStatus.delivered:
        return const Icon(Icons.done_all,
            size: 12, color: Colors.lightBlueAccent);
      case MessageStatus.failed:
        return const Icon(Icons.error_outline,
            size: 12, color: Colors.redAccent);
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_contact?.name ?? 'Chat'),
            if (_contact != null)
              Text(
                _contact!.shortId,
                style: const TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: Colors.white54),
              ),
          ],
        ),
      ),
      body: Column(
        children: [
          if (_isSelfContact)
            Container(
              width: double.infinity,
              color: Colors.orange.withValues(alpha: 0.85),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: const Text(
                'This contact is yourself. Sending is disabled.',
                style: TextStyle(color: Colors.white, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ),
          Expanded(
            child: _messages.isEmpty
                ? const Center(
                    child: Text(
                      'No messages yet.\nSay hello! 👋',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    itemCount: _messages.length,
                    itemBuilder: (_, index) =>
                        _buildBubble(_messages[index]),
                  ),
          ),
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildBubble(MeshMessage msg) {
    final isMe        = msg.senderId == _crypto.userId;
    final displayText = _getDisplayText(msg);

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isMe ? Colors.blue[700] : Colors.grey[800],
          borderRadius: BorderRadius.only(
            topLeft:     const Radius.circular(16),
            topRight:    const Radius.circular(16),
            bottomLeft:  Radius.circular(isMe ? 16 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(
              displayText,
              style: const TextStyle(color: Colors.white, fontSize: 15),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _formatTimestamp(msg.timestamp),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 10,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '· ${msg.hopCount}hop',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 10,
                  ),
                ),
                if (isMe) ...[
                  const SizedBox(width: 4),
                  _statusIcon(msg.status),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(color: Colors.grey.withValues(alpha: 0.3)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _msgController,
              maxLength: AppConfig.maxTextLength,
              enabled: !_isSelfContact,
              decoration: InputDecoration(
                hintText: _isSelfContact ? 'Cannot message yourself' : 'Message',
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                counterText: '',
              ),
              onSubmitted: (_) => _sendMessage(),
              textInputAction: TextInputAction.send,
              minLines: 1,
              maxLines: 4,
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.send),
            onPressed: _isSelfContact ? null : _sendMessage,
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _msgSub?.cancel();
    _statusSub?.cancel();
    _msgController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}
