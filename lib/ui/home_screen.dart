// FILE: lib/ui/home_screen.dart
import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../core/crypto_service.dart';
import '../core/storage_service.dart';
import '../main.dart';
import '../models/message.dart';
import '../network/peer_model.dart';
import '../network/transport_service.dart';
import 'chat_screen.dart';
import 'contact_list_screen.dart';
import 'debug_menu.dart';
import 'qr_scanner_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _crypto    = sl<CryptoService>();
  final _transport = sl<TransportService>();
  final _storage   = sl<StorageService>();

  int _connectedPeers = 0;
  bool _isRestartingNetwork = false;
  final Map<String, int> _unreadCounts = {};

  StreamSubscription<PeerEvent>? _peerSub;
  StreamSubscription<MeshMessage>? _msgSub;

  @override
  void initState() {
    super.initState();
    _refreshUnreadCounts();

    _peerSub = _transport.peerStream.listen((_) {
      if (mounted) {
        setState(() => _connectedPeers = _transport.knownPeers.length);
      }
    });

    _msgSub = _transport.messageStream.listen((msg) {
      if (msg.type != MessageType.data) return;
      _storage.incrementUnread(msg.senderId);
      if (mounted) {
        setState(() {
          _unreadCounts[msg.senderId] =
              _storage.getUnreadCount(msg.senderId);
        });
      }
    });
  }

  void _refreshUnreadCounts() {
    final counts = <String, int>{};
    for (final c in _storage.getAllContacts()) {
      counts[c.id] = _storage.getUnreadCount(c.id);
    }
    if (mounted) {
      setState(() => _unreadCounts
        ..clear()
        ..addAll(counts));
    }
  }

  @override
  void dispose() {
    _peerSub?.cancel();
    _msgSub?.cancel();
    super.dispose();
  }

  // ── Network Restart ─────────────────────────────────────────────────────────

  Future<void> _restartNetwork() async {
    if (_isRestartingNetwork) return;
    setState(() => _isRestartingNetwork = true);
    
    try {
      await _transport.restartNode();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Network successfully restarted.'),
            duration: Duration(seconds: 2),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to restart network: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isRestartingNetwork = false);
      }
    }
  }

  // ── Navigation ──────────────────────────────────────────────────────────────

  Future<void> _openChat(String contactId) async {
    await _storage.clearUnread(contactId);
    if (!mounted) return;
    setState(() => _unreadCounts[contactId] = 0);
    await Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => ChatScreen(contactId: contactId)),
    );
    _refreshUnreadCounts();
  }

  void _scanQR() {
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => const QRScannerScreen()));
  }

  void _showMyQR() {
    final pubKey = _crypto.publicKey;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Your QR Code'),
        content: SizedBox(
          width: 280,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children:[
              const Text(
                'Let others scan this to add you as a contact.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 16),
              Container(
                color: Colors.white,
                padding: const EdgeInsets.all(8),
                child: SizedBox(
                  width: 220,
                  height: 220,
                  child: QrImageView(
                    data: pubKey,
                    version: QrVersions.auto,
                    backgroundColor: Colors.white,
                    errorCorrectionLevel: QrErrorCorrectLevel.L,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: pubKey));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Public key copied to clipboard!')),
                  );
                },
                child: Text(
                  _crypto.shortDisplayId,
                  style: const TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: Colors.grey),
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Tap key to copy full value',
                style:
                    TextStyle(fontSize: 10, color: Colors.grey),
              ),
            ],
          ),
        ),
        actions:[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showDebugMenu() {
    showDialog(context: context, builder: (_) => const DebugMenu());
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mesh Messenger'),
        actions:[
          IconButton(
            icon: const Icon(Icons.bug_report),
            onPressed: _showDebugMenu,
            tooltip: 'Debug / Research',
          ),
        ],
      ),
      body: Column(
        children:[
          _buildStatusCard(),
          Expanded(
            child: ContactListScreen(
              unreadCounts: _unreadCounts,
              onContactTap: (contact) => _openChat(contact.id),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard() {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children:[
            // My ID row
            Row(
              children:[
                const Text('My ID:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _crypto.shortDisplayId,
                    style: const TextStyle(
                        fontFamily: 'monospace', fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy, size: 18),
                  tooltip: 'Copy full public key',
                  onPressed: () {
                    Clipboard.setData(
                        ClipboardData(text: _crypto.publicKey));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content:
                              Text('Public key copied to clipboard!'),
                          duration: Duration(seconds: 2)),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Connection status row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children:[
                Text('Peers: $_connectedPeers connected'),
                Row(
                  children: [
                    if (_isRestartingNetwork)
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    else
                      IconButton(
                        icon: const Icon(Icons.restart_alt, size: 20),
                        tooltip: 'Restart Network manually',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 40),
                        onPressed: _restartNetwork,
                      ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _connectedPeers > 0
                            ? Colors.green
                            : Colors.orange,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _connectedPeers > 0 ? 'Active' : 'Searching…',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ],
            ),

            if (!_transport.isInitialized && Platform.isAndroid)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children:[
                      const Icon(Icons.warning, color: Colors.redAccent, size: 20),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text('Network Offline. Missing permissions?',
                            style: TextStyle(fontSize: 12)),
                      ),
                      TextButton(
                        onPressed: _restartNetwork,
                        child: const Text('RETRY'),
                      ),
                    ],
                  ),
                ),
              ),

            if (!Platform.isAndroid)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'Desktop preview: mesh networking disabled.',
                  style:
                      TextStyle(color: Colors.orange, fontSize: 11),
                ),
              ),

            const SizedBox(height: 16),

            // Action buttons
            Row(
              children:[
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.qr_code),
                    label: const Text('My QR Code'),
                    onPressed: _showMyQR,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('Scan QR'),
                    onPressed: _scanQR,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
