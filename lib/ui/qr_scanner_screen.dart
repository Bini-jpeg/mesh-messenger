// FILE: lib/ui/qr_scanner_screen.dart
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../core/app_config.dart';
import '../core/crypto_service.dart';
import '../core/storage_service.dart';
import '../main.dart';
import '../models/contact.dart';

class QRScannerScreen extends StatefulWidget {
  const QRScannerScreen({super.key});

  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen> {
  bool _isProcessing = false;
  MobileScannerController? _controller;

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid || Platform.isIOS) {
      _controller = MobileScannerController();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  bool _isValidKey(String value) {
    return value.length >= AppConfig.minPublicKeyHexLength &&
        RegExp(r'^[0-9a-fA-F]+$').hasMatch(value);
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return Scaffold(
        appBar: AppBar(title: const Text('Add Contact')),
        body: _buildManualEntry(),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Scan Contact QR')),
      body: MobileScanner(
        controller: _controller!,
        onDetect: (capture) {
          if (_isProcessing) return;
          for (final barcode in capture.barcodes) {
            final raw = barcode.rawValue ?? '';
            if (_isValidKey(raw)) {
              _isProcessing = true;
              _controller?.stop();
              _showNameDialog(raw);
              break;
            }
          }
        },
        errorBuilder: (context, error, child) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.camera_alt, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              Text('Camera error: $error'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Go Back'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildManualEntry() {
    final keyCtrl  = TextEditingController();
    final nameCtrl = TextEditingController();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.camera_alt_outlined, size: 64, color: Colors.grey),
          const SizedBox(height: 12),
          const Text('QR scanning is only available on Android/iOS.\n'
              'Enter the contact\'s public key manually:'),
          const SizedBox(height: 20),
          TextField(
            controller: keyCtrl,
            decoration: const InputDecoration(
              labelText: 'Public Key (hex)',
              border: OutlineInputBorder(),
            ),
            maxLines: 4,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: nameCtrl,
            decoration: const InputDecoration(
              labelText: 'Contact Name (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                final key = keyCtrl.text.trim();
                if (!_isValidKey(key)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text(
                            'Invalid public key — must be a valid hex string.')),
                  );
                  return;
                }
                _saveContact(key, nameCtrl.text.trim());
              },
              child: const Text('Add Contact'),
            ),
          ),
        ],
      ),
    );
  }

  void _showNameDialog(String publicKey) {
    final nameCtrl = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('New Contact'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Key: ${publicKey.substring(0, 20)}…',
              style: const TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: Colors.grey),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Contact name',
                hintText: 'Leave blank for default name',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
              textCapitalization: TextCapitalization.words,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              _isProcessing = false;
              _controller?.start();
              Navigator.pop(context);
            },
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _saveContact(publicKey, nameCtrl.text.trim());
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _saveContact(String publicKey, String rawName) {
    // Fix 5: prevent saving your own QR code as a contact.
    // This can happen if a user accidentally scans their own screen.
    if (publicKey == sl<CryptoService>().userId) {
      if (mounted) {
        // Resume scanning in case the user wants to try again.
        _isProcessing = false;
        _controller?.start();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'This QR code is your own. Scan someone else\'s code to add them.'),
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    final existing = sl<StorageService>().getContact(publicKey);
    if (existing != null) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('"${existing.name}" is already in your contacts.'),
          ),
        );
      }
      return;
    }

    final name = rawName.isEmpty
        ? 'Unnamed ${DateTime.now().millisecondsSinceEpoch % 10000}'
        : rawName;

    sl<StorageService>().saveContact(Contact(
      id:        publicKey,
      name:      name,
      createdAt: DateTime.now(),
    ));

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Contact "$name" saved!')),
      );
    }
  }
}
