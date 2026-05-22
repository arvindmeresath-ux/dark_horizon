import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  // Get Unique Device ID
  Future<String?> _getDeviceId() async {
    try {
      if (Platform.isAndroid) {
        AndroidDeviceInfo androidInfo = await _deviceInfo.androidInfo;
        return androidInfo.id; // Unique ID for Android
      } else if (Platform.isIOS) {
        IosDeviceInfo iosInfo = await _deviceInfo.iosInfo;
        return iosInfo.identifierForVendor; // Unique ID for iOS
      }
    } catch (e) {
      return null;
    }
    return null;
  }

  // Sign In with Device Lock Logic
  Future<String?> signIn({
    required String email,
    required String password,
    bool force = false,
  }) async {
    try {
      // 1. Get current device ID
      String? currentDeviceId = await _getDeviceId();
      if (currentDeviceId == null) return "Could not identify device.";

      // 2. Perform Standard Auth
      UserCredential result = await _auth.signInWithEmailAndPassword(
        email: email, 
        password: password
      );
      User? user = result.user;

      if (user != null) {
        // 3. Check User Record in Firestore
        DocumentReference userDoc = _firestore.collection('users').doc(user.uid);
        DocumentSnapshot doc = await userDoc.get();

        if (!doc.exists) {
          await userDoc.set({
            'email': email,
            'deviceId': currentDeviceId,
            'lockedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
          return null;
        }

        Map<String, dynamic> userData = doc.data() as Map<String, dynamic>;
        String? registeredDeviceId = userData['deviceId'];

        if (registeredDeviceId == null || registeredDeviceId.isEmpty || force) {
          // First time login or Forced login
          await userDoc.update({
            'deviceId': currentDeviceId,
            'lockedAt': FieldValue.serverTimestamp(),
          });
          return null;
        } else if (registeredDeviceId != currentDeviceId) {
          // Device Mismatch!
          await _auth.signOut();
          return "DEVICE_MISMATCH"; // Return specific code for UI to handle
        }
      }
      return null;
    } on FirebaseAuthException catch (e) {
      return e.message;
    } catch (e) {
      return "An unexpected error occurred.";
    }
  }

  // Check if device is still valid (for use in AuthWrapper or Periodic check)
  Future<bool> isDeviceAuthorized() async {
    User? user = _auth.currentUser;
    if (user == null) return false;

    String? currentId = await _getDeviceId();
    DocumentSnapshot doc = await _firestore.collection('users').doc(user.uid).get();
    
    if (doc.exists) {
      String? registeredId = (doc.data() as Map<String, dynamic>)['deviceId'];
      return registeredId == null || registeredId.isEmpty || registeredId == currentId;
    }
    return true;
  }

  // Admin Sign Up (Optional - you can use this or create manually in Console)
  Future<String?> signUp({
    required String email,
    required String password,
    required String name,
  }) async {
    try {
      UserCredential result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      User? user = result.user;

      // Note: We don't save deviceId here so that the student 
      // can lock it during THEIR first login.
      await _firestore.collection('users').doc(user!.uid).set({
        'name': name,
        'email': email,
        'branch': 'Electrical Engineering',
        'deviceId': '', // Empty initially
        'createdAt': FieldValue.serverTimestamp(),
      });

      return null; 
    } on FirebaseAuthException catch (e) {
      return e.message;
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }

  Future<String> getUserName(String uid) async {
    DocumentSnapshot doc = await _firestore.collection('users').doc(uid).get();
    if (doc.exists) {
      return (doc.data() as Map<String, dynamic>)['name'] ?? 'Student';
    }
    return 'Student';
  }
}
