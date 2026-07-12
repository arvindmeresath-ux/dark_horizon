import 'dart:isolate';
import 'dart:ui';
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart';
import 'custom_video_player.dart';
import 'auth_service.dart';
import 'connectivity_wrapper.dart';
import 'pdf_viewer_screen.dart';

@pragma('vm:entry-point')
void downloadCallback(String id, int status, int progress) {
  final SendPort? send = IsolateNameServer.lookupPortByName('downloader_send_port');
  send?.send([id, status, progress]);
}

// 1. GLOBAL THEME NOTIFIER
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.dark);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  
  // Enforce background service initialization for Android
  await FlutterDownloader.initialize(
    debug: false, // Disabling debug in main ensures cleaner background thread detachment
    ignoreSsl: true,
  );
  FlutterDownloader.registerCallback(downloadCallback);

  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    // 2. WRAP MATERIALAPP TO LISTEN THEME CHANGES
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (_, ThemeMode currentMode, __) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Dark Horizon',
          theme: ThemeData(
            brightness: Brightness.light,
            scaffoldBackgroundColor: const Color(0xFFF5F5F5),
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.amber, brightness: Brightness.light, primary: Colors.amber),
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            scaffoldBackgroundColor: const Color(0xFF000814),
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.amber, brightness: Brightness.dark, primary: Colors.amber),
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

      final updateConf = await FirebaseFirestore.instance.collection('app_settings').doc('update_config').get();
      int latestVersion = updateConf.data()?['latest_version'] ?? 1;
      String downloadUrl = updateConf.data()?['download_url'] ?? "";
      const int currentVersion = 1;

      if (!mounted) return;
      setState(() {
        _isMaintenance = maintenance;
        _needsUpdate = latestVersion > currentVersion;
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
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: Colors.amber)));
    }
    if (_isMaintenance) {
      return const MaintenanceScreen();
    }
    if (_needsUpdate) {
      return UpdateDialog(downloadUrl: _updateUrl);
    }
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
    if (IsolateNameServer.lookupPortByName('downloader_send_port') != null) {
      IsolateNameServer.removePortNameMapping('downloader_send_port');
    }
    IsolateNameServer.registerPortWithName(_port.sendPort, 'downloader_send_port');

    _port.listen((dynamic data) {
      if (data is List) {
        int status = data[1];
        int progress = data[2];
        if (mounted) {
          setState(() {
            _progress = progress / 100;
            if (_progress < 0) _progress = 0;
          });
        }
        if (status == 3) {
          _installApk();
        }
        if (status == 4) {
          if (!mounted) return;
          setState(() => _isDownloading = false);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Download Failed!")));
        }
      }
    });
  }

  Future<void> _startUpdate() async {
    if (Platform.isAndroid) {
      await Permission.notification.request();
      if (!await Permission.requestInstallPackages.isGranted) {
        await Permission.requestInstallPackages.request();
      }
    }
    if (!mounted) return;
    setState(() => _isDownloading = true);
    final directory = await getApplicationSupportDirectory();
    const String fileName = "Update.apk";
    final file = File("${directory.path}/$fileName");
    if (await file.exists()) await file.delete();
    await FlutterDownloader.enqueue(url: widget.downloadUrl, savedDir: directory.path, fileName: fileName, showNotification: true, openFileFromNotification: false, saveInPublicStorage: false);
  }

  Future<void> _installApk() async {
    final directory = await getApplicationSupportDirectory();
    final path = "${directory.path}/Update.apk";
    await OpenFilex.open(path);
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
            boxShadow: [BoxShadow(color: Colors.amber.withValues(alpha: 0.05), blurRadius: 40, spreadRadius: 10)],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.1), shape: BoxShape.circle), child: const Icon(Icons.auto_awesome_rounded, size: 50, color: Colors.amber)),
              const SizedBox(height: 24),
              const Text("UPGRADE AVAILABLE", style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
              const SizedBox(height: 12),
              Text(_isDownloading ? "OPTIMIZING SYSTEM FILES..." : "A more powerful version is ready.", textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 14, height: 1.5)),
              const SizedBox(height: 32),
              if (_isDownloading)
                Column(children: [LinearProgressIndicator(value: _progress, minHeight: 12, color: Colors.amber, backgroundColor: Colors.amber.withValues(alpha: 0.1)), const SizedBox(height: 16), Text("${(_progress * 100).toInt()}% COMPLETED", style: const TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.bold))])
              else
                SizedBox(width: double.infinity, height: 55, child: ElevatedButton(onPressed: _startUpdate, style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))), child: const Text("INITIALIZE UPDATE", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)))),
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
    bool authorized = await AuthService().isDeviceAuthorized();
    if (!mounted) return;
    setState(() { _isAuthorized = authorized; _isChecking = false; _lastUid = uid; });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        final user = snapshot.data;
        if (snapshot.connectionState == ConnectionState.waiting && user == null) return const Scaffold(body: Center(child: CircularProgressIndicator(color: Colors.amber)));
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
  String? _selectedCategory; // Master Admin ke liye dynamic selection

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      appBar: AppBar(
        title: const Text("Dark Horizon", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2)),
        backgroundColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.amber),
        actions: const [
          CircleAvatar(backgroundColor: Colors.amber, radius: 15, child: Icon(Icons.person, size: 18, color: Colors.black)),
          SizedBox(width: 16)
        ],
      ),
      drawer: _buildModernDrawer(context, user),
      body: _buildStudentSubjectGrid(user),
    );
  }

  Widget _buildStudentSubjectGrid(User? user) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(user?.uid).snapshots(),
      builder: (context, userSnapshot) {
        if (userSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Colors.amber));
        }

        final userData = userSnapshot.data?.data() as Map<String, dynamic>?;

        // Priority: 'assigned_category', then 'branch', then 'category', then 'section'
        final String assignedCategory = userData?['assigned_category'] ??
            userData?['branch'] ??
            userData?['category'] ??
            userData?['section'] ?? "";

        final String studentName = userData?['name'] ?? 'Student';
        final bool isMasterAdmin = userData?['role'] == 'admin';

        // LOGIC:
        // 1. Students are LOCKED to their 'assignedCategory'. No fallback to dropdown.
        // 2. Admins use '_selectedCategory' if set, otherwise fallback to their 'assignedCategory' or "EE3rdsem".
        final String currentCategory = isMasterAdmin
            ? (_selectedCategory ?? (assignedCategory.isNotEmpty ? assignedCategory : "EE3rdsem"))
            : assignedCategory;

        return CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Welcome, $studentName 👋", style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 12),

                    // --- CATEGORY SELECTION ---
                    _buildCategoryDropdown(currentCategory, isMasterAdmin),
                  ],
                ),
              ),
            ),
            if (currentCategory.isEmpty)
              const SliverFillRemaining(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.all(32.0),
                    child: Text(
                      "Branch not assigned.\nPlease contact administrator to get access to your subjects.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white60, fontSize: 14),
                    ),
                  ),
                ),
              )
            else
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('content').doc(currentCategory).collection('subjects').snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const SliverFillRemaining(child: Center(child: CircularProgressIndicator(color: Colors.amber)));
                  final docs = snapshot.data!.docs;
                  if (docs.isEmpty) return const SliverFillRemaining(child: Center(child: Text("No subjects available for this category.", style: TextStyle(color: Colors.white24))));

                  return SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    sliver: SliverGrid(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 16, mainAxisSpacing: 16, childAspectRatio: 0.85),
                      delegate: SliverChildBuilderDelegate((context, index) {
                        String title = docs[index].id;
                        return GestureDetector(
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => UnitListScreen(subject: title, category: currentCategory))),
                          child: Container(
                            decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.white10)),
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(width: 40, height: 40, decoration: const BoxDecoration(color: Colors.amber, shape: BoxShape.circle), child: const Icon(Icons.menu_book_rounded, color: Colors.black, size: 20)),
                                const Spacer(),
                                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), maxLines: 2, overflow: TextOverflow.ellipsis)
                              ],
                            ),
                          ),
                        );
                      }, childCount: docs.length),
                    ),
                  );
                },
              ),
          ],
        );
      },
    );
  }

  // 2. Category Selection (Admin & Student)
  Widget _buildCategoryDropdown(String currentVal, bool isAdmin) {
    if (!isAdmin) {
      return Container(
        width: 220,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
            color: Colors.amber.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.amber.withValues(alpha: 0.2))
        ),
        child: Row(
          children: [
            const Icon(Icons.school_rounded, color: Colors.amber, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text("ASSIGNED BRANCH", style: TextStyle(color: Colors.amber, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                  Text(currentVal, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14), overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final List<String> categories = ['EE3rdsem', 'EE5thsem', 'EL3rdsem', 'EL5thsem', 'CSE3rdsem', 'CSE5thsem'];
    return Container(
      width: 220,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.amber.withValues(alpha: 0.2))),
      child: DropdownButtonHideUnderline(
        child: DropdownButtonFormField<String>(
          initialValue: categories.contains(currentVal) ? currentVal : categories[0],
          dropdownColor: const Color(0xFF000814),
          icon: const Icon(Icons.admin_panel_settings, color: Colors.amber, size: 18),
          decoration: const InputDecoration(
              border: InputBorder.none,
              labelText: "ADMIN - SELECT BRANCH",
              labelStyle: TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.bold)
          ),
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
          items: categories.map((cat) => DropdownMenuItem(value: cat, child: Text(cat))).toList(),
          onChanged: (val) {
            setState(() => _selectedCategory = val);
          },
        ),
      ),
    );
  }

  Widget _buildModernDrawer(BuildContext context, User? user) {
    return Drawer(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.only(topRight: Radius.circular(32), bottomRight: Radius.circular(32))),
      child: Column(
        children: [
          Container(width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40), color: Colors.amber, child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(Icons.bolt, color: Colors.black, size: 40), SizedBox(height: 12), Text("Dark Horizon", style: TextStyle(color: Colors.black, fontSize: 22, fontWeight: FontWeight.w900))])),
          const SizedBox(height: 20),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                ListTile(leading: const Icon(Icons.done_all_rounded, color: Colors.amber), title: const Text("Downloads"), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => const DownloadsScreen()))),
                // 3. DARK MODE TOGGLE LOGIC
                ValueListenableBuilder<ThemeMode>(
                  valueListenable: themeNotifier,
                  builder: (context, currentMode, _) {
                    bool isDark = currentMode == ThemeMode.dark;
                    return ListTile(
                      leading: Icon(isDark ? Icons.nightlight_round : Icons.wb_sunny_outlined, color: Colors.amber),
                      title: const Text("Dark Mode"),
                      trailing: Switch(
                        value: isDark,
                        onChanged: (v) => themeNotifier.value = v ? ThemeMode.dark : ThemeMode.light,
                        activeThumbColor: Colors.amber,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          Padding(padding: const EdgeInsets.all(24), child: InkWell(onTap: () => AuthService().signOut(), child: const Row(children: [Icon(Icons.logout_rounded, color: Colors.redAccent), SizedBox(width: 15), Expanded(child: Text("Sign Out", style: TextStyle(fontWeight: FontWeight.bold)))]))),
          const SizedBox(height: 10),
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
  final Map<String, String> _sizes = {};
  final Set<String> _loadingUnits = {};

  Future<String> _fetchSize(String url) async {
    if (url.isEmpty || url.contains("youtube.com") || url.contains("youtu.be")) return "Stream Only";
    try {
      final headResponse = await http.head(Uri.parse(url)).timeout(const Duration(seconds: 3));
      if (headResponse.headers.containsKey('content-length')) {
        return "${(double.parse(headResponse.headers['content-length']!) / (1024 * 1024)).toStringAsFixed(1)} MB";
      }
      final response = await http.get(Uri.parse(url), headers: {"Range": "bytes=0-0"}).timeout(const Duration(seconds: 3));
      if (response.headers.containsKey('content-range')) {
        double totalBytes = double.parse(response.headers['content-range']!.split('/').last);
        return "${(totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB";
      }
      return "Size Unknown";
    } catch (_) { return "Size Unknown"; }
  }

  Future<void> _loadUnitSizes(String unitId, List<QueryDocumentSnapshot> parts) async {
    setState(() => _loadingUnits.add(unitId));
    for (var part in parts) {
      var data = part.data() as Map<String, dynamic>;
      String decUrl = AuthService.decryptLink(data['videoUrl'] ?? "");
      if (decUrl.isNotEmpty && !_sizes.containsKey(decUrl)) {
        String size = await _fetchSize(decUrl);
        if (mounted) setState(() => _sizes[decUrl] = size);
      }
    }
    if (mounted) setState(() => _loadingUnits.remove(unitId));
  }

  Future<void> _startDownload(String url, String title, bool isNotes, String sub, String unit) async {
    if (url.isEmpty) return;
    if (Platform.isAndroid) await Permission.notification.request();
    final directory = await getApplicationDocumentsDirectory();
    final String fileName = "${sub}__${unit}__${title.replaceAll(' ', '_')}${isNotes ? ".pdf" : ".mp4"}";
    await FlutterDownloader.enqueue(
      url: url, 
      savedDir: directory.path, 
      fileName: fileName, 
      showNotification: true, 
      openFileFromNotification: false, 
      saveInPublicStorage: false,
      allowCellular: true,
    );
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("One-Shot Download Started...")),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.subject), backgroundColor: Colors.transparent),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('content').doc(widget.category).collection('subjects').doc(widget.subject).collection('one_shots').snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(padding: EdgeInsets.all(16), child: Text("ONE-SHOT SERIES", style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, letterSpacing: 1.2))),
                    ...snapshot.data!.docs.map((unitDoc) {
                      return StreamBuilder<QuerySnapshot>(
                          stream: unitDoc.reference.collection('parts').snapshots(),
                          builder: (context, partSnap) {
                            bool isLoading = _loadingUnits.contains(unitDoc.id);
                            return ExpansionTile(
                              title: Text(unitDoc.id, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                              leading: const Icon(Icons.bolt, color: Colors.cyanAccent),
                              trailing: isLoading
                                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.cyanAccent))
                                  : TextButton(
                                onPressed: () => _loadUnitSizes(unitDoc.id, partSnap.data?.docs ?? []),
                                child: const Text("Load Sizes", style: TextStyle(color: Colors.cyanAccent, fontSize: 11)),
                              ),
                              children: [
                                if (partSnap.hasData)
                                  Column(
                                    children: partSnap.data!.docs.map((partDoc) {
                                      var data = partDoc.data() as Map<String, dynamic>;
                                      String decUrl = AuthService.decryptLink(data['videoUrl'] ?? "");
                                      String size = _sizes[decUrl] ?? "Size Hidden";
                                      return InkWell(
                                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => MXStylePlayer(url: decUrl, title: "${unitDoc.id} - ${partDoc.id}", subjectCode: widget.subject, unitName: "One-Shot", category: widget.category))),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Text(
                                                      partDoc.id, 
                                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      size, 
                                                      style: const TextStyle(color: Colors.white24, fontSize: 10),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              IconButton(
                                                icon: const Icon(Icons.download_for_offline_rounded, color: Colors.cyanAccent, size: 20), 
                                                onPressed: () => _startDownload(decUrl, "${unitDoc.id}__${partDoc.id}", false, widget.subject, unitDoc.id)
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  )
                              ],
                            );
                          }
                      );
                    }),
                    const Divider(color: Colors.white10, height: 40),
                  ],
                );
              },
            ),
          ),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('content').doc(widget.category).collection('subjects').doc(widget.subject).collection('units').snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const SliverToBoxAdapter(child: Center(child: CircularProgressIndicator(color: Colors.amber)));
              final docs = snapshot.data!.docs;
              return SliverList(delegate: SliverChildBuilderDelegate((context, index) => Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), child: Card(color: Theme.of(context).cardColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: const BorderSide(color: Colors.white10)), child: ListTile(title: Text(docs[index].id, style: const TextStyle(fontWeight: FontWeight.bold)), trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.amber), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => ContentListScreen(category: widget.category, subject: widget.subject, unit: docs[index].id)))))), childCount: docs.length));
            },
          ),
        ],
      ),
    );
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
  final Map<String, String> _sizes = {};
  bool _isLoadingSizes = false;
  String? _savedDirPath;
  
  final ReceivePort _port = ReceivePort();
  final Map<String, String> _urlToTaskId = {};
  final Map<String, String> _taskIdToFilePath = {};
  final Map<String, int> _progress = {};
  final Map<String, DownloadTaskStatus> _status = {};
  
  // BYPASS LOGIC VARIABLES
  final Map<String, String> _taskIdToItemId = {};

  @override
  void initState() {
    super.initState();
    _prepare();
    _bindBackgroundIsolate();
    _loadExistingTasks();
  }

  void _prepare() async {
    final dir = await getApplicationDocumentsDirectory();
    if (!mounted) return;
    setState(() => _savedDirPath = dir.path);
  }

  bool _isNoteLocallyAvailable(String itemId, bool isNotes) {
    if (_savedDirPath == null) return false;
    final directory = Directory(_savedDirPath!);
    if (!directory.existsSync()) return false;
    
    // Check if any file starts with "Subject__Unit__DocId"
    final List<FileSystemEntity> files = directory.listSync();
    for (var file in files) {
      if (p.basename(file.path).startsWith(itemId) && file is File && file.lengthSync() > 0) {
        return true;
      }
    }
    return false;
  }

  @override
  void dispose() {
    IsolateNameServer.removePortNameMapping('downloader_send_port');
    _port.close();
    super.dispose();
  }

  void _bindBackgroundIsolate() {
    if (IsolateNameServer.lookupPortByName('downloader_send_port') != null) {
      IsolateNameServer.removePortNameMapping('downloader_send_port');
    }
    IsolateNameServer.registerPortWithName(_port.sendPort, 'downloader_send_port');
    _port.listen((dynamic data) async {
      String id = data[0]; // taskId
      int statusInt = data[1];
      int progress = data[2];

      DownloadTaskStatus status = DownloadTaskStatus.fromInt(statusInt);

      if (mounted) {
        setState(() {
          _progress[id] = progress;
          _status[id] = status;
        });
      }
    });
  }

  Future<void> _loadExistingTasks() async {
    final tasks = await FlutterDownloader.loadTasks();
    if (tasks != null) {
      for (var task in tasks) {
        // Recover itemId from filename (formatted as "$itemId$extension")
        String? itemId;
        if (task.filename != null) {
          itemId = p.basenameWithoutExtension(task.filename!);
        }

        if (mounted) {
          setState(() {
            _urlToTaskId[task.url] = task.taskId;
            _taskIdToFilePath[task.taskId] = "${task.savedDir}${Platform.pathSeparator}${task.filename}";
            _progress[task.taskId] = task.progress;
            _status[task.taskId] = task.status;
            
            if (itemId != null) {
              _taskIdToItemId[task.taskId] = itemId;
            }
          });
        }
      }
    }
  }

  Future<void> _loadAllSizes(List<QueryDocumentSnapshot> docs, String type) async {
    setState(() => _isLoadingSizes = true);
    for (var doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final String encryptedUrl = data[type == "lectures" ? 'videoUrl' : 'fileUrl'] ?? "";
      if (encryptedUrl.isNotEmpty && !_sizes.containsKey(encryptedUrl)) {
        String decryptedUrl = AuthService.decryptLink(encryptedUrl);
        String size = await _fetchSize(decryptedUrl);
        if (mounted) setState(() => _sizes[encryptedUrl] = size);
      }
    }
    if (mounted) setState(() => _isLoadingSizes = false);
  }

  Future<String> _fetchSize(String url) async {
    if (url.isEmpty || url.contains("youtube.com") || url.contains("youtu.be")) return "Stream Only";
    try {
      final headResponse = await http.head(Uri.parse(url)).timeout(const Duration(seconds: 3));
      if (headResponse.headers.containsKey('content-length')) {
        return "${(double.parse(headResponse.headers['content-length']!) / (1024 * 1024)).toStringAsFixed(1)} MB";
      }
      return "Size Unknown";
    } catch (_) { return "Size Unknown"; }
  }

  Future<String> _getLocalFilePath(String itemId, bool isNotes) async {
    final dir = await getApplicationDocumentsDirectory();
    final List<FileSystemEntity> files = dir.listSync();
    for (var file in files) {
      if (p.basename(file.path).startsWith(itemId)) {
        return file.path;
      }
    }
    return "";
  }

  Future<void> _startBackgroundDownload(String url, String docId, String title, bool isNotes) async {
    if (url.isEmpty) return;
    if (Platform.isAndroid) {
      await Permission.notification.request();
    }
    final directory = await getApplicationDocumentsDirectory();
    final String extension = isNotes ? ".pdf" : ".mp4";
    
    // UNIQUE ID: Subject__Unit__DocId
    final String itemId = "${widget.subject}__${widget.unit}__$docId";
    // READABLE FILENAME: Subject__Unit__DocId__Title.extension
    final String fileName = "${itemId}__${title.replaceAll(' ', '_')}$extension";

    // CLEANUP: Delete any existing file for this itemId
    final List<FileSystemEntity> files = directory.listSync();
    for (var f in files) {
      if (p.basename(f.path).startsWith(itemId)) {
        await f.delete();
      }
    }

    final taskId = await FlutterDownloader.enqueue(
      url: url,
      savedDir: directory.path,
      fileName: fileName,
      showNotification: true,
      openFileFromNotification: false,
      saveInPublicStorage: false,
      allowCellular: true,
    );

    if (taskId != null) {
      if (mounted) {
        setState(() {
          _urlToTaskId[url] = taskId;
          _taskIdToFilePath[taskId] = "${directory.path}${Platform.pathSeparator}$fileName";
          _taskIdToItemId[taskId] = itemId;
          _progress[taskId] = 0;
          _status[taskId] = DownloadTaskStatus.enqueued;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.unit),
          bottom: const TabBar(indicatorColor: Colors.amber, labelColor: Colors.amber, tabs: [Tab(text: "Lectures"), Tab(text: "Notes")]),
          backgroundColor: Colors.transparent,
          actions: [
            Builder(builder: (ctx) => TextButton.icon(
              onPressed: _isLoadingSizes ? null : () {
                final tabController = DefaultTabController.of(ctx);
                _triggerLoadSizes(tabController.index == 0 ? "lectures" : "notes");
              },
              icon: _isLoadingSizes ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amber)) : const Icon(Icons.refresh, size: 18, color: Colors.amber),
              label: const Text("Load Sizes", style: TextStyle(color: Colors.amber, fontSize: 12)),
            )),
          ],
        ),
        body: TabBarView(children: [_buildList("lectures"), _buildList("notes")]),
      ),
    );
  }

  void _triggerLoadSizes(String type) async {
    final snapshot = await FirebaseFirestore.instance.collection('content').doc(widget.category).collection('subjects').doc(widget.subject).collection('units').doc(widget.unit).collection(type).get();
    _loadAllSizes(snapshot.docs, type);
  }

  Widget _buildList(String type) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('content').doc(widget.category).collection('subjects').doc(widget.subject).collection('units').doc(widget.unit).collection(type).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: Colors.amber));
        final docs = snapshot.data!.docs;
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            final String docId = docs[index].id;
            final String title = data['title'] ?? "No Title";
            final String url = data[type == "lectures" ? 'videoUrl' : 'fileUrl'] ?? "";
            final String size = _sizes[url] ?? "Size Hidden";
            bool isNotes = type == "notes";
            
            final String uniqueId = "${widget.subject}__${widget.unit}__$docId";
            final bool physicalFileExists = _isNoteLocallyAvailable(uniqueId, isNotes);
            final String decryptedUrl = AuthService.decryptLink(url);
            final String? taskId = _urlToTaskId[decryptedUrl];
            final int progress = _progress[taskId] ?? 0;
            final DownloadTaskStatus status = _status[taskId] ?? DownloadTaskStatus.undefined;

            final bool isDownloading = status == DownloadTaskStatus.running || status == DownloadTaskStatus.enqueued;
            final bool isDownloaded = physicalFileExists || status == DownloadTaskStatus.complete;

            return Card(
              color: Theme.of(context).cardColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: const BorderSide(color: Colors.white10)),
              child: InkWell(
                onTap: () async {
                  final navigator = Navigator.of(context);

                  if (isDownloaded) {
                    final String localPath = await _getLocalFilePath(uniqueId, isNotes);

                    if (!mounted) return;

                    if (isNotes) {
                      navigator.push(
                        MaterialPageRoute(
                          builder: (_) => AppPdfViewer(
                            filePath: localPath,
                            noteTitle: title,
                          ),
                        ),
                      );
                    } else {
                      navigator.push(
                        MaterialPageRoute(
                          builder: (_) => MXStylePlayer(
                            url: localPath,
                            title: title,
                            subjectCode: widget.subject,
                            unitName: widget.unit,
                            category: widget.category,
                          ),
                        ),
                      );
                    }
                  } else {
                    String decryptedUrl = AuthService.decryptLink(url);

                    if (isNotes) {
                      navigator.push(
                        MaterialPageRoute(
                          builder: (_) => AppPdfViewer(
                            pdfUrl: decryptedUrl,
                            noteTitle: title,
                          ),
                        ),
                      );
                    } else {
                      navigator.push(
                        MaterialPageRoute(
                          builder: (_) => MXStylePlayer(
                            url: decryptedUrl,
                            title: title,
                            subjectCode: widget.subject,
                            unitName: widget.unit,
                            category: widget.category,
                          ),
                        ),
                      );
                    }
                  }
                },
                borderRadius: BorderRadius.circular(15),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Icon(isNotes ? Icons.description : Icons.play_circle, color: Colors.amber),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title, 
                              style: const TextStyle(fontWeight: FontWeight.bold), 
                              maxLines: 1, 
                              overflow: TextOverflow.ellipsis
                            ),
                            const SizedBox(height: 4),
                            Text(
                              size, 
                              style: const TextStyle(color: Colors.white38, fontSize: 11),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      isDownloading 
                        ? SizedBox(
                            width: 32,
                            height: 32,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                CircularProgressIndicator(value: progress / 100, strokeWidth: 3, color: Colors.amber),
                                Text("${progress.clamp(0, 100)}%", style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.amber)),
                              ],
                            ),
                          )
                        : IconButton(
                            icon: Icon(
                              isDownloaded ? Icons.check_circle : Icons.download_for_offline, 
                              color: isDownloaded ? Colors.greenAccent : const Color(0xFFFFB300)
                            ),
                            onPressed: isDownloaded ? null : () => _startBackgroundDownload(decryptedUrl, docId, title, isNotes),
                          ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result == "DEVICE_MISMATCH" ? "Locked to another device!" : result),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(backgroundColor: Colors.black, body: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(32.0), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.05), shape: BoxShape.circle, border: Border.all(color: Colors.amber.withValues(alpha: 0.1), width: 2)), child: const Icon(Icons.bolt_rounded, size: 80, color: Colors.amber)), const SizedBox(height: 20), const Text("DARK HORIZON", style: TextStyle(color: Colors.amber, fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: 4)), const SizedBox(height: 60), Container(decoration: BoxDecoration(color: Colors.grey[900], borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white10)), child: TextField(controller: _emailController, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: "Student Email", prefixIcon: Icon(Icons.alternate_email, color: Colors.amber), border: InputBorder.none, contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 18)))), const SizedBox(height: 16), Container(decoration: BoxDecoration(color: Colors.grey[900], borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white10)), child: TextField(controller: _passwordController, obscureText: true, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: "Security Key", prefixIcon: Icon(Icons.vpn_key, color: Colors.amber), border: InputBorder.none, contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 18)))), const SizedBox(height: 40), SizedBox(width: double.infinity, height: 60, child: ElevatedButton(onPressed: _isLoading ? null : _login, style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))), child: _isLoading ? const CircularProgressIndicator(color: Colors.black) : const Text("INITIALIZE SYSTEM", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900))))]))));
  }
}

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});
  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  final ReceivePort _port = ReceivePort();
  List<FileSystemEntity> _files = [];
  List<DownloadTask> _tasks = [];
  final Map<String, double> _totalSizes = {};
  Timer? _refreshTimer;
  @override
  void initState() {
    super.initState();
    if (IsolateNameServer.lookupPortByName('downloader_send_port') != null) {
      IsolateNameServer.removePortNameMapping('downloader_send_port');
    }
    IsolateNameServer.registerPortWithName(_port.sendPort, 'downloader_send_port');
    _port.listen((dynamic data) => _loadAll());
    _loadAll();
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (timer) => _loadAll());
  }
  @override
  void dispose() {
    _refreshTimer?.cancel();
    IsolateNameServer.removePortNameMapping('downloader_send_port');
    super.dispose();
  }

  Future<void> _loadAll() async {
    final ts = await FlutterDownloader.loadTasks();
    if (!mounted) return;
    if (ts != null) {
      for (var t in ts) { if ((t.status == DownloadTaskStatus.running || t.status == DownloadTaskStatus.paused) && (!_totalSizes.containsKey(t.taskId) || _totalSizes[t.taskId] == 0)) _fetchFileSize(t.taskId, t.url); }
      setState(() => _tasks = ts);
    }
    final dir = await getApplicationDocumentsDirectory();
    if (!mounted) return;
    if (await dir.exists()) {
      setState(() {
        _files = dir.listSync().where((f) => f.path.endsWith('.mp4') || f.path.endsWith('.pdf')).toList();
        _files.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
      });
    }
  }
  Future<void> _fetchFileSize(String tid, String url) async {
    try {
      final r = await http.head(Uri.parse(url)).timeout(const Duration(seconds: 3));
      if (r.headers.containsKey('content-length')) {
        double b = double.parse(r.headers['content-length']!);
        if (mounted) setState(() => _totalSizes[tid] = b / (1024 * 1024));
      }
    } catch (_) {}
  }
  @override
  Widget build(BuildContext context) {
    final activeTasks = _tasks.where((t) => t.status == DownloadTaskStatus.running || t.status == DownloadTaskStatus.enqueued || t.status == DownloadTaskStatus.paused || t.status == DownloadTaskStatus.failed).toList();

    Map<String, Map<String, List<FileSystemEntity>>> grouped = {};
    for (var f in _files) {
      String n = p.basename(f.path);
      List<String> ps = n.split('__');
      String s = ps.length > 2 ? ps[0] : "General", u = ps.length > 2 ? ps[1] : "Misc";
      grouped.putIfAbsent(s, () => {}); grouped[s]!.putIfAbsent(u, () => []); grouped[s]![u]!.add(f);
    }
    return Scaffold(appBar: AppBar(title: const Text("My Downloads")), body: ListView(padding: const EdgeInsets.all(12), children: [
      if (activeTasks.isNotEmpty) ...[const Text("ACTIVE DOWNLOADS", style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 12)), const SizedBox(height: 10), ...activeTasks.map((t) => _buildActiveTaskTile(t)), const Divider(color: Colors.white10, height: 40)],
      ...grouped.entries.map((se) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Text(se.key, style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold))), ...se.value.entries.map((ue) => Card(color: Theme.of(context).cardColor, child: ExpansionTile(initiallyExpanded: true, title: Text(ue.key, style: const TextStyle(fontSize: 14)), children: ue.value.map((f) => _buildFileTile(f)).toList())))]))
    ]));
  }
  Widget _buildActiveTaskTile(DownloadTask t) {
    double total = _totalSizes[t.taskId] ?? 0, current = (t.progress / 100) * total;
    return Card(color: Theme.of(context).cardColor, child: Padding(padding: const EdgeInsets.all(12.0), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween, 
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          t.filename ?? "File", 
                          style: const TextStyle(fontWeight: FontWeight.bold), 
                          maxLines: 1, 
                          overflow: TextOverflow.ellipsis
                        ),
                      ],
                    ),
                  ), 
                  const SizedBox(width: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min, 
                    children: [
                      if (t.status == DownloadTaskStatus.running) 
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.pause, color: Colors.amber), 
                          onPressed: () => FlutterDownloader.pause(taskId: t.taskId)
                        ), 
                      if (t.status == DownloadTaskStatus.paused) 
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.play_arrow, color: Colors.green), 
                          onPressed: () => FlutterDownloader.resume(taskId: t.taskId)
                        ), 
                      if (t.status == DownloadTaskStatus.failed) 
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.refresh, color: Colors.orange), 
                          onPressed: () => FlutterDownloader.retry(taskId: t.taskId)
                        ), 
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.cancel, color: Colors.red), 
                        onPressed: () => FlutterDownloader.remove(taskId: t.taskId, shouldDeleteContent: true)
                      )
                    ]
                  )
                ]
              ), 
              const SizedBox(height: 8),
              LinearProgressIndicator(value: t.progress / 100, color: Colors.amber), 
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween, 
                children: [
                  Text("${t.progress}%", style: const TextStyle(color: Colors.amber, fontSize: 11)), 
                  if (total > 0) 
                    Expanded(
                      child: Text(
                        "${current.toStringAsFixed(1)} MB / ${total.toStringAsFixed(1)} MB", 
                        style: const TextStyle(color: Colors.white38, fontSize: 11),
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                      ),
                    )
                ]
              )
            ]
          )
        )
      );
  }
  Widget _buildFileTile(FileSystemEntity f) {
    String n = p.basename(f.path);
    List<String> ps = n.split('__');
    String t = ps.last.replaceAll('.mp4', '').replaceAll('.pdf', '');
    bool v = n.endsWith('.mp4');
    String s = "0 MB";
    try { s = "${(f.statSync().size / (1024 * 1024)).toStringAsFixed(1)} MB"; } catch (_) {}
    return ListTile(
      leading: Icon(v ? Icons.play_circle : Icons.description, color: Colors.amber),
      title: Text(t),
      subtitle: Text(s, style: const TextStyle(color: Colors.white24)),
      onTap: () {
        if (v) {
          Navigator.push(context, MaterialPageRoute(builder: (c) => MXStylePlayer(url: f.path, title: t, subjectCode: "Offline", unitName: "Downloads", category: "Offline")));
        } else {
          Navigator.push(context, MaterialPageRoute(builder: (c) => AppPdfViewer(filePath: f.path, noteTitle: t)));
        }
      },
      trailing: IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () { f.deleteSync(); _loadAll(); }),
    );
  }
}
