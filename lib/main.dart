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
import 'package:path/path.dart' as p;
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
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
      if (rawVer is int) latestVersion = rawVer;
      else if (rawVer is double) latestVersion = rawVer.toInt();
      else if (rawVer is String) latestVersion = int.tryParse(rawVer) ?? 1;

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
    // PC Responsive Grid Count
    int crossAxisCount = (MediaQuery.of(context).size.width > 900) ? 4 : 2;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Dark Horizon", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        actions: const [CircleAvatar(backgroundColor: Colors.amber, radius: 15, child: Icon(Icons.person, size: 18, color: Colors.black)), SizedBox(width: 16)],
      ),
      drawer: _buildModernDrawer(context),
      body: _buildStudentSubjectGrid(user, crossAxisCount),
    );
  }

  Widget _buildStudentSubjectGrid(User? user, int crossAxisCount) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(user?.uid).snapshots(),
      builder: (context, userSnapshot) {
        if (userSnapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Colors.amber));
        final userData = userSnapshot.data?.data() as Map<String, dynamic>?;
        final List<dynamic> subjectsArray = userData?['subjects'] ?? [];

        if (subjectsArray.isNotEmpty) {
          return CustomScrollView(
            slivers: [
              const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(24), child: Text("My Subjects 👋", style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900)))),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: crossAxisCount, crossAxisSpacing: 16, mainAxisSpacing: 16, childAspectRatio: 0.85),
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final item = subjectsArray[index];
                    String title = (item is Map) ? (item['name'] ?? "") : item.toString();
                    String category = (item is Map) ? (item['category'] ?? "") : "";
                    return _buildSubjectCard(title, category);
                  }, childCount: subjectsArray.length),
                ),
              ),
            ],
          );
        }

        String assignedCategory = userData?['assigned_category'] ?? userData?['branch'] ?? userData?['category'] ?? "EE3rdsem";
        if (assignedCategory.toLowerCase() == "all") assignedCategory = "EE3rdsem";
        
        final String studentName = userData?['name'] ?? 'Student';
        final bool isMasterAdmin = (userData?['role']?.toString().toLowerCase().contains('admin') ?? false) || (assignedCategory.toLowerCase() == "all");
        final String currentCategory = isMasterAdmin ? (_selectedCategory ?? assignedCategory) : assignedCategory;

        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.all(24), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text("Welcome, $studentName 👋", style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)), const SizedBox(height: 12), _buildCategoryDropdown(currentCategory, isMasterAdmin)]))),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('content').doc(currentCategory).collection('subjects').snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const SliverFillRemaining(child: Center(child: CircularProgressIndicator(color: Colors.amber)));
                final docs = snapshot.data!.docs;
                return SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: crossAxisCount, crossAxisSpacing: 16, mainAxisSpacing: 16, childAspectRatio: 0.85),
                    delegate: SliverChildBuilderDelegate((context, index) => _buildSubjectCard(docs[index].id, currentCategory), childCount: docs.length),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildSubjectCard(String title, String category) {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => UnitListScreen(subject: title, category: category))),
      child: Container(
        decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.white10)),
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(width: 40, height: 40, decoration: const BoxDecoration(color: Colors.amber, shape: BoxShape.circle), child: const Icon(Icons.menu_book_rounded, color: Colors.black, size: 20)),
          const Spacer(),
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), maxLines: 2, overflow: TextOverflow.ellipsis)
        ]),
      ),
    );
  }

  Widget _buildCategoryDropdown(String currentVal, bool isAdmin) {
    if (!isAdmin) return Text("Branch: $currentVal", style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold));
    return FutureBuilder<QuerySnapshot>(
      future: FirebaseFirestore.instance.collection('content').get(),
      builder: (context, snapshot) {
        Set<String> categorySet = {'EE3rdsem', 'EE5thsem', 'EL3rdsem', 'EL5thsem', 'CSE3rdsem', 'CSE5thsem'};
        if (snapshot.hasData) { for (var d in snapshot.data!.docs) { if (d.id != "all") categorySet.add(d.id); } }
        List<String> categories = categorySet.toList()..sort();
        return DropdownButton<String>(
          value: categories.contains(currentVal) ? currentVal : categories[0],
          items: categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
          onChanged: (v) => setState(() => _selectedCategory = v),
        );
      },
    );
  }

  Widget _buildModernDrawer(BuildContext context) {
    return Drawer(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      child: Column(children: [
        Container(width: double.infinity, padding: const EdgeInsets.all(40), color: Colors.amber, child: const Text("Dark Horizon", style: TextStyle(color: Colors.black, fontSize: 22, fontWeight: FontWeight.w900))),
        ListTile(leading: const Icon(Icons.done_all_rounded, color: Colors.amber), title: const Text("Downloads"), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => const DownloadsScreen()))),
        ListTile(leading: const Icon(Icons.logout, color: Colors.red), title: const Text("Sign Out"), onTap: () => AuthService().signOut()),
      ]),
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
  String? _savedDirPath;
  final ReceivePort _port = ReceivePort();
  final Map<String, int> _progress = {};
  final Map<String, DownloadTaskStatus> _status = {};
  String? _resolvedCategory;

  @override
  void initState() {
    super.initState();
    _prepare();
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

  void _prepare() async {
    final dir = await getApplicationDocumentsDirectory();
    if (mounted) setState(() => _savedDirPath = dir.path);
  }

  void _bindBackgroundIsolate() {
    IsolateNameServer.registerPortWithName(_port.sendPort, 'downloader_send_port');
    _port.listen((data) {
      if (mounted) setState(() { _progress[data[0]] = data[2]; _status[data[0]] = DownloadTaskStatus.fromInt(data[1]); });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_resolvedCategory == null) return const Scaffold(body: Center(child: CircularProgressIndicator(color: Colors.amber)));
    int crossAxisCount = (MediaQuery.of(context).size.width > 900) ? 4 : 2;

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(FirebaseAuth.instance.currentUser?.uid).snapshots(),
      builder: (context, userSnapshot) {
        final userData = userSnapshot.data?.data() as Map<String, dynamic>?;
        bool isOneShotOnly = (userData?['oneShotOnlySubjects'] ?? []).contains(widget.subject);

        return Scaffold(
          appBar: AppBar(title: Text(widget.subject)),
          body: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: ListTile(
                  tileColor: Colors.cyanAccent.withValues(alpha: 0.1),
                  title: const Text("ONE-SHOT SERIES", style: TextStyle(fontWeight: FontWeight.bold)),
                  trailing: const Icon(Icons.arrow_forward_ios),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => OneShotSeriesScreen(subject: widget.subject, category: _resolvedCategory!))),
                ),
              ),
              if (!isOneShotOnly)
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection('content').doc(_resolvedCategory).collection('subjects').doc(widget.subject).collection('units').snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return const SliverToBoxAdapter(child: LinearProgressIndicator());
                    final docs = snapshot.data!.docs;
                    return SliverPadding(
                      padding: const EdgeInsets.all(20),
                      sliver: SliverGrid(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: crossAxisCount, crossAxisSpacing: 16, mainAxisSpacing: 16),
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
        decoration: BoxDecoration(color: const Color(0xFF0A0A0A), borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.amber.withValues(alpha: 0.1))),
        child: Center(child: Text(title, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold))),
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
      backgroundColor: Colors.black,
      appBar: AppBar(title: Text("${widget.subject} One-Shot")),
      body: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          ElevatedButton(onPressed: () => setState(() => _showNotes = false), child: const Text("LECTURES")),
          const SizedBox(width: 20),
          ElevatedButton(onPressed: () => setState(() => _showNotes = true), child: const Text("NOTES")),
        ]),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('content').doc(widget.category).collection('subjects').doc(widget.subject).collection('one_shots').snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              final units = snapshot.data!.docs;
              return ListView.builder(
                itemCount: units.length,
                itemBuilder: (context, index) => _buildUnitSection(units[index]),
              );
            },
          ),
        ),
      ]),
    );
  }

  Widget _buildUnitSection(QueryDocumentSnapshot unitDoc) {
    String path = _showNotes ? "notes" : "parts";
    return StreamBuilder<QuerySnapshot>(
      stream: unitDoc.reference.collection(path).snapshots(),
      builder: (context, sub) {
        if (!sub.hasData) return const SizedBox.shrink();
        return Column(children: sub.data!.docs.map((item) {
          final data = item.data() as Map<String, dynamic>;
          final url = AuthService.decryptLink(data[_showNotes ? 'fileUrl' : 'videoUrl'] ?? "");
          return ListTile(
            title: Text(item.id),
            onTap: () {
              if (_showNotes) {
                Navigator.push(context, MaterialPageRoute(builder: (c) => AppPdfViewer(pdfUrl: url, noteTitle: item.id)));
              } else {
                Navigator.push(context, MaterialPageRoute(builder: (c) => MXStylePlayer(url: url, title: item.id, subjectCode: widget.subject, unitName: "One-Shot", category: widget.category)));
              }
            },
          );
        }).toList());
      },
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
  bool _showNotes = false;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: Text(widget.unit)),
      body: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          ElevatedButton(onPressed: () => setState(() => _showNotes = false), child: const Text("LECTURES")),
          const SizedBox(width: 20),
          ElevatedButton(onPressed: () => setState(() => _showNotes = true), child: const Text("NOTES")),
        ]),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('content').doc(widget.category).collection('subjects').doc(widget.subject).collection('units').doc(widget.unit).collection(_showNotes ? 'notes' : 'lectures').snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              final docs = snapshot.data!.docs;
              return ListView.builder(
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final data = docs[index].data() as Map<String, dynamic>;
                  final url = AuthService.decryptLink(data[_showNotes ? 'fileUrl' : 'videoUrl'] ?? "");
                  return ListTile(
                    leading: Icon(_showNotes ? Icons.description : Icons.play_circle, color: Colors.amber),
                    title: Text(data['title'] ?? docs[index].id),
                    onTap: () {
                      if (_showNotes) {
                        Navigator.push(context, MaterialPageRoute(builder: (c) => AppPdfViewer(pdfUrl: url, noteTitle: docs[index].id)));
                      } else {
                        Navigator.push(context, MaterialPageRoute(builder: (c) => MXStylePlayer(url: url, title: docs[index].id, subjectCode: widget.subject, unitName: widget.unit, category: widget.category)));
                      }
                    },
                  );
                },
              );
            },
          ),
        ),
      ]),
    );
  }
}

class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("My Downloads")),
      body: Center(child: Text(Platform.isWindows ? "Offline downloads are available on mobile app." : "No downloads found.")),
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
    if (mounted) setState(() => _isLoading = false);
    if (result != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result == "DEVICE_MISMATCH" ? "Locked to another device!" : result), backgroundColor: Colors.redAccent));
    }
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(backgroundColor: Colors.black, body: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(32.0), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Icon(Icons.bolt_rounded, size: 80, color: Colors.amber),
      const SizedBox(height: 20),
      const Text("DARK HORIZON PC", style: TextStyle(color: Colors.amber, fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: 4)),
      const SizedBox(height: 60),
      TextField(controller: _emailController, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: "Student Email", prefixIcon: Icon(Icons.alternate_email, color: Colors.amber))),
      const SizedBox(height: 16),
      TextField(controller: _passwordController, obscureText: true, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: "Security Key", prefixIcon: Icon(Icons.vpn_key, color: Colors.amber))),
      const SizedBox(height: 40),
      SizedBox(width: double.infinity, height: 60, child: ElevatedButton(onPressed: _isLoading ? null : _login, style: ElevatedButton.styleFrom(backgroundColor: Colors.amber), child: _isLoading ? const CircularProgressIndicator(color: Colors.black) : const Text("INITIALIZE SYSTEM", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)))),
    ]))));
  }
}
