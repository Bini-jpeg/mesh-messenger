// FILE: lib/models/contact.dart

/// A contact is uniquely identified by their RSA public key (full hex modulus).
/// [id] is the full public key — there is no separate publicKey field.
/// This eliminates any possibility of ID/key mismatch.
class Contact {
  final String id; // full RSA modulus hex — also used for encryption
  final String name;
  final DateTime createdAt;

  Contact({
    required this.id,
    required this.name,
    required this.createdAt,
  });

  /// The key used for encryption is the id itself.
  String get publicKey => id;

  /// Short display label for UI — visual only, never used in logic.
  String get shortId => id.length > 16 ? '${id.substring(0, 16)}…' : id;

  Contact copyWith({String? name}) => Contact(
        id: id,
        name: name ?? this.name,
        createdAt: createdAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'created': createdAt.toIso8601String(),
      };

  factory Contact.fromJson(Map<String, dynamic> json) => Contact(
        id: json['id'] as String,
        name: json['name'] as String,
        createdAt: DateTime.parse(json['created'] as String),
      );
}
