// FILE: lib/ui/contact_list_screen.dart
import 'package:flutter/material.dart';
import '../core/app_config.dart';
import '../core/crypto_service.dart';
import '../core/storage_service.dart';
import '../main.dart';
import '../models/contact.dart';

class ContactListScreen extends StatefulWidget {
  final Function(Contact) onContactTap;
  final Map<String, int> unreadCounts;

  const ContactListScreen({
    super.key,
    required this.onContactTap,
    this.unreadCounts = const {},
  });

  @override
  State<ContactListScreen> createState() => _ContactListScreenState();
}

class _ContactListScreenState extends State<ContactListScreen> {
  final _storage = sl<StorageService>();
  // Fix 5: we need the current user's ID to reject self-contact attempts.
  final _crypto  = sl<CryptoService>();

  List<Contact> _contacts = [];

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  void _loadContacts() {
    setState(() => _contacts = _storage.getAllContacts());
  }

  // ── Add contact manually ────────────────────────────────────────────────────

  void _showAddContactDialog() {
    final keyController  = TextEditingController();
    final nameController = TextEditingController();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add Contact'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: keyController,
              decoration: const InputDecoration(
                labelText: 'Public Key (hex)',
                hintText: 'Paste the full RSA public key',
                border: OutlineInputBorder(),
              ),
              maxLines: 4,
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Name (optional)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => _saveContactFromInputs(
                keyController.text, nameController.text, context),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _saveContactFromInputs(
      String rawKey, String rawName, BuildContext ctx) {
    final key = rawKey.trim();

    if (key.length < AppConfig.minPublicKeyHexLength ||
        !RegExp(r'^[0-9a-fA-F]+$').hasMatch(key)) {
      ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
        content: Text(
          'Invalid key — paste the full public key shown in your '
          'contact\'s "My QR Code" screen (~512 hex characters).',
        ),
        duration: Duration(seconds: 4),
      ));
      return;
    }

    // Fix 5: prevent the user from adding their own public key as a contact.
    if (key == _crypto.userId) {
      ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
        content: Text(
            'This is your own public key. You cannot add yourself as a contact.'),
        duration: Duration(seconds: 3),
      ));
      return;
    }

    final name = rawName.trim().isEmpty
        ? 'Unnamed ${DateTime.now().millisecondsSinceEpoch % 10000}'
        : rawName.trim();

    final existing = _storage.getContact(key);
    if (existing != null) {
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
        content: Text('"${existing.name}" is already in your contacts.'),
      ));
      Navigator.pop(ctx);
      return;
    }

    _storage.saveContact(Contact(
      id:        key,
      name:      name,
      createdAt: DateTime.now(),
    ));
    _loadContacts();
    Navigator.pop(ctx);
    ScaffoldMessenger.of(ctx).showSnackBar(
      const SnackBar(content: Text('Contact saved!')),
    );
  }

  // ── Rename contact ──────────────────────────────────────────────────────────

  void _showRenameDialog(Contact contact) {
    final controller = TextEditingController(text: contact.name);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Rename Contact'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'New name',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final newName = controller.text.trim();
              if (newName.isEmpty) return;

              // Fix 7: reload the contact record from storage immediately
              // before saving to avoid a stale-object race where a concurrent
              // rename from another widget rebuilds overwrites this update.
              // This is especially important if the contact record gains more
              // fields in the future.
              final latest = _storage.getContact(contact.id) ?? contact;
              _storage.saveContact(latest.copyWith(name: newName));

              _loadContacts();
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  // ── Delete contact ──────────────────────────────────────────────────────────

  void _showDeleteDialog(Contact contact) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Contact'),
        content: Text('Remove "${contact.name}" from your contacts?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              _storage.deleteContact(contact.id);
              _loadContacts();
              Navigator.pop(context);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
          child: Row(
            children: [
              const Text('Contacts',
                  style: TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.person_add),
                onPressed: _showAddContactDialog,
                tooltip: 'Add contact manually',
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _loadContacts,
                tooltip: 'Refresh',
              ),
            ],
          ),
        ),
        Expanded(
          child: _contacts.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'No contacts yet.\n\n'
                      'Add one by scanning their QR code or entering their public key manually.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: _contacts.length,
                  itemBuilder: (context, index) {
                    final contact = _contacts[index];
                    final unread  = widget.unreadCounts[contact.id] ?? 0;

                    return ListTile(
                      leading: CircleAvatar(
                        child: Text(
                          contact.name.isNotEmpty
                              ? contact.name[0].toUpperCase()
                              : '?',
                        ),
                      ),
                      title: Text(contact.name),
                      subtitle: Text(
                        contact.shortId,
                        style: const TextStyle(
                            fontSize: 11, fontFamily: 'monospace'),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (unread > 0)
                            Container(
                              margin: const EdgeInsets.only(right: 4),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.blue,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                unread > 99 ? '99+' : '$unread',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                          PopupMenuButton<_ContactAction>(
                            onSelected: (action) {
                              if (action == _ContactAction.rename) {
                                _showRenameDialog(contact);
                              } else {
                                _showDeleteDialog(contact);
                              }
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                value: _ContactAction.rename,
                                child: ListTile(
                                  leading: Icon(Icons.edit),
                                  title: Text('Rename'),
                                  contentPadding: EdgeInsets.zero,
                                ),
                              ),
                              PopupMenuItem(
                                value: _ContactAction.delete,
                                child: ListTile(
                                  leading: Icon(
                                      Icons.delete, color: Colors.red),
                                  title: Text('Delete',
                                      style: TextStyle(color: Colors.red)),
                                  contentPadding: EdgeInsets.zero,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      onTap: () => widget.onContactTap(contact),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

enum _ContactAction { rename, delete }
