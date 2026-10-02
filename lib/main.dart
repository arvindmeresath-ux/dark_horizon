import 'dart:isolate';
import 'dart:ui';
import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:open_filex/open_filex.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:http/http.dart' as http;
import 'custom_video_player.dart';
import 'auth_service.dart';
import 'connectivity_wrapper.dart';
import 'pdf_viewer_screen.dart';
import 'radar_sync_service.dart';

@pragma('vm:entry-point')
void downloadCallback(String id, int status, int progress) {
  final SendPort? send = IsolateNameServer.lookupPortByName('downloader_send_port');
  send?.send([id, status, progress]);
}

class OTTColors {
  static const Color background = Color(0xFF07080E);
  static const Color surface = Color(0xFF10121E);
  static const Color card = Color(0xFF161928);
  static const Color cardBorder = Color(0x22FFB703);
  static const Color primary = Color(0xFFFFB703); // Amber Gold
  static const Color secondary = Color(0xFFFF9F1C); // Vibrant Orange
  static const Color accentCyan = Color(0xFF00E5FF);
  static const Color textPrimary = Color(0xFFF8FAFC);
  static const Color textSecondary = Color(0xFF94A3B8);
}

class DownloadItemMeta {
  final String taskId;
  final String subject;
  final String unit;
  final String title;
  final String url;
  final bool isPdf;
  final String fileName;
  final int totalBytes;
  bool fileExists;

  DownloadItemMeta({
    required this.taskId,
    required this.subject,
    required this.unit,
    required this.title,
    required this.url,
    required this.isPdf,
    required this.fileName,
    this.totalBytes = 0,
    this.fileExists = false,
  });

  Map<String, dynamic> toJson() => {
        'taskId': taskId,
        'subject': subject,
        'unit': unit,
        'title': title,
        'url': url,
        'isPdf': isPdf,
        'fileName': fileName,
        'totalBytes': totalBytes,
      };

  factory DownloadItemMeta.fromJson(Map<String, dynamic> json) => DownloadItemMeta(
        taskId: json['taskId'] ?? '',
        subject: json['subject'] ?? 'General',
        unit: json['unit'] ?? 'Unit 1',
        title: json['title'] ?? '',
        url: json['url'] ?? '',
        isPdf: json['isPdf'] ?? false,
        fileName: json['fileName'] ?? '',
        totalBytes: json['totalBytes'] ?? 0,
      );
}

class DownloadManager {
  static const String _metaFileName = 'downloads_metadata.json';

  static Future<File> _getFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_metaFileName');
  }

  static Future<List<DownloadItemMeta>> getDownloads() async {
    try {
      final file = await _getFile();
      if (!await file.exists()) return [];
      final content = await file.readAsString();
      if (content.isEmpty) return [];
      final List<dynamic> jsonList = jsonDecode(content);
      return jsonList.map((e) => DownloadItemMeta.fromJson(e)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> addDownload(DownloadItemMeta meta) async {
    try {
      final list = await getDownloads();
      list.removeWhere((element) => element.taskId == meta.taskId || element.url == meta.url);
      list.add(meta);
      final file = await _getFile();
      await file.writeAsString(jsonEncode(list.map((e) => e.toJson()).toList()));
    } catch (_) {}
  }

  static Future<void> removeDownload(String taskId) async {
    try {
      final list = await getDownloads();
      list.removeWhere((element) => element.taskId == taskId);
      final file = await _getFile();
      await file.writeAsString(jsonEncode(list.map((e) => e.toJson()).toList()));
    } catch (_) {}
  }

  static Future<void> updateTaskId(String oldTaskId, String newTaskId) async {
    try {
      final list = await getDownloads();
      for (var item in list) {
        if (item.taskId == oldTaskId) {
          final index = list.indexOf(item);
          list[index] = DownloadItemMeta(
            taskId: newTaskId,
            subject: item.subject,
            unit: item.unit,
            title: item.title,
            url: item.url,
            isPdf: item.isPdf,
            fileName: item.fileName,
            totalBytes: item.totalBytes,
          );
          break;
        }
      }
      final file = await _getFile();
      await file.writeAsString(jsonEncode(list.map((e) => e.toJson()).toList()));
    } catch (_) {}
  }
}

// 1. GLOBAL THEME NOTIFIER
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.dark);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    // 1. Initialize orientation (Mobile only)
    if (Platform.isAndroid || Platform.isIOS) {
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    }

    // 2. Initialize Firebase
    await Firebase.initializeApp();
    debugPrint("Firebase initialized successfully");

    // 3. Optional services in background
    _initBackgroundServices();

    runApp(const MyApp());
  } catch (e) {
    debugPrint("CRITICAL STARTUP ERROR: $e");
    runApp(ErrorApp(error: e.toString()));
  }
}

Future<void> _initBackgroundServices() async {
  // Downloader (Mobile Only)
  if (Platform.isAndroid || Platform.isIOS) {
    try {
      await FlutterDownloader.initialize(debug: false, ignoreSsl: true);
      FlutterDownloader.registerCallback(downloadCallback);
    } catch (_) {}
  }

  // Tracking & Wakelock
  try {
    AppRadarSyncService.instance.init();
    if (Platform.isAndroid || Platform.isIOS) {
      await WakelockPlus.enable();
    }
  } catch (_) {}
}

class ErrorApp extends StatelessWidget {
  final String error;
  const ErrorApp({super.key, required this.error});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              "Startup Failed:\n$error",
              style: const TextStyle(color: Colors.red, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (_, ThemeMode currentMode, __) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Dark Horizon',
          theme: ThemeData(
            brightness: Brightness.light,
            scaffoldBackgroundColor: const Color(0xFFF5F5F5),
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.amber, brightness: Brightness.light),
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            scaffoldBackgroundColor: const Color(0xFF000814),
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.amber, brightness: Brightness.dark),
            useMaterial3: true,
          ),
          themeMode: currentMode,
          home: const ConnectivityWrapper(child: SystemStatusWrapper()),
        );
      },
    );
  }
}

class SystemStatusWrapper extends StatefulWidget {
  const SystemStatusWrapper({super.key});
  @override
  State<SystemStatusWrapper> createState() => _SystemStatusWrapperState();
}

class _SystemStatusWrapperState extends State<SystemStatusWrapper> {
  bool _isLoading = true;
  bool _isMaintenance = false;
  bool _needsUpdate = false;
  String _updateUrl = "";

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    try {
      final systemConf = await FirebaseFirestore.instance.collection('system').doc('config').get();
      bool maintenance = systemConf.data()?['isMaintenance'] ?? false;

      final updateConf = await FirebaseFirestore.instance.collection('app_settings').doc('update_config').get().timeout(const Duration(seconds: 7));
      
      dynamic rawVer = updateConf.data()?['latest_version'];
      int latestVersion = 1;
      if (rawVer is int) {
        latestVersion = rawVer;
      } else if (rawVer is double) {
        latestVersion = rawVer.toInt();
      } else if (rawVer is String) {
        latestVersion = int.tryParse(rawVer) ?? 1;
      }

      String downloadUrl = updateConf.data()?['download_url'] ?? "";
      const int currentVersion = 1;

      if (!mounted) return;
      setState(() {
        _isMaintenance = maintenance;
        // Disable auto-update popup on Windows for now
        _needsUpdate = (Platform.isAndroid || Platform.isIOS) && (latestVersion > currentVersion);
        _updateUrl = downloadUrl;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator(color: Colors.amber)));
    if (_isMaintenance) return const MaintenanceScreen();
    if (_needsUpdate) return UpdateDialog(downloadUrl: _updateUrl);
    return const AuthWrapper();
  }
}

class MaintenanceScreen extends StatelessWidget {
  const MaintenanceScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(30),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.handyman_rounded, size: 80, color: Colors.amber),
              SizedBox(height: 24),
              Text("SYSTEM MAINTENANCE", style: TextStyle(color: Colors.amber, fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 2)),
              SizedBox(height: 16),
              Text("We are currently upgrading our systems to serve you better. Please check back later.", textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, fontSize: 14)),
              SizedBox(height: 40),
              CircularProgressIndicator(color: Colors.amber, strokeWidth: 2),
            ],
          ),
        ),
      ),
    );
  }
}

class UpdateDialog extends StatefulWidget {
  final String downloadUrl;
  const UpdateDialog({super.key, required this.downloadUrl});
  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  double _progress = 0;
  bool _isDownloading = false;
  final ReceivePort _port = ReceivePort();

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid || Platform.isIOS) {
      if (IsolateNameServer.lookupPortByName('downloader_send_port') != null) {
        IsolateNameServer.removePortNameMapping('downloader_send_port');
      }
      IsolateNameServer.registerPortWithName(_port.sendPort, 'downloader_send_port');
      _port.listen((dynamic data) {
        if (data is List) {
          int status = data[1];
          int progress = data[2];
          if (mounted) setState(() { _progress = (progress / 100).clamp(0.0, 1.0); });
          if (status == 3) _installApk();
          if (status == 4) {
            if (mounted) setState(() => _isDownloading = false);
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Download Failed!")));
          }
        }
      });
    }
  }

  Future<void> _startUpdate() async {
    if (!Platform.isAndroid) return;
    await Permission.notification.request();
    if (!await Permission.requestInstallPackages.isGranted) {
      await Permission.requestInstallPackages.request();
    }
    if (!mounted) return;
    setState(() => _isDownloading = true);
    final directory = await getApplicationSupportDirectory();
    final file = File("${directory.path}/Update.apk");
    if (await file.exists()) await file.delete();
    await FlutterDownloader.enqueue(url: widget.downloadUrl, savedDir: directory.path, fileName: "Update.apk", showNotification: true, openFileFromNotification: true);
  }

  Future<void> _installApk() async {
    final directory = await getApplicationSupportDirectory();
    await OpenFilex.open("${directory.path}/Update.apk");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 30),
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: const Color(0xFF0A0A0A),
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: Colors.amber.withValues(alpha: 0.2), width: 1.5),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.auto_awesome_rounded, size: 50, color: Colors.amber),
              const SizedBox(height: 24),
              const Text("UPGRADE AVAILABLE", style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
              const SizedBox(height: 12),
              Text(_isDownloading ? "OPTIMIZING SYSTEM..." : "A new version is ready.", textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60, fontSize: 14)),
              const SizedBox(height: 32),
              if (_isDownloading)
                LinearProgressIndicator(value: _progress, color: Colors.amber)
              else
                SizedBox(width: double.infinity, height: 55, child: ElevatedButton(onPressed: _startUpdate, style: ElevatedButton.styleFrom(backgroundColor: Colors.amber), child: const Text("INITIALIZE UPDATE", style: TextStyle(fontWeight: FontWeight.bold)))),
            ],
          ),
        ),
      ),
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});
  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool? _isAuthorized;
  String? _lastUid;
  bool _isChecking = false;

  Future<void> _checkDevice(String uid) async {
    if (_isChecking) return;
    _isChecking = true;
    try {
      bool authorized = await AuthService().isDeviceAuthorized().timeout(const Duration(seconds: 10));
      if (mounted) setState(() { _isAuthorized = authorized; _isChecking = false; _lastUid = uid; });
    } catch (e) {
      if (mounted) setState(() { _isAuthorized = true; _isChecking = false; _lastUid = uid; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        final user = snapshot.data;
        if (snapshot.connectionState == ConnectionState.waiting && user == null) {
          return const Scaffold(body: Center(child: CircularProgressIndicator(color: Colors.amber)));
        }
        if (user != null) {
          if (_lastUid != user.uid || _isAuthorized == null) { _checkDevice(user.uid); return const Scaffold(body: Center(child: CircularProgressIndicator(color: Colors.amber))); }
          return _isAuthorized == true ? const SubjectListScreen() : const LoginScreen();
        }
        return const LoginScreen();
      },
    );
  }
}

class SubjectListScreen extends StatefulWidget {
  const SubjectListScreen({super.key});
  @override
  State<SubjectListScreen> createState() => _SubjectListScreenState();
}

class _SubjectListScreenState extends State<SubjectListScreen> {
  String? _selectedCategory;
  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid || Platform.isIOS) {
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    }
    AppRadarSyncService.instance.syncUserStatus();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: OTTColors.background,
      appBar: AppBar(
        title: const Text("DARK HORIZON", style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2, fontSize: 16)),
        backgroundColor: OTTColors.surface,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.download_for_offline_rounded, color: OTTColors.primary),
            tooltip: "Downloads",
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (c) => const DownloadsScreen())),
          ),
          const SizedBox(width: 8),
          const CircleAvatar(backgroundColor: OTTColors.primary, radius: 16, child: Icon(Icons.person, size: 20, color: Colors.black)),
          const SizedBox(width: 16),
        ],
      ),
      drawer: _buildModernDrawer(context),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('users').doc(user?.uid).snapshots(),
        builder: (context, userSnapshot) {
          if (userSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: OTTColors.primary));
          }
          final userData = userSnapshot.data?.data() as Map<String, dynamic>?;
          final List<dynamic> subjectsArray = userData?['subjects'] ?? [];

          String assignedCategory = userData?['assigned_category'] ?? userData?['branch'] ?? userData?['category'] ?? "EE3rdsem";
          if (assignedCategory.toLowerCase() == "all") assignedCategory = "EE3rdsem";
          
          final String studentName = userData?['name'] ?? 'Student';
          final bool isMasterAdmin = (userData?['role']?.toString().toLowerCase().contains('admin') ?? false) || (assignedCategory.toLowerCase() == "all");
          final String currentCategory = isMasterAdmin ? (_selectedCategory ?? assignedCategory) : assignedCategory;

          return ListView(
            padding: const EdgeInsets.only(bottom: 40),
            children: [
              // 1. Netflix Hero Spotlight Banner (Continue Watching)
              Container(
                margin: const EdgeInsets.all(20),
                height: 220,
                decoration: BoxDecoration(
                  color: OTTColors.card,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: OTTColors.cardBorder, width: 1.5),
                  boxShadow: [BoxShadow(color: OTTColors.primary.withValues(alpha: 0.1), blurRadius: 20)],
                ),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [OTTColors.surface, OTTColors.background],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                          ),
                          child: const Center(child: Icon(Icons.play_circle_filled_rounded, size: 64, color: OTTColors.primary)),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
                          gradient: LinearGradient(
                            colors: [Colors.transparent, Colors.black.withValues(alpha: 0.9)],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(color: OTTColors.primary, borderRadius: BorderRadius.circular(6)),
                                  child: const Text("TOP SEEN", style: TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.w900)),
                                ),
                                const SizedBox(width: 8),
                                const Text("Continue Learning", style: TextStyle(color: OTTColors.textSecondary, fontSize: 12, fontWeight: FontWeight.bold)),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text("Welcome back, $studentName 👋", style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                ElevatedButton.icon(
                                  onPressed: () {},
                                  style: ElevatedButton.styleFrom(backgroundColor: OTTColors.primary, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                                  label: const Text("Resume", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                ),
                                const SizedBox(width: 10),
                                OutlinedButton.icon(
                                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (c) => const DownloadsScreen())),
                                  style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: OTTColors.cardBorder), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                                  icon: const Icon(Icons.download_rounded, size: 18, color: OTTColors.primary),
                                  label: const Text("Downloads", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // 2. Branch / Category Selector Bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Trending Subjects", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white)),
                    _buildCategoryDropdown(currentCategory, isMasterAdmin),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // 3. Subject Grid (Netflix Poster Style)
              if (subjectsArray.isNotEmpty)
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    childAspectRatio: 0.75,
                  ),
                  itemCount: subjectsArray.length,
                  itemBuilder: (context, index) {
                    final item = subjectsArray[index];
                    String title = (item is Map) ? (item['name'] ?? "") : item.toString();
                    String category = (item is Map) ? (item['category'] ?? "") : "";
                    return _buildNetflixPosterCard(title, category);
                  },
                )
              else
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection('content').doc(currentCategory).collection('subjects').snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: OTTColors.primary));
                    final docs = snapshot.data!.docs;
                    return GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                        childAspectRatio: 0.75,
                      ),
                      itemCount: docs.length,
                      itemBuilder: (context, index) {
                        return _buildNetflixPosterCard(docs[index].id, currentCategory);
                      },
                    );
                  },
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildNetflixPosterCard(String title, String category) {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => UnitListScreen(subject: title, category: category))),
      child: Container(
        decoration: BoxDecoration(
          color: OTTColors.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: OTTColors.cardBorder, width: 1.2),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                child: Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [OTTColors.surface, OTTColors.card],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: const Center(
                    child: Icon(Icons.movie_filter_rounded, size: 48, color: OTTColors.primary),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: OTTColors.primary.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
                    child: const Text("COURSE", style: TextStyle(color: OTTColors.primary, fontSize: 9, fontWeight: FontWeight.w900)),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryDropdown(String currentVal, bool isAdmin) {
    if (!isAdmin) return Text("Branch: $currentVal", style: const TextStyle(color: OTTColors.primary, fontWeight: FontWeight.bold));
    return FutureBuilder<QuerySnapshot>(
      future: FirebaseFirestore.instance.collection('content').get(),
      builder: (context, snapshot) {
        Set<String> categorySet = {'EE3rdsem', 'EE5thsem', 'EL3rdsem', 'EL5thsem', 'CSE3rdsem', 'CSE5thsem'};
        if (snapshot.hasData) { for (var d in snapshot.data!.docs) { if (d.id != "all") categorySet.add(d.id); } }
        List<String> categories = categorySet.toList()..sort();
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: OTTColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: OTTColors.cardBorder),
          ),
          child: DropdownButton<String>(
            value: categories.contains(currentVal) ? currentVal : categories[0],
            dropdownColor: OTTColors.surface,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            underline: const SizedBox.shrink(),
            icon: const Icon(Icons.keyboard_arrow_down_rounded, color: OTTColors.primary),
            items: categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
            onChanged: (v) => setState(() => _selectedCategory = v),
          ),
        );
      },
    );
  }

  Widget _buildModernDrawer(BuildContext context) {
    return Drawer(
      backgroundColor: OTTColors.background,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(24, 60, 24, 30),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [OTTColors.primary, OTTColors.secondary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.bolt_rounded, color: Colors.black, size: 36),
                SizedBox(height: 12),
                Text("Dark Horizon", style: TextStyle(color: Colors.black, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                Text("Streaming & Learning Terminal", style: TextStyle(color: Colors.black87, fontSize: 11, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.done_all_rounded, color: OTTColors.primary),
            title: const Text("Downloads", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => const DownloadsScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.logout_rounded, color: Colors.redAccent),
            title: const Text("Sign Out", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            onTap: () => AuthService().signOut(),
          ),
        ],
      ),
    );
  }
}

class UnitListScreen extends StatefulWidget {
  final String subject;
  final String category;
  const UnitListScreen({super.key, required this.subject, required this.category});
  @override
  State<UnitListScreen> createState() => _UnitListScreenState();
}

class _UnitListScreenState extends State<UnitListScreen> {
  final ReceivePort _port = ReceivePort();
  final Map<String, int> _progress = {};
  final Map<String, DownloadTaskStatus> _status = {};
  String? _resolvedCategory;

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid || Platform.isIOS) _bindBackgroundIsolate();
    _autoResolveCategory();
  }

  Future<void> _autoResolveCategory() async {
    if (widget.category.isNotEmpty && widget.category != "all") { setState(() => _resolvedCategory = widget.category); return; }
    final pool = ['EE3rdsem', 'EE5thsem', 'EL3rdsem', 'EL5thsem', 'CSE3rdsem', 'CSE5thsem', 'Common'];
    for (String cat in pool) {
      final doc = await FirebaseFirestore.instance.collection('content').doc(cat).collection('subjects').doc(widget.subject).get();
      if (doc.exists) { if (mounted) setState(() => _resolvedCategory = cat); return; }
    }
    if (mounted) setState(() => _resolvedCategory = "EE3rdsem");
  }

  void _bindBackgroundIsolate() {
    IsolateNameServer.registerPortWithName(_port.sendPort, 'downloader_send_port');
    _port.listen((data) {
      if (mounted) setState(() { _progress[data[0]] = data[2]; _status[data[0]] = DownloadTaskStatus.fromInt(data[1]); });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_resolvedCategory == null) {
      return const Scaffold(
        backgroundColor: OTTColors.background,
        body: Center(child: CircularProgressIndicator(color: OTTColors.primary)),
      );
    }
    int crossAxisCount = (MediaQuery.of(context).size.width > 900) ? 4 : 2;

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(FirebaseAuth.instance.currentUser?.uid).snapshots(),
      builder: (context, userSnapshot) {
        final userData = userSnapshot.data?.data() as Map<String, dynamic>?;
        bool isOneShotOnly = (userData?['oneShotOnlySubjects'] ?? []).contains(widget.subject);

        return Scaffold(
          backgroundColor: OTTColors.background,
          appBar: AppBar(
            title: Text(widget.subject, style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.2)),
            backgroundColor: OTTColors.surface,
            elevation: 0,
          ),
          body: CustomScrollView(
            slivers: [
              // HOT One-Shot Spotlight Banner
              SliverToBoxAdapter(
                child: GestureDetector(
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => OneShotSeriesScreen(subject: widget.subject, category: _resolvedCategory!))),
                  child: Container(
                    margin: const EdgeInsets.all(20),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [OTTColors.accentCyan.withValues(alpha: 0.2), OTTColors.primary.withValues(alpha: 0.2)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: OTTColors.primary, width: 1.5),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: const BoxDecoration(color: OTTColors.primary, shape: BoxShape.circle),
                          child: const Icon(Icons.flash_on_rounded, color: Colors.black, size: 28),
                        ),
                        const SizedBox(width: 16),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("HOT ONE-SHOT SERIES", style: TextStyle(color: OTTColors.primary, fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 1.5)),
                              SizedBox(height: 4),
                              Text("Complete 1-shot unit revisions & marathon lectures", style: TextStyle(color: OTTColors.textSecondary, fontSize: 12)),
                            ],
                          ),
                        ),
                        const Icon(Icons.arrow_forward_ios_rounded, color: OTTColors.primary, size: 16),
                      ],
                    ),
                  ),
                ),
              ),

              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  child: Text("Available Units", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white)),
                ),
              ),

              if (!isOneShotOnly)
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection('content').doc(_resolvedCategory).collection('subjects').doc(widget.subject).collection('units').snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const SliverFillRemaining(child: Center(child: CircularProgressIndicator(color: OTTColors.primary)));
                    }
                    final docs = snapshot.data!.docs;
                    return SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      sliver: SliverGrid(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                          childAspectRatio: 1.4,
                        ),
                        delegate: SliverChildBuilderDelegate((context, i) => _buildUnitCard(docs[i].id, i + 1), childCount: docs.length),
                      ),
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildUnitCard(String title, int index) {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => ContentListScreen(category: _resolvedCategory!, subject: widget.subject, unit: title))),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: OTTColors.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: OTTColors.cardBorder, width: 1.2),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 4))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: OTTColors.primary.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                  child: Text("UNIT 0$index", style: const TextStyle(color: OTTColors.primary, fontSize: 10, fontWeight: FontWeight.w900)),
                ),
                const Spacer(),
                const Icon(Icons.arrow_forward_ios_rounded, color: OTTColors.textSecondary, size: 14),
              ],
            ),
            const Spacer(),
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class OneShotSeriesScreen extends StatefulWidget {
  final String subject;
  final String category;
  const OneShotSeriesScreen({super.key, required this.subject, required this.category});
  @override
  State<OneShotSeriesScreen> createState() => _OneShotSeriesScreenState();
}

class _OneShotSeriesScreenState extends State<OneShotSeriesScreen> {
  bool _showNotes = false;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OTTColors.background,
      appBar: AppBar(title: Text("${widget.subject} One-Shot", style: const TextStyle(fontWeight: FontWeight.bold))),
      body: Column(
        children: [
          const SizedBox(height: 8),
          _buildSegmentToggle(),
          const SizedBox(height: 12),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('content').doc(widget.category).collection('subjects').doc(widget.subject).collection('one_shots').snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: OTTColors.primary));
                final units = snapshot.data!.docs;
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: units.length,
                  itemBuilder: (context, index) => _buildUnitSection(units[index]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentToggle() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: OTTColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: OTTColors.cardBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _showNotes = false),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: !_showNotes ? OTTColors.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text("LECTURES", textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: !_showNotes ? Colors.black : OTTColors.textSecondary)),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _showNotes = true),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: _showNotes ? OTTColors.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text("NOTES", textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: _showNotes ? Colors.black : OTTColors.textSecondary)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUnitSection(QueryDocumentSnapshot unitDoc) {
    String path = _showNotes ? "notes" : "parts";
    return StreamBuilder<QuerySnapshot>(
      stream: unitDoc.reference.collection(path).snapshots(),
      builder: (context, sub) {
        if (!sub.hasData) return const SizedBox.shrink();
        return Column(
          children: sub.data!.docs.map((item) {
            final data = item.data() as Map<String, dynamic>;
            final url = AuthService.decryptLink(data[_showNotes ? 'fileUrl' : 'videoUrl'] ?? "");
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: OTTColors.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: OTTColors.cardBorder),
              ),
              child: ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: OTTColors.primary.withValues(alpha: 0.12), shape: BoxShape.circle),
                  child: Icon(_showNotes ? Icons.description_rounded : Icons.play_circle_fill_rounded, color: OTTColors.primary, size: 22),
                ),
                title: Text(item.id, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white)),
                trailing: IconButton(
                  icon: const Icon(Icons.download_rounded, color: OTTColors.primary, size: 20),
                  tooltip: "Download",
                  onPressed: () => _startDownload(url, item.id, _showNotes, widget.subject, "One-Shot"),
                ),
                onTap: () {
                  if (_showNotes) {
                    Navigator.push(context, MaterialPageRoute(builder: (c) => AppPdfViewer(pdfUrl: url, noteTitle: item.id)));
                  } else {
                    Navigator.push(context, MaterialPageRoute(builder: (c) => MXStylePlayer(url: url, title: item.id, subjectCode: widget.subject, unitName: "One-Shot", category: widget.category)));
                  }
                },
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Future<void> _startDownload(String url, String title, bool isPdf, String subject, String unit) async {
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Invalid download URL!")));
      return;
    }
    try {
      int totalBytes = 0;
      try {
        final response = await http.head(Uri.parse(url));
        if (response.headers.containsKey('content-length')) {
          totalBytes = int.tryParse(response.headers['content-length'] ?? '0') ?? 0;
        }
      } catch (_) {}

      final directory = await getApplicationDocumentsDirectory();
      final ext = isPdf ? '.pdf' : '.mp4';
      final sanitizedTitle = title.replaceAll(RegExp(r'[^\w\s]+'), '').replaceAll(' ', '_');
      final fileName = '$sanitizedTitle$ext';
      
      final taskId = await FlutterDownloader.enqueue(
        url: url,
        savedDir: directory.path,
        fileName: fileName,
        showNotification: true,
        openFileFromNotification: false,
      );

      if (taskId != null) {
        await DownloadManager.addDownload(DownloadItemMeta(
          taskId: taskId,
          subject: subject,
          unit: unit,
          title: title,
          url: url,
          isPdf: isPdf,
          fileName: fileName,
          totalBytes: totalBytes,
        ));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Download started: $title")));
          setState(() {});
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Download failed: $e")));
      }
    }
  }
}

class ContentListScreen extends StatefulWidget {
  final String category;
  final String subject;
  final String unit;
  const ContentListScreen({super.key, required this.category, required this.subject, required this.unit});
  @override
  State<ContentListScreen> createState() => _ContentListScreenState();
}

class _ContentListScreenState extends State<ContentListScreen> {
  bool _showNotes = false;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OTTColors.background,
      appBar: AppBar(title: Text(widget.unit, style: const TextStyle(fontWeight: FontWeight.bold))),
      body: Column(
        children: [
          const SizedBox(height: 8),
          _buildSegmentToggle(),
          const SizedBox(height: 12),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('content').doc(widget.category).collection('subjects').doc(widget.subject).collection('units').doc(widget.unit).collection(_showNotes ? 'notes' : 'lectures').snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: OTTColors.primary));
                final docs = snapshot.data!.docs;
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = docs[index].data() as Map<String, dynamic>;
                    final url = AuthService.decryptLink(data[_showNotes ? 'fileUrl' : 'videoUrl'] ?? "");
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: OTTColors.card,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: OTTColors.cardBorder),
                      ),
                      child: ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(color: OTTColors.primary.withValues(alpha: 0.12), shape: BoxShape.circle),
                          child: Icon(_showNotes ? Icons.description_rounded : Icons.play_circle_fill_rounded, color: OTTColors.primary, size: 22),
                        ),
                        title: Text(data['title'] ?? docs[index].id, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white)),
                        trailing: IconButton(
                          icon: const Icon(Icons.download_rounded, color: OTTColors.primary, size: 20),
                          tooltip: "Download",
                          onPressed: () => _startDownload(url, data['title'] ?? docs[index].id, _showNotes, widget.subject, widget.unit),
                        ),
                        onTap: () {
                          if (_showNotes) {
                            Navigator.push(context, MaterialPageRoute(builder: (c) => AppPdfViewer(pdfUrl: url, noteTitle: docs[index].id)));
                          } else {
                            Navigator.push(context, MaterialPageRoute(builder: (c) => MXStylePlayer(url: url, title: docs[index].id, subjectCode: widget.subject, unitName: widget.unit, category: widget.category)));
                          }
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentToggle() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: OTTColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: OTTColors.cardBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _showNotes = false),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: !_showNotes ? OTTColors.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text("LECTURES", textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: !_showNotes ? Colors.black : OTTColors.textSecondary)),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _showNotes = true),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: _showNotes ? OTTColors.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text("NOTES", textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: _showNotes ? Colors.black : OTTColors.textSecondary)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _startDownload(String url, String title, bool isPdf, String subject, String unit) async {
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Invalid download URL!")));
      return;
    }
    try {
      int totalBytes = 0;
      try {
        final response = await http.head(Uri.parse(url));
        if (response.headers.containsKey('content-length')) {
          totalBytes = int.tryParse(response.headers['content-length'] ?? '0') ?? 0;
        }
      } catch (_) {}

      final directory = await getApplicationDocumentsDirectory();
      final ext = isPdf ? '.pdf' : '.mp4';
      final sanitizedTitle = title.replaceAll(RegExp(r'[^\w\s]+'), '').replaceAll(' ', '_');
      final fileName = '$sanitizedTitle$ext';
      
      final taskId = await FlutterDownloader.enqueue(
        url: url,
        savedDir: directory.path,
        fileName: fileName,
        showNotification: true,
        openFileFromNotification: false,
      );

      if (taskId != null) {
        await DownloadManager.addDownload(DownloadItemMeta(
          taskId: taskId,
          subject: subject,
          unit: unit,
          title: title,
          url: url,
          isPdf: isPdf,
          fileName: fileName,
          totalBytes: totalBytes,
        ));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Download started: $title")));
          setState(() {});
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Download failed: $e")));
      }
    }
  }
}

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  List<DownloadItemMeta> _downloads = [];
  List<DownloadTask> _tasks = [];
  bool _isLoading = true;
  final ReceivePort _port = ReceivePort();
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _initDownloads();
    if (Platform.isAndroid || Platform.isIOS) {
      try {
        if (IsolateNameServer.lookupPortByName('downloader_send_port') != null) {
          IsolateNameServer.removePortNameMapping('downloader_send_port');
        }
        IsolateNameServer.registerPortWithName(_port.sendPort, 'downloader_send_port');
      } catch (_) {}

      _port.listen((dynamic data) async {
        if (data is List) {
          await _initDownloads();
        }
      });
    }

    _refreshTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (mounted) {
        _initDownloads();
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    IsolateNameServer.removePortNameMapping('downloader_send_port');
    _port.close();
    super.dispose();
  }

  Future<void> _initDownloads() async {
    final downloads = await DownloadManager.getDownloads();
    final tasks = await FlutterDownloader.loadTasks() ?? [];
    final dir = await getApplicationDocumentsDirectory();
    for (var item in downloads) {
      final file = File('${dir.path}/${item.fileName}');
      item.fileExists = await file.exists();
    }
    if (mounted) {
      setState(() {
        _downloads = downloads;
        _tasks = tasks;
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteDownload(DownloadItemMeta meta) async {
    try {
      final tasks = await FlutterDownloader.loadTasks() ?? [];
      for (var task in tasks) {
        if (task.taskId == meta.taskId) {
          await FlutterDownloader.remove(taskId: task.taskId, shouldDeleteContent: true);
        }
      }
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/${meta.fileName}');
      if (await file.exists()) {
        await file.delete();
      }
      await DownloadManager.removeDownload(meta.taskId);
      await _initDownloads();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Download removed")));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to delete: $e")));
      }
    }
  }

  Future<void> _pauseDownload(String taskId) async {
    await FlutterDownloader.pause(taskId: taskId);
    await _initDownloads();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Download paused"), duration: Duration(milliseconds: 800)));
    }
  }

  Future<void> _resumeDownload(DownloadItemMeta item) async {
    try {
      final newTaskId = await FlutterDownloader.resume(taskId: item.taskId);
      if (newTaskId != null) {
        await DownloadManager.updateTaskId(item.taskId, newTaskId);
      } else {
        await _reEnqueueDownload(item);
      }
    } catch (_) {
      await _reEnqueueDownload(item);
    }
    await _initDownloads();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Resuming download..."), duration: Duration(milliseconds: 800)));
    }
  }

  Future<void> _retryDownload(DownloadItemMeta item) async {
    try {
      final newTaskId = await FlutterDownloader.retry(taskId: item.taskId);
      if (newTaskId != null) {
        await DownloadManager.updateTaskId(item.taskId, newTaskId);
      } else {
        await _reEnqueueDownload(item);
      }
    } catch (_) {
      await _reEnqueueDownload(item);
    }
    await _initDownloads();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Retrying download..."), duration: Duration(milliseconds: 800)));
    }
  }

  Future<void> _reEnqueueDownload(DownloadItemMeta item) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final newTaskId = await FlutterDownloader.enqueue(
        url: item.url,
        savedDir: dir.path,
        fileName: item.fileName,
        showNotification: true,
        openFileFromNotification: false,
      );
      if (newTaskId != null) {
        await DownloadManager.updateTaskId(item.taskId, newTaskId);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    Map<String, List<DownloadItemMeta>> subjectMap = {};
    for (var item in _downloads) {
      subjectMap.putIfAbsent(item.subject, () => []);
      subjectMap[item.subject]!.add(item);
    }

    return Scaffold(
      backgroundColor: OTTColors.background,
      appBar: AppBar(
        title: const Text("My Offline Downloads", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: OTTColors.surface,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: OTTColors.primary))
          : _downloads.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(color: OTTColors.surface, shape: BoxShape.circle, border: Border.all(color: OTTColors.cardBorder)),
                          child: const Icon(Icons.download_for_offline_rounded, size: 48, color: OTTColors.primary),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          "No offline downloads found.\nDownloaded lectures and notes are organized securely here.",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: OTTColors.textSecondary, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // DH Offline Vault Header Banner
                    Container(
                      margin: const EdgeInsets.only(bottom: 20),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: OTTColors.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: OTTColors.cardBorder),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: OTTColors.primary.withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.download_for_offline_rounded, color: OTTColors.primary, size: 28),
                          ),
                          const SizedBox(width: 16),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("DH OFFLINE VAULT", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 1.2)),
                                SizedBox(height: 4),
                                Text("Select a subject to view downloaded content", style: TextStyle(color: OTTColors.textSecondary, fontSize: 12)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    ...subjectMap.entries.map((entry) {
                      String subject = entry.key;
                      List<DownloadItemMeta> items = entry.value;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 14),
                        decoration: BoxDecoration(
                          color: OTTColors.card,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: OTTColors.cardBorder, width: 1.2),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          leading: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(color: OTTColors.primary.withValues(alpha: 0.15), shape: BoxShape.circle),
                            child: const Icon(Icons.movie_filter_rounded, color: OTTColors.primary, size: 24),
                          ),
                          title: Text(subject, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Colors.white)),
                          subtitle: Text("${items.length} items downloaded", style: const TextStyle(color: OTTColors.textSecondary, fontSize: 12)),
                          trailing: const Icon(Icons.arrow_forward_ios_rounded, color: OTTColors.primary, size: 16),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (c) => SubjectDownloadsDetailScreen(
                                  subject: subject,
                                  items: items,
                                  tasks: _tasks,
                                  onDelete: (meta) => _deleteDownload(meta),
                                  onResume: (meta) => _resumeDownload(meta),
                                  onRetry: (meta) => _retryDownload(meta),
                                  onPause: (taskId) => _pauseDownload(taskId),
                                  onRefresh: () => _initDownloads(),
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    }),
                  ],
                ),
    );
  }
}

class SubjectDownloadsDetailScreen extends StatefulWidget {
  final String subject;
  final List<DownloadItemMeta> items;
  final List<DownloadTask> tasks;
  final Function(DownloadItemMeta) onDelete;
  final Function(DownloadItemMeta) onResume;
  final Function(DownloadItemMeta) onRetry;
  final Function(String) onPause;
  final VoidCallback? onRefresh;

  const SubjectDownloadsDetailScreen({
    super.key,
    required this.subject,
    required this.items,
    required this.tasks,
    required this.onDelete,
    required this.onResume,
    required this.onRetry,
    required this.onPause,
    this.onRefresh,
  });

  @override
  State<SubjectDownloadsDetailScreen> createState() => _SubjectDownloadsDetailScreenState();
}

class _SubjectDownloadsDetailScreenState extends State<SubjectDownloadsDetailScreen> {
  @override
  Widget build(BuildContext context) {
    Map<String, List<DownloadItemMeta>> unitMap = {};
    for (var item in widget.items) {
      unitMap.putIfAbsent(item.unit, () => []);
      unitMap[item.unit]!.add(item);
    }

    return Scaffold(
      backgroundColor: OTTColors.background,
      appBar: AppBar(
        title: Text(widget.subject, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: OTTColors.surface,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: OTTColors.primary),
            tooltip: "Refresh Downloads",
            onPressed: () {
              widget.onRefresh?.call();
              setState(() {});
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Refreshed downloads"), duration: Duration(milliseconds: 600)));
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: unitMap.entries.map((unitEntry) {
          String unit = unitEntry.key;
          List<DownloadItemMeta> unitItems = unitEntry.value;
          return Container(
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: OTTColors.card,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: OTTColors.cardBorder, width: 1.2),
            ),
            child: ExpansionTile(
              initiallyExpanded: true,
              iconColor: OTTColors.primary,
              collapsedIconColor: OTTColors.textSecondary,
              title: Text(unit, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: OTTColors.primary)),
              subtitle: Text("${unitItems.length} items", style: const TextStyle(color: OTTColors.textSecondary, fontSize: 12)),
              children: unitItems.map((item) {
                DownloadTask? task;
                try {
                  task = widget.tasks.firstWhere((t) => t.taskId == item.taskId);
                } catch (_) {}

                int progress = task?.progress ?? (item.fileExists ? 100 : 0);
                DownloadTaskStatus status = task?.status ?? (item.fileExists ? DownloadTaskStatus.complete : DownloadTaskStatus.failed);

                String mbText = "";
                if (item.totalBytes > 0) {
                  double totalMB = item.totalBytes / (1024 * 1024);
                  double downloadedMB = (progress / 100.0) * totalMB;
                  mbText = "${downloadedMB.toStringAsFixed(1)} MB / ${totalMB.toStringAsFixed(1)} MB ($progress%)";
                } else {
                  mbText = "$progress%";
                }

                String statusText = "Ready to Watch";
                if (status == DownloadTaskStatus.running) {
                  statusText = "Downloading ($progress%)...";
                } else if (status == DownloadTaskStatus.paused) {
                  statusText = "Paused";
                } else if (status == DownloadTaskStatus.failed) {
                  statusText = "Failed";
                }

                bool isComplete = status == DownloadTaskStatus.complete;

                return Container(
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: OTTColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: OTTColors.cardBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          InkWell(
                            onTap: (progress > 0 || isComplete) ? () async {
                              final dir = await getApplicationDocumentsDirectory();
                              final filePath = '${dir.path}/${item.fileName}';
                              if (context.mounted) {
                                if (item.isPdf) {
                                  Navigator.push(context, MaterialPageRoute(builder: (c) => AppPdfViewer(pdfUrl: filePath, noteTitle: item.title)));
                                } else {
                                  Navigator.push(context, MaterialPageRoute(builder: (c) => MXStylePlayer(url: filePath, title: item.title, subjectCode: item.subject, unitName: item.unit, category: "offline")));
                                }
                              }
                            } : null,
                            borderRadius: BorderRadius.circular(30),
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: OTTColors.primary.withValues(alpha: 0.12),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                item.isPdf ? Icons.description_rounded : Icons.play_circle_fill_rounded,
                                color: OTTColors.primary,
                                size: 22,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.title,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  item.isPdf ? "PDF Document" : "Video Lecture",
                                  style: const TextStyle(color: OTTColors.textSecondary, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          if (isComplete)
                            IconButton(
                              icon: const Icon(Icons.play_arrow_rounded, color: OTTColors.primary, size: 22),
                              tooltip: item.isPdf ? "View" : "Play",
                              onPressed: () async {
                                final dir = await getApplicationDocumentsDirectory();
                                final filePath = '${dir.path}/${item.fileName}';
                                if (context.mounted) {
                                  if (item.isPdf) {
                                    Navigator.push(context, MaterialPageRoute(builder: (c) => AppPdfViewer(pdfUrl: filePath, noteTitle: item.title)));
                                  } else {
                                    Navigator.push(context, MaterialPageRoute(builder: (c) => MXStylePlayer(url: filePath, title: item.title, subjectCode: item.subject, unitName: item.unit, category: "offline")));
                                  }
                                }
                              },
                            )
                          else ...[
                            if (status == DownloadTaskStatus.running)
                              IconButton(
                                icon: const Icon(Icons.pause_rounded, color: OTTColors.primary, size: 22),
                                tooltip: "Pause",
                                onPressed: () => widget.onPause(item.taskId),
                              )
                            else if (status == DownloadTaskStatus.paused)
                              IconButton(
                                icon: const Icon(Icons.play_arrow_rounded, color: OTTColors.primary, size: 22),
                                tooltip: "Resume",
                                onPressed: () => widget.onResume(item),
                              )
                            else if (status == DownloadTaskStatus.failed)
                              IconButton(
                                icon: const Icon(Icons.refresh_rounded, color: OTTColors.primary, size: 22),
                                tooltip: "Retry",
                                onPressed: () => widget.onRetry(item),
                              ),
                          ],
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                            tooltip: "Delete",
                            onPressed: () => widget.onDelete(item),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: progress > 0 ? progress / 100.0 : 0.0,
                          color: OTTColors.primary,
                          backgroundColor: OTTColors.card,
                          minHeight: 8,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            statusText,
                            style: TextStyle(
                              color: isComplete ? Colors.greenAccent : OTTColors.primary,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            mbText,
                            style: const TextStyle(
                              color: OTTColors.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          );
        }).toList(),
      ),
    );
  }
}


class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  void _login() async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) return;
    setState(() => _isLoading = true);
    String? result = await AuthService().signIn(email: _emailController.text.trim(), password: _passwordController.text.trim());
    if (!mounted) return;
    setState(() => _isLoading = false);
    if (result != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result == "DEVICE_MISMATCH" ? "Locked to another device!" : result), backgroundColor: Colors.redAccent));
    }
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OTTColors.background,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28.0),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420),
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: OTTColors.surface,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: OTTColors.cardBorder, width: 1.2),
              boxShadow: [
                BoxShadow(color: OTTColors.primary.withValues(alpha: 0.08), blurRadius: 40, spreadRadius: 4),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: OTTColors.primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    border: Border.all(color: OTTColors.cardBorder),
                  ),
                  child: const Icon(Icons.bolt_rounded, size: 48, color: OTTColors.primary),
                ),
                const SizedBox(height: 20),
                const Text(
                  "DARK HORIZON",
                  style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 4),
                ),
                const SizedBox(height: 8),
                const Text(
                  "STREAMING & LEARNING TERMINAL",
                  style: TextStyle(color: OTTColors.textSecondary, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.5),
                ),
                const SizedBox(height: 40),
                TextField(
                  controller: _emailController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: "Student Email",
                    labelStyle: const TextStyle(color: OTTColors.textSecondary),
                    filled: true,
                    fillColor: OTTColors.card,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: OTTColors.cardBorder)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: OTTColors.cardBorder)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: OTTColors.primary)),
                    prefixIcon: const Icon(Icons.alternate_email_rounded, color: OTTColors.primary),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: "Security Key",
                    labelStyle: const TextStyle(color: OTTColors.textSecondary),
                    filled: true,
                    fillColor: OTTColors.card,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: OTTColors.cardBorder)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: OTTColors.cardBorder)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: OTTColors.primary)),
                    prefixIcon: const Icon(Icons.vpn_key_rounded, color: OTTColors.primary),
                  ),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _login,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: OTTColors.primary,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 8,
                      shadowColor: OTTColors.primary.withValues(alpha: 0.4),
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.black)
                        : const Text("SIGN IN", style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
