import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  // --- 1. LINK PROTECTION (OBFUSCATION) ---
  static String encryptLink(String url) => base64.encode(utf8.encode(url));
  static String decryptLink(String encoded) {
    try {
      return utf8.decode(base64.decode(encoded));
    } catch (e) {
      return encoded; // Return as is if it's not base64 (legacy data)
    }
  }

  // --- 2. ADMIN ROLE CHECK ---
  Future<bool> isAdmin() async {
    User? user = _auth.currentUser;
    if (user == null) return false;
    DocumentSnapshot doc = await _firestore.collection('users').doc(user.uid).get();
    if (doc.exists) {
      return (doc.data() as Map<String, dynamic>)['role'] == 'admin';
    }
    return false;
  }

  // Get Unique Device ID
  Future<String?> _getDeviceId() async {
    try {
      if (Platform.isAndroid) {
        AndroidDeviceInfo androidInfo = await _deviceInfo.androidInfo;
        return androidInfo.id;
      } else if (Platform.isIOS) {
        IosDeviceInfo iosInfo = await _deviceInfo.iosInfo;
        return iosInfo.identifierForVendor;
      }
    } catch (e) {
      return null;
    }
    return null;
  }

  // --- 3. SECURE SIGN IN WITH DEVICE LOCK ---
  Future<String?> signIn({required String email, required String password}) async {
    try {
      String? currentDeviceId = await _getDeviceId();
      if (currentDeviceId == null) return "Could not identify device.";

      UserCredential result = await _auth.signInWithEmailAndPassword(email: email, password: password);
      User? user = result.user;

      if (user != null) {
        DocumentReference userDoc = _firestore.collection('users').doc(user.uid);
        DocumentSnapshot doc = await userDoc.get();

        if (!doc.exists) {
          await userDoc.set({
            'email': email,
            'deviceId': currentDeviceId,
            'role': 'student', // Default role
            'lockedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
          return null;
        }

        Map<String, dynamic> userData = doc.data() as Map<String, dynamic>;
        String? registeredDeviceId = userData['deviceId'];

        if (registeredDeviceId == null || registeredDeviceId.isEmpty) {
          await userDoc.update({'deviceId': currentDeviceId, 'lockedAt': FieldValue.serverTimestamp()});
          return null;
        } else if (registeredDeviceId != currentDeviceId) {
          await _auth.signOut();
          return "DEVICE_MISMATCH";
        }
      }
      return null;
    } on FirebaseAuthException catch (e) {
      return e.message;
    } catch (e) {
      return "An unexpected error occurred.";
    }
  }

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

  Future<String?> signUp({required String email, required String password, required String name}) async {
    try {
      UserCredential result = await _auth.createUserWithEmailAndPassword(email: email, password: password);
      await _firestore.collection('users').doc(result.user!.uid).set({
        'name': name,
        'email': email,
        'role': 'student', // Explicitly set role
        'deviceId': '',
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
}
