import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// RADAR SYNC SERVICE (Tracking & Engagement Engine)
/// Handles User Status, Location (IP-based), and Video Watching Sessions.
class AppRadarSyncService with WidgetsBindingObserver {
  // Singleton Pattern
  AppRadarSyncService._internal();
  static final AppRadarSyncService instance = AppRadarSyncService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  
  Timer? _engagementTimer;
  String? _currentLocation;
  bool _isWatching = false;

  /// 1. INITIALIZE (Call in main.dart)
  void init() {
    WidgetsBinding.instance.addObserver(this);
    
    // Listen for Auth changes to sync data immediately on login
    _auth.authStateChanges().listen((User? user) {
      if (user != null) {
        syncUserStatus();
        _syncOfflineMinutes(); // Sync any pending offline minutes
      }
    });
  }

  /// 1.1 GET LOCAL CACHE FILE
  Future<File> _getOfflineCacheFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/offline_watch_cache.json');
  }

  /// 1.2 SYNC OFFLINE MINUTES TO FIRESTORE
  Future<void> _syncOfflineMinutes() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final file = await _getOfflineCacheFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        final data = json.decode(content);
        int pendingMinutes = data['minutes'] ?? 0;

        if (pendingMinutes > 0) {
          await _db.collection('users').doc(user.uid).update({
            'totalMinutesWatched': FieldValue.increment(pendingMinutes),
            'lastActive': FieldValue.serverTimestamp(),
          });
          // Clear cache after successful sync
          await file.writeAsString(json.encode({'minutes': 0}));
        }
      }
    } catch (e) {
      debugPrint("Radar Offline Sync Error: $e");
    }
  }

  /// 2. USER STATUS & LOCATION SYNC (HTTPS Fail-safe Architecture)
  Future<void> syncUserStatus() async {
    final user = _auth.currentUser;
    if (user == null) return;

    String location = _currentLocation ?? "Network Active";
    try {
      // Primary High-Stability Provider: ipwho.is (HTTPS)
      final response = await http.get(Uri.parse('https://ipwho.is/')).timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          location = "${data['city'] ?? "Unknown"}, ${data['region'] ?? ""}";
          _currentLocation = location;
        }
      }
    } catch (_) {
      // Graceful Fallback to cached location or status string
      location = _currentLocation ?? "Network Active";
    }

    // Fetch actual device brand and model
    String deviceDisplayName = Platform.isAndroid ? "Android Device" : "iOS Device";
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        deviceDisplayName = "${androidInfo.brand} ${androidInfo.model}";
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        deviceDisplayName = iosInfo.name;
      }
    } catch (e) {
      debugPrint("Error fetching device info: $e");
    }

    await _db.collection('users').doc(user.uid).set({
      'uid': user.uid,
      'email': user.email,
      'isOnline': true,
      'lastActive': FieldValue.serverTimestamp(),
      'device': deviceDisplayName,
      'location': location,
      'locationInfo': location, // Compatibility with Admin Panel
      'deviceType': Platform.isAndroid ? "Mobile" : "Tablet",
    }, SetOptions(merge: true));
  }

  /// 3. VIDEO WATCHING TRACKER (Include Subject Name)
  void updateWatchingStatus({
    required bool isWatching,
    String? lectureTitle,
    String? unitName,
    String? subjectName,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;

    _isWatching = isWatching;

    await _db.collection('users').doc(user.uid).update({
      'isWatching': isWatching,
      'currentPlayingLecture': isWatching ? lectureTitle : null,
      'currentUnit': isWatching ? unitName : null,
      'currentSubject': isWatching ? subjectName : null, // New field for Live Tracking
    });

    // LEADERBOARD LOGIC: Every 60s increment minutes watched
    if (isWatching) {
      _engagementTimer?.cancel();
      _engagementTimer = Timer.periodic(const Duration(seconds: 60), (timer) async {
        if (_isWatching && _auth.currentUser != null) {
          try {
            // Attempt online sync
            await _db.collection('users').doc(_auth.currentUser!.uid).update({
              'totalMinutesWatched': FieldValue.increment(1),
              'lastActive': FieldValue.serverTimestamp(),
            }).timeout(const Duration(seconds: 5));
          } catch (e) {
            // OFFLINE LOGIC: Save to local cache if Firestore update fails
            try {
              final file = await _getOfflineCacheFile();
              int currentPending = 0;
              if (await file.exists()) {
                final content = await file.readAsString();
                currentPending = json.decode(content)['minutes'] ?? 0;
              }
              await file.writeAsString(json.encode({'minutes': currentPending + 1}));
              debugPrint("Radar: Saved 1 minute to offline cache");
            } catch (cacheError) {
              debugPrint("Radar Cache Error: $cacheError");
            }
          }
        } else {
          timer.cancel();
        }
      });
    } else {
      _engagementTimer?.cancel();
      _syncOfflineMinutes(); // Attempt sync when video stops
    }
  }

  /// 4. AUTOMATIC LIFECYCLE TRACKING
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      syncUserStatus();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive || state == AppLifecycleState.detached) {
      // Mark offline immediately when leaving or closing the app
      setOffline();
      
      // Stop watch session tracking if app is closed/hidden
      if (_isWatching) {
        updateWatchingStatus(isWatching: false);
      }
    }
  }

  Future<void> setOffline() async {
    final user = _auth.currentUser;
    if (user == null) return;
    await _db.collection('users').doc(user.uid).update({'isOnline': false});
  }
}
