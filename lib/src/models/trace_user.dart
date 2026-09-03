/// The tracked user, as the Barikoi backend knows it.
///
/// Mirrors `TraceUser.kt` and `TraceUser.swift`. [companyId] and [group] drive
/// MQTT topic resolution — authentication fails before ever producing a
/// [TraceUser] without a company, so in practice they are non-null on any user
/// returned by `setOrCreateUser`.
class TraceUser {
  /// Creates a user.
  TraceUser({
    required this.userId,
    this.name,
    this.email,
    this.phone,
    this.companyId,
    this.group,
    this.lastLat = 0,
    this.lastLon = 0,
    required this.updatedAt,
  });

  /// Barikoi-issued user id. The MQTT client id and every upload are keyed on
  /// this.
  final String userId;

  /// Display name, if one was supplied at creation.
  final String? name;

  /// Email address, if one was supplied at creation.
  final String? email;

  /// Phone number — the identity `setOrCreateUser` looks up on.
  final String? phone;

  /// Owning company id. Part of the MQTT topic.
  final String? companyId;

  /// Group within the company, if the account is grouped.
  final String? group;

  /// Latitude of the last fix the backend has for this user, or `0` if none.
  final double lastLat;

  /// Longitude of the last fix the backend has for this user, or `0` if none.
  final double lastLon;

  /// When the record was last updated. Decoded from the natives' epoch
  /// milliseconds, in UTC.
  final DateTime updatedAt;

  /// Decodes the wire map documented in `docs/WIRE_CONTRACT.md`.
  ///
  /// [userId] falls back to the empty string and [updatedAt] to the epoch when
  /// the platform omits them, so a partially populated map never throws mid
  /// stream.
  static TraceUser fromMap(Map<String, Object?> map) {
    return TraceUser(
      userId: map['userId'] is String ? map['userId']! as String : '',
      name: map['name'] is String ? map['name']! as String : null,
      email: map['email'] is String ? map['email']! as String : null,
      phone: map['phone'] is String ? map['phone']! as String : null,
      companyId: map['companyId'] is String ? map['companyId']! as String : null,
      group: map['group'] is String ? map['group']! as String : null,
      lastLat: map['lastLat'] is num ? (map['lastLat']! as num).toDouble() : 0,
      lastLon: map['lastLon'] is num ? (map['lastLon']! as num).toDouble() : 0,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        map['updatedAt'] is num ? (map['updatedAt']! as num).toInt() : 0,
        isUtc: true,
      ),
    );
  }

  /// Encodes back to the wire map. Present for symmetry and for tests; the
  /// plugin never sends a user to the platform side.
  Map<String, Object?> toMap() => <String, Object?>{
        'userId': userId,
        'name': name,
        'email': email,
        'phone': phone,
        'companyId': companyId,
        'group': group,
        'lastLat': lastLat,
        'lastLon': lastLon,
        'updatedAt': updatedAt.millisecondsSinceEpoch,
      };

  @override
  String toString() => 'TraceUser(userId: $userId, name: $name, '
      'email: $email, phone: $phone, companyId: $companyId, group: $group, '
      'lastLat: $lastLat, lastLon: $lastLon, updatedAt: $updatedAt)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TraceUser &&
          other.userId == userId &&
          other.name == name &&
          other.email == email &&
          other.phone == phone &&
          other.companyId == companyId &&
          other.group == group &&
          other.lastLat == lastLat &&
          other.lastLon == lastLon &&
          other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(
        userId,
        name,
        email,
        phone,
        companyId,
        group,
        lastLat,
        lastLon,
        updatedAt,
      );
}
