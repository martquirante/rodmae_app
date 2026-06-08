import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/theme.dart';
import '../core/constants.dart';
import '../models/couple_location.dart';
import '../services/supabase_service.dart';
import '../services/auth_service.dart';
import '../services/firebase_service.dart';
import '../widgets/animated_3d_card.dart';
import '../widgets/glass_card.dart';
import '../widgets/isometric_markers.dart';

enum MapType { street, satellite, hybrid }

enum TransitMode {
  walking(Icons.directions_walk_rounded, 'Walking', 5.0, Colors.green),
  bicycling(Icons.directions_bike_rounded, 'Biking', 15.0, Colors.teal),
  motorcycle(Icons.motorcycle_rounded, 'Motorcycle', 40.0, Colors.orange),
  driving(Icons.directions_car_rounded, 'Driving', 50.0, Colors.amber),
  transit(Icons.directions_bus_rounded, 'Commuting', 25.0, Colors.indigo);

  final IconData icon;
  final String label;
  final double speedKmh; // Average speed
  final Color color;

  const TransitMode(this.icon, this.label, this.speedKmh, this.color);
}

class MapScreen extends StatefulWidget {
  final bool autoHeadingHome;
  const MapScreen({super.key, this.autoHeadingHome = false});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with TickerProviderStateMixin {
  final MapController _mapController = MapController();
  MapType _currentMapType = MapType.hybrid;

  // Search details
  final TextEditingController _searchController = TextEditingController();
  List<dynamic> _searchResults = [];
  bool _isSearching = false;
  LatLng? _searchPin;

  // Coordinates
  LatLng? _myLocation;
  LatLng? _spouseLocation;
  LatLng? _homeLocation;
  LatLng? _myWorkLocation;
  LatLng? _spouseWorkLocation;

  // Location name labels from Nominatim / DB
  String _homeLocationName = 'Home';
  String _myWorkLocationName = 'My Work';
  String _spouseWorkLocationName = "Spouse's Work";

  // Routing details
  List<LatLng> _routePoints = [];
  double _routeDistanceKm = 0.0;
  double _routeDurationMin = 0.0;

  // Real-time location streams
  StreamSubscription<Position>? _positionStreamSub;
  StreamSubscription<List<CoupleLocation>>? _locationsSub;

  // Transit animation variables
  AnimationController? _transitSimController;
  LatLng? _simulatedVehiclePosition;
  TransitMode? _activeTransitMode;
  bool _isSimulatingTransit = false;

  Timer? _debounce;
  bool _isLayersExpanded = false;
  bool _isPinningMode = false;
  LatLng? _pinnedLocationPreview;
  bool _isReverseGeocoding = false;
  String? _myAvatarUrl;
  String? _spouseAvatarUrl;

  // ── Presence tracking ────────────────────────────────────────────────────
  DateTime? _spouseLastSeen;
  bool _isSpouseOnline = false;

  // ── Smooth lerp animation for spouse marker ──────────────────────────────
  LatLng? _spouseFromLoc;    // lerp start position
  LatLng? _spouseTargetLoc;  // lerp end / current target
  AnimationController? _spouseLerpController;

  // ── Timers ───────────────────────────────────────────────────────────────
  Timer? _heartbeatTimer;
  Timer? _presenceRefreshTimer;

  // ── Supabase Realtime broadcast channel for < 100 ms location delivery ───
  RealtimeChannel? _locationBroadcastChannel;

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () {
      if (query.trim().isNotEmpty) {
        _searchPlaces(query);
      } else {
        setState(() {
          _searchResults = [];
        });
      }
    });
  }

  Future<void> _confirmPinnedLocation(String type) async {
    final pos = _pinnedLocationPreview ?? _mapController.camera.center;
    final partner = PartnerIdentity.active.value.label;

    setState(() => _isReverseGeocoding = true);

    String locName = type == 'home' ? 'Our Home' : '$partner\'s Work';
    final url = Uri.parse(
      'https://nominatim.openstreetmap.org/reverse?lat=${pos.latitude}&lon=${pos.longitude}&format=json&addressdetails=1'
    );
    try {
      final response = await http.get(url, headers: {'User-Agent': 'rodmae_app'});
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final displayName = decoded['display_name'];
        if (displayName != null) {
          final address = decoded['address'];
          if (address != null) {
            final road = address['road'] ?? address['suburb'] ?? address['neighbourhood'] ?? '';
            final city = address['city'] ?? address['municipality'] ?? address['town'] ?? address['county'] ?? '';
            if (road.isNotEmpty && city.isNotEmpty) {
              locName = '$road, $city';
            } else if (road.isNotEmpty) {
              locName = road;
            } else {
              locName = displayName.toString().split(',').take(2).join(', ');
            }
          } else {
            locName = displayName.toString().split(',').take(2).join(', ');
          }
        }
      }
    } catch (_) {}

    final loc = CoupleLocation(
      id: '',
      coupleId: AppConfig.coupleId,
      partner: type == 'home' ? 'shared' : partner,
      position: pos,
      locationType: type,
      locationName: locName,
      updatedAt: DateTime.now(),
    );

    try {
      await SupabaseWeddingRepository.instance.upsertLocation(loc);
      if (mounted) _showSuccessSnackBar('${type == 'home' ? 'Home' : 'Work'} saved: $locName ✅');
    } catch (e) {
      if (mounted) _showErrorSnackBar('Save failed: $e');
    }

    setState(() {
      _isPinningMode = false;
      _pinnedLocationPreview = null;
      _isReverseGeocoding = false;
    });
  }

  Future<void> _loadUserAvatars() async {
    final me = PartnerIdentity.active.value.label;
    final spouse = PartnerIdentity.active.value == PartnerProfile.rodel
        ? PartnerProfile.maryMae.label
        : PartnerProfile.rodel.label;

    try {
      final myProfile = await SupabaseWeddingRepository.instance.fetchUserProfile(me);
      final spouseProfile = await SupabaseWeddingRepository.instance.fetchUserProfile(spouse);

      if (mounted) {
        setState(() {
          _myAvatarUrl = myProfile?.avatarUrl;
          _spouseAvatarUrl = spouseProfile?.avatarUrl;
        });
      }
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();

    // Smooth lerp controller for spouse marker movement (60 fps rebuild)
    _spouseLerpController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    _spouseLerpController!.addListener(() {
      if (mounted) setState(() {});
    });

    // 30-second heartbeat so the partner always sees an up-to-date last-seen
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      final me = PartnerIdentity.active.value.label;
      SupabaseWeddingRepository.instance
          .updatePresenceHeartbeat(me)
          .catchError((_) {});
      // Also re-broadcast position over Realtime for sub-100 ms partners
      if (_myLocation != null) _broadcastLocation(_myLocation!);
    });

    // Refresh the online/offline indicator every 15 s
    _presenceRefreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) {
        setState(() {
          _isSpouseOnline = _spouseLastSeen != null &&
              DateTime.now()
                  .difference(_spouseLastSeen!)
                  .inSeconds < 90;
        });
      }
    });

    _requestPermissionAndTrack();
    _listenToSpouseAndStaticLocations();
    _subscribeToBroadcast();
    _loadUserAvatars();

    if (widget.autoHeadingHome) {
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted && _myLocation != null && _homeLocation != null) {
          _fetchRoute(_myLocation!, _homeLocation!).then((_) {
            if (mounted) _showTransitSelectionBottomSheet();
          });
        } else if (mounted) {
          _showErrorSnackBar(
              'Set your Home location first to use Heading Home routing.');
        }
      });
    }
  }

  @override
  void dispose() {
    _positionStreamSub?.cancel();
    _locationsSub?.cancel();
    _transitSimController?.dispose();
    _spouseLerpController?.dispose();
    _searchController.dispose();
    _debounce?.cancel();
    _heartbeatTimer?.cancel();
    _presenceRefreshTimer?.cancel();
    _unsubscribeBroadcast();
    super.dispose();
  }

  // Request Location Permissions & Start Tracking
  Future<void> _requestPermissionAndTrack() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _showErrorSnackBar('Location services are disabled.');
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _showErrorSnackBar('Location permissions are denied.');
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      _showErrorSnackBar('Location permissions are permanently denied.');
      return;
    }

    // Get current position once
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      final latLng = LatLng(pos.latitude, pos.longitude);
      setState(() => _myLocation = latLng);
      _mapController.move(latLng, 14.5);
      
      // Upsert live location to database
      _updateLiveLocationInDatabase(latLng);
    } catch (_) {}

    // Watch live location
    _positionStreamSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen((pos) {
      final latLng = LatLng(pos.latitude, pos.longitude);
      if (mounted) {
        setState(() => _myLocation = latLng);
        _updateLiveLocationInDatabase(latLng);
      }
    });
  }

  // Listen to Database Locations (Spouse position + pinned Home/Work)
  void _listenToSpouseAndStaticLocations() {
    _locationsSub =
        SupabaseWeddingRepository.instance.watchLocations().listen((locations) {
      if (!mounted) return;
      final currentPartner = PartnerIdentity.active.value.label;

      LatLng? newSpouseLoc;
      DateTime? newSpouseLastSeen;
      LatLng? newHomeLoc;
      LatLng? newMyWork;
      LatLng? newSpouseWork;

      String? newHomeName;
      String? newMyWorkName;
      String? newSpouseWorkName;

      for (final loc in locations) {
        if (loc.locationType == 'live' && loc.partner != currentPartner) {
          newSpouseLoc = loc.position;
          // Use the DB updated_at as fallback last-seen (broadcast is faster)
          newSpouseLastSeen = loc.updatedAt;
        } else if (loc.locationType == 'home') {
          newHomeLoc = loc.position;
          if (loc.locationName != null && loc.locationName!.isNotEmpty) {
            newHomeName = loc.locationName;
          }
        } else if (loc.locationType == 'work') {
          if (loc.partner == currentPartner) {
            newMyWork = loc.position;
            if (loc.locationName != null && loc.locationName!.isNotEmpty) {
              newMyWorkName = loc.locationName;
            }
          } else {
            newSpouseWork = loc.position;
            if (loc.locationName != null && loc.locationName!.isNotEmpty) {
              newSpouseWorkName = loc.locationName;
            }
          }
        }
      }

      setState(() {
        _homeLocation = newHomeLoc;
        _myWorkLocation = newMyWork;
        _spouseWorkLocation = newSpouseWork;
        if (newHomeName != null) _homeLocationName = newHomeName;
        if (newMyWorkName != null) _myWorkLocationName = newMyWorkName;
        if (newSpouseWorkName != null) _spouseWorkLocationName = newSpouseWorkName;
      });

      // Animate spouse to new DB position (broadcast may have already handled it)
      if (newSpouseLoc != null) {
        _spouseLocation = newSpouseLoc; // keep for Focus/Pin backwards compat
        _onNewSpouseLocation(newSpouseLoc, newSpouseLastSeen);
      }

      if (_myAvatarUrl == null || _spouseAvatarUrl == null) _loadUserAvatars();
    });
  }

  Future<void> _updateLiveLocationInDatabase(LatLng pos) async {
    final me = PartnerIdentity.active.value.label;
    final loc = CoupleLocation(
      id: '',
      coupleId: AppConfig.coupleId,
      partner: me,
      position: pos,
      locationType: 'live',
      updatedAt: DateTime.now(),
    );
    await SupabaseWeddingRepository.instance.upsertLocation(loc);
    // Also push a Realtime broadcast for sub-100 ms delivery on the partner's device
    _broadcastLocation(pos);
  }

  // ── Realtime Broadcast helpers ────────────────────────────────────────────

  void _subscribeToBroadcast() {
    if (!AppRuntime.supabaseReady) return;
    try {
      _locationBroadcastChannel = Supabase.instance.client
          .channel('location:${AppConfig.coupleId}');

      _locationBroadcastChannel!
          .onBroadcast(
            event: 'gps',
            callback: (payload) {
              if (!mounted) return;
              final sender = payload['sender']?.toString() ?? '';
              final me = PartnerIdentity.active.value.label;
              // Ignore my own broadcast echoes
              if (sender.toLowerCase() == me.toLowerCase()) return;

              final lat = (payload['lat'] as num?)?.toDouble();
              final lon = (payload['lon'] as num?)?.toDouble();
              if (lat == null || lon == null) return;

              final ts = DateTime.tryParse(payload['ts']?.toString() ?? '') ??
                  DateTime.now().toUtc();

              _spouseLocation = LatLng(lat, lon); // keep for Focus/Pin
              _onNewSpouseLocation(LatLng(lat, lon), ts);
            },
          )
          .subscribe();
    } catch (_) {}
  }

  void _unsubscribeBroadcast() {
    try {
      _locationBroadcastChannel?.unsubscribe();
    } catch (_) {}
    _locationBroadcastChannel = null;
  }

  void _broadcastLocation(LatLng pos) {
    try {
      _locationBroadcastChannel?.sendBroadcastMessage(
        event: 'gps',
        payload: {
          'sender': PartnerIdentity.active.value.label,
          'lat': pos.latitude,
          'lon': pos.longitude,
          'ts': DateTime.now().toUtc().toIso8601String(),
        },
      );
    } catch (_) {}
  }

  // ── Spouse marker lerp ────────────────────────────────────────────────────

  /// Called whenever a new spouse location arrives (DB stream OR broadcast).
  /// Smoothly interpolates the map marker from the previous to the new position.
  void _onNewSpouseLocation(LatLng newLoc, DateTime? lastSeen) {
    if (!mounted) return;
    final ctrl = _spouseLerpController;
    if (ctrl == null) {
      setState(() {
        _spouseFromLoc = newLoc;
        _spouseTargetLoc = newLoc;
      });
      return;
    }

    // Mid-animation? Compute current interpolated position as new start.
    LatLng from;
    if (_spouseFromLoc != null &&
        _spouseTargetLoc != null &&
        ctrl.isAnimating) {
      final t = Curves.easeOutCubic.transform(ctrl.value.clamp(0.0, 1.0));
      from = LatLng(
        _spouseFromLoc!.latitude +
            (_spouseTargetLoc!.latitude - _spouseFromLoc!.latitude) * t,
        _spouseFromLoc!.longitude +
            (_spouseTargetLoc!.longitude - _spouseFromLoc!.longitude) * t,
      );
    } else {
      from = _spouseTargetLoc ?? newLoc;
    }

    // Only update last-seen if this timestamp is newer
    final effectiveLastSeen = lastSeen?.toLocal() ?? DateTime.now();
    final isNewer = _spouseLastSeen == null ||
        effectiveLastSeen.isAfter(_spouseLastSeen!);

    setState(() {
      _spouseFromLoc = from;
      _spouseTargetLoc = newLoc;
      if (isNewer) {
        _spouseLastSeen = effectiveLastSeen;
        _isSpouseOnline = DateTime.now()
                .difference(effectiveLastSeen)
                .inSeconds <
            90;
      }
    });

    ctrl.forward(from: 0);
  }

  // ── Presence helpers ─────────────────────────────────────────────────────

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  // nominatim search
  Future<void> _searchPlaces(String query) async {
    if (query.trim().isEmpty) return;
    setState(() => _isSearching = true);
    
    final encodedQuery = Uri.encodeComponent(query);
    final url = Uri.parse('https://nominatim.openstreetmap.org/search?q=$encodedQuery&format=json&limit=5&addressdetails=1');
    
    try {
      final response = await http.get(url, headers: {'User-Agent': 'rodmae_app'});
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            _searchResults = decoded;
            _isSearching = false;
          });
        }
      } else {
        setState(() => _isSearching = false);
      }
    } catch (_) {
      setState(() => _isSearching = false);
    }
  }

  // OSRM snapped-to-road routing
  Future<void> _fetchRoute(LatLng start, LatLng end) async {
    final url = Uri.parse(
      'http://router.project-osrm.org/route/v1/driving/'
      '${start.longitude},${start.latitude};${end.longitude},${end.latitude}'
      '?overview=full&geometries=geojson'
    );

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final routes = data['routes'] as List;
        if (routes.isNotEmpty) {
          final route = routes.first;
          final geometry = route['geometry'];
          final coordinates = geometry['coordinates'] as List;
          
          final points = coordinates.map((c) {
            final lon = (c[0] as num).toDouble();
            final lat = (c[1] as num).toDouble();
            return LatLng(lat, lon);
          }).toList();

          final distance = (route['distance'] as num).toDouble() / 1000.0; // km
          final duration = (route['duration'] as num).toDouble() / 60.0; // min

          setState(() {
            _routePoints = points;
            _routeDistanceKm = distance;
            _routeDurationMin = duration;
          });

          // Move camera to fit route
          _fitRouteBounds(points);
        }
      } else {
        _showErrorSnackBar('Routing service error.');
      }
    } catch (e) {
      _showErrorSnackBar('Could not fetch directions.');
    }
  }

  void _fitRouteBounds(List<LatLng> points) {
    if (points.isEmpty) return;
    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLon = points.first.longitude;
    double maxLon = points.first.longitude;

    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLon) minLon = p.longitude;
      if (p.longitude > maxLon) maxLon = p.longitude;
    }

    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds(LatLng(minLat, minLon), LatLng(maxLat, maxLon)),
        padding: const EdgeInsets.all(64),
      ),
    );
  }



  // Heading Home transit simulation
  void _startTransitSimulation(TransitMode mode) {
    if (_routePoints.isEmpty) {
      _showErrorSnackBar('Please calculate a route first.');
      return;
    }

    // Trigger love signal to other spouse
    SupabaseWeddingRepository.instance
        .insertLoveTrigger('Heading Home')
        .catchError((_) {});

    _transitSimController?.dispose();
    setState(() {
      _activeTransitMode = mode;
      _isSimulatingTransit = true;
      _isSearching = false;
      _searchResults = [];
    });

    // Approximate duration in seconds (shorter for simulation visuals)
    const simDuration = Duration(seconds: 10);
    _transitSimController = AnimationController(
      vsync: this,
      duration: simDuration,
    );

    _transitSimController!.addListener(() {
      final val = _transitSimController!.value;
      if (val >= 1.0) {
        setState(() {
          _isSimulatingTransit = false;
          _simulatedVehiclePosition = null;
        });
        _showSuccessSnackBar('You have arrived home safely! ❤️');
      } else {
        // Interpolate along route points
        setState(() {
          _simulatedVehiclePosition = _interpolateRoutePosition(val);
        });
      }
    });

    _transitSimController!.forward();
  }

  LatLng _interpolateRoutePosition(double fraction) {
    if (_routePoints.isEmpty) return _myLocation ?? const LatLng(0, 0);
    if (_routePoints.length == 1) return _routePoints.first;

    final totalPoints = _routePoints.length;
    final targetIndexFloat = fraction * (totalPoints - 1);
    final index1 = targetIndexFloat.floor();
    final index2 = (index1 + 1).clamp(0, totalPoints - 1);
    final segmentFraction = targetIndexFloat - index1;

    final p1 = _routePoints[index1];
    final p2 = _routePoints[index2];

    final lat = p1.latitude + (p2.latitude - p1.latitude) * segmentFraction;
    final lon = p1.longitude + (p2.longitude - p1.longitude) * segmentFraction;

    return LatLng(lat, lon);
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.redAccent,
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: RodMaeColors.mint,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // ── Build markers ────────────────────────────────────────────────────
    final markers = <Marker>[];

    // Compute smooth lerped spouse render position
    LatLng? spouseRenderPos;
    if (_spouseFromLoc != null &&
        _spouseTargetLoc != null &&
        _spouseLerpController != null) {
      final t = Curves.easeOutCubic
          .transform(_spouseLerpController!.value.clamp(0.0, 1.0));
      spouseRenderPos = LatLng(
        _spouseFromLoc!.latitude +
            (_spouseTargetLoc!.latitude - _spouseFromLoc!.latitude) * t,
        _spouseFromLoc!.longitude +
            (_spouseTargetLoc!.longitude - _spouseFromLoc!.longitude) * t,
      );
    } else {
      spouseRenderPos = _spouseTargetLoc;
    }

    final myName = PartnerIdentity.active.value.label;
    final spouseName = PartnerIdentity.active.value == PartnerProfile.rodel
        ? PartnerProfile.maryMae.label
        : PartnerProfile.rodel.label;

    // My marker (always online while visible)
    if (_myLocation != null && !_isSimulatingTransit) {
      markers.add(
        Marker(
          point: _myLocation!,
          width: 92,
          height: 116,
          alignment: Alignment.topCenter,
          child: PersonGameMarker(
            name: myName,
            markerColor: RodMaeColors.electricBlue,
            presence: PresenceStatus.online,
            avatarUrl: _myAvatarUrl,
            initials: myName.substring(0, 1),
            isMe: true,
          ),
        ),
      );
    }

    // Spouse marker — lerp animated, presence-aware
    if (spouseRenderPos != null) {
      markers.add(
        Marker(
          point: spouseRenderPos,
          width: 92,
          height: 116,
          alignment: Alignment.topCenter,
          child: PersonGameMarker(
            name: spouseName,
            markerColor: RodMaeColors.rose,
            presence:
                _isSpouseOnline ? PresenceStatus.online : PresenceStatus.offline,
            avatarUrl: _spouseAvatarUrl,
            initials: spouseName.substring(0, 1),
            lastSeenLabel:
                _spouseLastSeen != null ? _timeAgo(_spouseLastSeen!) : null,
          ),
        ),
      );
    }

    // Home marker (3D-style house) with DB location name label
    if (_homeLocation != null) {
      markers.add(
        Marker(
          point: _homeLocation!,
          width: 95,
          height: 105,
          alignment: Alignment.topCenter,
          child: IsometricMarker(
            type: 'home',
            label: _homeLocationName,
            color: RodMaeColors.gold,
          ),
        ),
      );
    }

    // My Work marker with DB location name label
    if (_myWorkLocation != null) {
      markers.add(
        Marker(
          point: _myWorkLocation!,
          width: 95,
          height: 105,
          alignment: Alignment.topCenter,
          child: IsometricMarker(
            type: 'work',
            label: _myWorkLocationName,
            color: RodMaeColors.electricBlue,
          ),
        ),
      );
    }

    // Spouse Work marker with DB location name label
    if (_spouseWorkLocation != null) {
      markers.add(
        Marker(
          point: _spouseWorkLocation!,
          width: 95,
          height: 105,
          alignment: Alignment.topCenter,
          child: IsometricMarker(
            type: 'work',
            label: _spouseWorkLocationName,
            color: RodMaeColors.rose,
          ),
        ),
      );
    }

    // Search pin marker
    if (_searchPin != null) {
      markers.add(
        Marker(
          point: _searchPin!,
          width: 50,
          height: 50,
          child: const Icon(
            Icons.location_on_rounded,
            color: Colors.redAccent,
            size: 40,
          ),
        ),
      );
    }

    // Temporary preview pin marker in pinning mode
    if (_isPinningMode && _pinnedLocationPreview != null) {
      markers.add(
        Marker(
          point: _pinnedLocationPreview!,
          width: 85,
          height: 85,
          alignment: Alignment.topCenter,
          child: const IsometricMarker(
            type: 'home',
            label: 'TAP TO MOVE PIN',
            color: RodMaeColors.gold,
            isAnimated: true,
          ),
        ),
      );
    }

    // Simulated Vehicle Marker
    if (_simulatedVehiclePosition != null && _activeTransitMode != null) {
      markers.add(
        Marker(
          point: _simulatedVehiclePosition!,
          width: 85,
          height: 85,
          alignment: Alignment.topCenter,
          child: _buildVehicleMarker(_activeTransitMode!),
        ),
      );
    }

    return Scaffold(
      backgroundColor: RodMaeColors.background,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // 1. FlutterMap Widget
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _myLocation ?? const LatLng(14.5547, 121.0244),
              initialZoom: 13.5,
              maxZoom: 18.0,
              minZoom: 4.0,
              onTap: (tapPosition, point) {
                if (_isPinningMode) {
                  setState(() {
                    _pinnedLocationPreview = point;
                  });
                }
              },
              onPositionChanged: (camera, hasGesture) {
                if (_isPinningMode && hasGesture) {
                  setState(() {
                    _pinnedLocationPreview = camera.center;
                  });
                }
              },
            ),
            children: [
              // Layers
              if (_currentMapType == MapType.street)
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.rodmae_app',
                ),
              if (_currentMapType == MapType.satellite || _currentMapType == MapType.hybrid)
                TileLayer(
                  urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
                  userAgentPackageName: 'com.example.rodmae_app',
                ),
              if (_currentMapType == MapType.satellite || _currentMapType == MapType.hybrid)
                TileLayer(
                  urlTemplate: 'https://mt1.google.com/vt/lyrs=h&x={x}&y={y}&z={z}',
                  userAgentPackageName: 'com.example.rodmae_app',
                ),

              // Polyline snapped route
              if (_routePoints.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _routePoints,
                      color: RodMaeColors.electricBlue,
                      strokeWidth: 5.5,
                      borderColor: RodMaeColors.sky,
                      borderStrokeWidth: 1.5,
                    ),
                  ],
                ),

              // Markers layer
              MarkerLayer(markers: markers),
            ],
          ),

          // Presence HUD chip (bottom-left, above the zoom controls)
          Positioned(
            bottom: 200,
            left: 16,
            child: _buildPresenceHud(isDark),
          ),

          // 2. Floating Search Bar & Results
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 16,
            right: 16,
            child: Column(
              children: [
                // Glassmorphic Search Input Bar
                GlassCard(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  borderRadius: BorderRadius.circular(24),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Icon(
                          Icons.arrow_back_ios_new_rounded,
                          color: isDark ? Colors.white70 : RodMaeColors.lightText,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          style: GoogleFonts.inter(
                            color: isDark ? Colors.white : RodMaeColors.lightText,
                            fontSize: 13,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Search place, street, or city...',
                            filled: false,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                            hintStyle: GoogleFonts.inter(
                              color: isDark ? Colors.white38 : Colors.black38,
                              fontSize: 13,
                            ),
                          ),
                          onChanged: _onSearchChanged,
                          onSubmitted: _searchPlaces,
                        ),
                      ),
                      if (_isSearching)
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: RodMaeColors.gold,
                          ),
                        )
                      else
                        IconButton(
                          icon: Icon(
                            Icons.search_rounded,
                            color: isDark ? RodMaeColors.sky : RodMaeColors.royalBlue,
                            size: 20,
                          ),
                          onPressed: () => _searchPlaces(_searchController.text),
                        ),
                    ],
                  ),
                ),

                // Search Results Dropdown List
                if (_searchResults.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    constraints: const BoxConstraints(maxHeight: 220),
                    child: GlassCard(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      borderRadius: BorderRadius.circular(18),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: _searchResults.length,
                        separatorBuilder: (context, index) => Divider(
                          color: Colors.white.withValues(alpha: isDark ? 0.08 : 0.2),
                          height: 1,
                        ),
                        itemBuilder: (context, index) {
                          final item = _searchResults[index];
                          final displayName = item['display_name'] ?? 'Unknown place';
                          return ListTile(
                            title: Text(
                              displayName,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: isDark ? Colors.white : RodMaeColors.lightText,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            dense: true,
                            onTap: () {
                              final lat = double.parse(item['lat']);
                              final lon = double.parse(item['lon']);
                              final pin = LatLng(lat, lon);
                              setState(() {
                                _searchPin = pin;
                                _searchResults = [];
                                _searchController.text = displayName;
                                if (_isPinningMode) {
                                  _pinnedLocationPreview = pin;
                                }
                              });
                              _mapController.move(pin, 15.5);
                            },
                          );
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // 3. Floating Control Actions (Right Side Buttons)
          Positioned(
            right: 16,
            bottom: (_routePoints.isNotEmpty || _isPinningMode) ? 190 : 100,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Map Type Toggler (Street, Satellite, Hybrid) - Expandable
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (_isLayersExpanded) ...[
                      _buildLayerOptionButton(
                        label: 'Street',
                        icon: Icons.map_outlined,
                        isActive: _currentMapType == MapType.street,
                        onPressed: () {
                          setState(() {
                            _currentMapType = MapType.street;
                            _isLayersExpanded = false;
                          });
                        },
                        isDark: isDark,
                      ),
                      const SizedBox(height: 8),
                      _buildLayerOptionButton(
                        label: 'Satellite',
                        icon: Icons.satellite_outlined,
                        isActive: _currentMapType == MapType.satellite,
                        onPressed: () {
                          setState(() {
                            _currentMapType = MapType.satellite;
                            _isLayersExpanded = false;
                          });
                        },
                        isDark: isDark,
                      ),
                      const SizedBox(height: 8),
                      _buildLayerOptionButton(
                        label: 'Hybrid',
                        icon: Icons.layers_outlined,
                        isActive: _currentMapType == MapType.hybrid,
                        onPressed: () {
                          setState(() {
                            _currentMapType = MapType.hybrid;
                            _isLayersExpanded = false;
                          });
                        },
                        isDark: isDark,
                      ),
                      const SizedBox(height: 8),
                    ],
                    _buildFloatingActionButton(
                      icon: Icons.layers_rounded,
                      onPressed: () {
                        setState(() {
                          _isLayersExpanded = !_isLayersExpanded;
                        });
                      },
                      isDark: isDark,
                      tooltip: 'Map Layer',
                      isSelected: _isLayersExpanded,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                
                // Recenter GPS Button
                _buildFloatingActionButton(
                  icon: Icons.my_location_rounded,
                  onPressed: () {
                    if (_myLocation != null) {
                      _mapController.move(_myLocation!, 15.0);
                    }
                  },
                  isDark: isDark,
                  tooltip: 'Recenter GPS',
                ),
                const SizedBox(height: 12),

                // Pinned Home / Work Setter Button
                _buildFloatingActionButton(
                  icon: Icons.add_location_alt_rounded,
                  onPressed: () {
                    setState(() {
                      _isPinningMode = !_isPinningMode;
                      if (_isPinningMode) {
                        _routePoints = [];
                        _searchPin = null;
                        _pinnedLocationPreview = _mapController.camera.center;
                      } else {
                        _pinnedLocationPreview = null;
                      }
                    });
                  },
                  isDark: isDark,
                  tooltip: 'Pin Locations',
                  isSelected: _isPinningMode,
                ),
                const SizedBox(height: 12),
                // Focus on Me
                _buildFloatingActionButton(
                  icon: Icons.person_pin_circle_rounded,
                  onPressed: () {
                    if (_myLocation != null) {
                      _mapController.move(_myLocation!, 15.5);
                    }
                  },
                  isDark: isDark,
                  tooltip: 'Focus Me',
                ),
                const SizedBox(height: 12),
                // Focus on Spouse
                _buildFloatingActionButton(
                  icon: Icons.people_rounded,
                  onPressed: () {
                    if (_spouseLocation != null) {
                      _mapController.move(_spouseLocation!, 15.5);
                    } else {
                      _showErrorSnackBar('Spouse location not available yet.');
                    }
                  },
                  isDark: isDark,
                  tooltip: 'Focus Spouse',
                ),
              ],
            ),
          ),

          // 4. Direction & Route Display Panel (Bottom Panel)
          if (_routePoints.isNotEmpty && !_isPinningMode)
            Positioned(
              left: 16,
              right: 16,
              bottom: 24,
              child: Animated3DCard(
                borderColor: RodMaeColors.gold.withValues(alpha: 0.3),
                padding: const EdgeInsets.all(18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: RodMaeColors.electricBlue.withValues(alpha: 0.14),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.directions_rounded,
                            color: RodMaeColors.electricBlue,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _isSimulatingTransit ? 'EN ROUTE TO HOME' : 'DIRECTIONS TO HOME',
                                style: GoogleFonts.inter(
                                  color: RodMaeColors.gold,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.2,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _isSimulatingTransit
                                    ? 'Simulating your transit live...'
                                    : 'Snapped to actual roads via OSRM.',
                                style: GoogleFonts.inter(
                                  color: isDark ? Colors.white70 : RodMaeColors.lightTextSoft,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '${_routeDistanceKm.toStringAsFixed(1)} KM',
                              style: GoogleFonts.robotoMono(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            Text(
                              '${_routeDurationMin.toStringAsFixed(0)} mins',
                              style: GoogleFonts.inter(
                                color: RodMaeColors.sky,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    
                    if (!_isSimulatingTransit)
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                setState(() {
                                  _routePoints = [];
                                  _searchPin = null;
                                  _searchController.clear();
                                });
                              },
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                              child: Text(
                                'Clear Route',
                                style: GoogleFonts.inter(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: _showTransitSelectionBottomSheet,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: RodMaeColors.gold,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                              child: Text(
                                'Go Heading Home',
                                style: GoogleFonts.inter(color: RodMaeColors.navy, fontSize: 12, fontWeight: FontWeight.w900),
                              ),
                            ),
                          ),
                        ],
                      )
                    else
                      // Progress bar showing transit simulation
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: LinearProgressIndicator(
                          value: _transitSimController?.value ?? 0,
                          backgroundColor: Colors.white.withValues(alpha: 0.1),
                          color: _activeTransitMode?.color ?? RodMaeColors.gold,
                          minHeight: 6,
                        ),
                      ),
                  ],
                ),
              ),
            ),

          // 5. Initial Quick Action (Direct directions trigger when not routing)
          if (_routePoints.isEmpty && !_isPinningMode)
            Positioned(
              left: 24,
              bottom: 24,
              child: ElevatedButton.icon(
                onPressed: () {
                  if (_myLocation != null && _homeLocation != null) {
                    _fetchRoute(_myLocation!, _homeLocation!);
                  } else {
                    _showErrorSnackBar('Current location or Home address is not set yet.');
                  }
                },
                icon: const Icon(Icons.navigation_rounded, color: RodMaeColors.navy, size: 18),
                label: Text(
                  'HEADING HOME',
                  style: GoogleFonts.inter(
                    color: RodMaeColors.navy,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.1,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: RodMaeColors.gold,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  elevation: 8,
                ),
              ),
            ),
                   // 6. Pinning Mode Bottom Panel
          if (_isPinningMode)
            Positioned(
              left: 16,
              right: 16,
              bottom: 24,
              child: Animated3DCard(
                borderColor: RodMaeColors.gold.withValues(alpha: 0.3),
                padding: const EdgeInsets.all(18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: RodMaeColors.gold.withValues(alpha: 0.14),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.add_location_alt_rounded,
                            color: RodMaeColors.gold,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'PINNING LOCATION',
                                style: GoogleFonts.inter(
                                  color: RodMaeColors.gold,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.2,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Tap map to move pin, or snap using shortcuts.',
                                style: GoogleFonts.inter(
                                  color: isDark ? Colors.white70 : RodMaeColors.lightTextSoft,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Snap shortcuts
                    Row(
                      children: [
                        Expanded(
                          child: TextButton.icon(
                            onPressed: _myLocation == null
                                ? null
                                : () {
                                    setState(() {
                                      _pinnedLocationPreview = _myLocation;
                                    });
                                    _mapController.move(_myLocation!, _mapController.camera.zoom);
                                  },
                            icon: const Icon(Icons.my_location_rounded, size: 14, color: RodMaeColors.electricBlue),
                            label: Text(
                              'Snap to Me',
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: _myLocation == null ? Colors.grey : RodMaeColors.electricBlue,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextButton.icon(
                            onPressed: _spouseLocation == null
                                ? null
                                : () {
                                    setState(() {
                                      _pinnedLocationPreview = _spouseLocation;
                                    });
                                    _mapController.move(_spouseLocation!, _mapController.camera.zoom);
                                  },
                            icon: const Icon(Icons.person_pin_circle_rounded, size: 14, color: RodMaeColors.rose),
                            label: Text(
                              'Snap to Spouse',
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: _spouseLocation == null ? Colors.grey : RodMaeColors.rose,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_isReverseGeocoding)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: RodMaeColors.gold,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'Reverse geocoding address...',
                              style: GoogleFonts.inter(
                                color: isDark ? Colors.white70 : RodMaeColors.lightTextSoft,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                setState(() {
                                  _isPinningMode = false;
                                  _pinnedLocationPreview = null;
                                });
                              },
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                              child: Text(
                                'Cancel',
                                style: GoogleFonts.inter(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () => _confirmPinnedLocation('home'),
                              icon: const Icon(Icons.home_rounded, color: RodMaeColors.navy, size: 14),
                              label: Text(
                                'Set Home',
                                style: GoogleFonts.inter(color: RodMaeColors.navy, fontSize: 12, fontWeight: FontWeight.w900),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: RodMaeColors.gold,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () => _confirmPinnedLocation('work'),
                              icon: const Icon(Icons.business_rounded, color: RodMaeColors.navy, size: 14),
                              label: Text(
                                'Set Work',
                                style: GoogleFonts.inter(color: RodMaeColors.navy, fontSize: 12, fontWeight: FontWeight.w900),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: RodMaeColors.electricBlue,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }



  Widget _buildFloatingActionButton({
    required IconData icon,
    required VoidCallback onPressed,
    required bool isDark,
    required String tooltip,
    bool isSelected = false,
  }) {
    final bgColor = isSelected
        ? RodMaeColors.gold
        : (isDark ? RodMaeColors.navy.withValues(alpha: 0.9) : Colors.white);
    final iconColor = isSelected
        ? RodMaeColors.navy
        : (isDark ? RodMaeColors.sky : RodMaeColors.royalBlue);
    return FloatingActionButton(
      heroTag: tooltip,
      onPressed: onPressed,
      tooltip: tooltip,
      backgroundColor: bgColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Colors.white.withValues(alpha: isDark ? 0.08 : 0.3),
        ),
      ),
      mini: true,
      child: Icon(
        icon,
        color: iconColor,
        size: 18,
      ),
    );
  }

  Widget _buildLayerOptionButton({
    required String label,
    required IconData icon,
    required bool isActive,
    required VoidCallback onPressed,
    required bool isDark,
  }) {
    final bgColor = isActive
        ? RodMaeColors.gold
        : (isDark ? RodMaeColors.navy.withValues(alpha: 0.9) : Colors.white);
    final iconColor = isActive
        ? RodMaeColors.navy
        : (isDark ? RodMaeColors.sky : RodMaeColors.royalBlue);
        
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.white.withValues(alpha: isDark ? 0.08 : 0.3),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 8,
              offset: const Offset(2, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: iconColor, size: 16),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.inter(
                color: isActive
                    ? RodMaeColors.navy
                    : (isDark ? Colors.white : RodMaeColors.lightText),
                fontSize: 10,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Kept for backward compatibility; now delegates to PersonGameMarker
  Widget _buildUserMarker(
    String name,
    bool isMe, {
    PresenceStatus presence = PresenceStatus.online,
    String? lastSeenLabel,
  }) {
    return PersonGameMarker(
      name: name,
      markerColor: isMe ? RodMaeColors.electricBlue : RodMaeColors.rose,
      presence: presence,
      avatarUrl: isMe ? _myAvatarUrl : _spouseAvatarUrl,
      initials: name.substring(0, 1),
      lastSeenLabel: lastSeenLabel,
      isMe: isMe,
    );
  }

  // ── Presence HUD (floating chip shown when spouse is detected offline) ────
  Widget _buildPresenceHud(bool isDark) {
    if (_spouseTargetLoc == null) return const SizedBox.shrink();
    final spouseName =
        PartnerIdentity.active.value == PartnerProfile.rodel
            ? PartnerProfile.maryMae.label
            : PartnerProfile.rodel.label;
    final presenceColor =
        _isSpouseOnline ? const Color(0xFF4ADE80) : const Color(0xFF6B7280);
    final label = _isSpouseOnline
        ? 'Online'
        : (_spouseLastSeen != null ? _timeAgo(_spouseLastSeen!) : 'Offline');

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: (isDark ? Colors.black : Colors.white)
                .withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: presenceColor.withValues(alpha: 0.35),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Animated presence dot
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: presenceColor,
                  boxShadow: [
                    BoxShadow(
                      color: presenceColor.withValues(alpha: 0.60),
                      blurRadius: 5,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 7),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    spouseName,
                    style: GoogleFonts.inter(
                      color: isDark ? Colors.white : const Color(0xFF1E3A8A),
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    label,
                    style: GoogleFonts.inter(
                      color: presenceColor,
                      fontSize: 8.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 3D/Isometric vehicle marker via IsometricMarker
  Widget _buildVehicleMarker(TransitMode mode) {
    return IsometricMarker(
      type: mode.name,
      label: mode.label,
      color: mode.color,
      isAnimated: true,
    );
  }



  void _showTransitSelectionBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: RodMaeColors.background.withValues(alpha: 0.95),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'SELECT TRANSIT MODE',
                  style: GoogleFonts.inter(
                    color: RodMaeColors.gold,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Choose your mode of transit. This will animate your 3D vehicle avatar and notify your spouse.',
                  style: GoogleFonts.inter(color: Colors.white60, fontSize: 11),
                ),
                const SizedBox(height: 20),
                
                // Horizontal list of transit modes
                SizedBox(
                  height: 94,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: TransitMode.values.length,
                    itemBuilder: (context, index) {
                      final mode = TransitMode.values[index];
                      return GestureDetector(
                        onTap: () {
                          Navigator.pop(context);
                          _startTransitSimulation(mode);
                        },
                        child: Container(
                          width: 82,
                          margin: const EdgeInsets.only(right: 12),
                          decoration: BoxDecoration(
                            color: mode.color.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: mode.color.withValues(alpha: 0.4),
                              width: 1.2,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(mode.icon, color: mode.color, size: 28),
                              const SizedBox(height: 8),
                              Text(
                                mode.label,
                                style: GoogleFonts.inter(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 18),
              ],
            ),
          ),
        );
      },
    );
  }
}
