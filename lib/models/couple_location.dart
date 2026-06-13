import 'package:latlong2/latlong.dart';

final class CoupleLocation {
  final String id;
  final String coupleId;
  final String partner;
  final LatLng position;
  final String locationType; // 'live', 'home', 'work'
  final String? locationName;
  final DateTime updatedAt;

  const CoupleLocation({
    required this.id,
    required this.coupleId,
    required this.partner,
    required this.position,
    required this.locationType,
    this.locationName,
    required this.updatedAt,
  });

  factory CoupleLocation.fromMap(Map<String, dynamic> row) {
    return CoupleLocation(
      id: '${row['id']}',
      coupleId: '${row['couple_id']}',
      partner: '${row['partner']}',
      position: LatLng(
        (row['latitude'] as num).toDouble(),
        (row['longitude'] as num).toDouble(),
      ),
      locationType: '${row['location_type']}',
      locationName: row['location_name'],
      updatedAt: DateTime.parse('${row['updated_at'] ?? DateTime.now().toIso8601String()}'),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'couple_id': coupleId,
      'partner': partner,
      'latitude': position.latitude,
      'longitude': position.longitude,
      'location_type': locationType,
      'location_name': locationName,
    };
  }
}
