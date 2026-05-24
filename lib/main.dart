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

@pragma('vm:entry-point')
void downloadCallback(String id, int status, int progress) {
  final SendPort? send = IsolateNameServer.lookupPortByName('downloader_send_port');
  send?.send([id, status, progress]);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await FlutterDownloader.initialize(debug: true, ignoreSsl: false);
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Dark Horizon',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF000814),
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.amber, brightness: Brightness.dark, primary: Colors.amber),
        useMaterial3: true,
      ),
      home: const ConnectivityWrapper(child: AuthWrapper()),
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
    if (_isChecking) {
      return;
    }
    _isChecking = true;
    bool authorized = await AuthService().isDeviceAuthorized();
    if (mounted) {
      setState(() {
        _isAuthorized = authorized;
        _isChecking = false;
        _lastUid = uid;
      });
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
          if (_lastUid != user.uid || _isAuthorized == null) {
            _checkDevice(user.uid);
            return const Scaffold(body: Center(child: CircularProgressIndicator(color: Colors.amber)));
          }
          return _isAuthorized == true ? const SubjectListScreen() : const LoginScreen();
        }
        return const LoginScreen();
      },
    );
  }
}

class SubjectListScreen extends StatelessWidget {
  const SubjectListScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      backgroundColor: const Color(0xFF000814),
      appBar: AppBar(
        title: const Text("Dark Horizon", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2)),
        backgroundColor: Colors.transparent, iconTheme: const IconThemeData(color: Colors.amber),
        actions: const [
          CircleAvatar(backgroundColor: Colors.amber, radius: 15, child: Icon(Icons.person, size: 18, color: Colors.black)),
          SizedBox(width: 16),
        ],
      ),
      drawer: _buildModernDrawer(context, user),
      body: _buildStudentSubjectGrid(user),
    );
  }

  Widget _buildStudentSubjectGrid(User? user) {
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('users').doc(user?.uid).get(),
      builder: (context, userSnapshot) {
        if (userSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Colors.amber));
        }
        final userData = userSnapshot.data?.data() as Map<String, dynamic>?;
        final String category = userData?['assigned_category'] ?? "EE3rdsem";
        final String studentName = userData?['name'] ?? 'Student';
        return CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.all(24), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text("Welcome, $studentName 👋", style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Colors.white)), const SizedBox(height: 6), Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.amber.withValues(alpha: 0.3))), child: Text(category, style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 12)))]))),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('content').doc(category).collection('subjects').snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const SliverFillRemaining(child: Center(child: CircularProgressIndicator()));
                }
                final docs = snapshot.data!.docs;
                if (docs.isEmpty) {
                  return const SliverFillRemaining(child: Center(child: Text("No content available.", style: TextStyle(color: Colors.white24))));
                }
                return SliverPadding(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10), sliver: SliverGrid(gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 16, mainAxisSpacing: 16, childAspectRatio: 0.85), delegate: SliverChildBuilderDelegate((context, index) => _darkSubjectCard(context, docs[index].id, category), childCount: docs.length)));
              },
            ),
          ],
        );
      },
    );
  }

  Widget _darkSubjectCard(BuildContext context, String title, String category) {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => UnitListScreen(subject: title, category: category))),
      child: Container(
        decoration: BoxDecoration(color: Colors.grey[900], borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.white10), gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Colors.grey[900]!, Colors.black])),
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Container(width: 50, height: 50, decoration: const BoxDecoration(color: Colors.amber, shape: BoxShape.circle), child: const Icon(Icons.menu_book_rounded, color: Colors.black, size: 28)), const Spacer(), Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Colors.white), maxLines: 2, overflow: TextOverflow.ellipsis)]),
      ),
    );
  }

  Widget _buildModernDrawer(BuildContext context, User? user) {
    return Drawer(
      backgroundColor: Colors.black,
      child: Column(children: [
        const DrawerHeader(decoration: BoxDecoration(color: Colors.amber), child: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.bolt, size: 50, color: Colors.black), Text("Dark Horizon", style: TextStyle(color: Colors.black, fontSize: 20, fontWeight: FontWeight.bold))]))),
        ListTile(leading: const Icon(Icons.download_done, color: Colors.amber), title: const Text("My Downloads"), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => const DownloadsScreen()))),
        const Spacer(), ListTile(leading: const Icon(Icons.logout, color: Colors.redAccent), title: const Text("Sign Out"), onTap: () => AuthService().signOut()), const SizedBox(height: 20),
      ]),
    );
  }
}

class UnitListScreen extends StatelessWidget {
  final String subject;
  final String category;
  const UnitListScreen({super.key, required this.subject, required this.category});

  Future<String> _fetchSize(String url) async {
    if (url.isEmpty || url.contains("youtube.com") || url.contains("youtu.be")) return "Stream Only";
    try {
      final response = await http.get(Uri.parse(url), headers: {"Range": "bytes=0-0"}).timeout(const Duration(seconds: 3));
      if (response.headers.containsKey('content-range')) {
        double totalBytes = double.parse(response.headers['content-range']!.split('/').last);
        return "${(totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB";
      }
      return "Size Unknown";
    } catch (_) { return "Size Unknown"; }
  }

  Future<void> _startDownload(BuildContext context, String url, String title, bool isNotes, String sub, String unit) async {
    if (url.isEmpty) return;
    if (Platform.isAndroid) await Permission.notification.request();
    final directory = await getApplicationDocumentsDirectory();
    final String fileName = "$sub⦙$unit⦙${title.replaceAll(' ', '_')}${isNotes ? ".pdf" : ".mp4"}";
    await FlutterDownloader.enqueue(url: url, savedDir: directory.path, fileName: fileName, showNotification: true, openFileFromNotification: false, saveInPublicStorage: false);
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("One-Shot Download Started...")));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF000814),
      appBar: AppBar(title: Text(subject), backgroundColor: Colors.transparent),
      body: CustomScrollView(
        slivers: [
          // 1. ONE-SHOT SERIES (UNIT-BASED)
          SliverToBoxAdapter(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('content').doc(category).collection('subjects').doc(subject).collection('one_shots').snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const SizedBox.shrink();
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(padding: EdgeInsets.all(16), child: Text("ONE-SHOT SERIES", style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, letterSpacing: 1.2))),
                    ...snapshot.data!.docs.map((unitDoc) {
                      return ExpansionTile(
                        title: Text(unitDoc.id, style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold)),
                        leading: const Icon(Icons.bolt, color: Colors.cyanAccent),
                        children: [
                          StreamBuilder<QuerySnapshot>(
                            stream: unitDoc.reference.collection('parts').snapshots(),
                            builder: (context, partSnap) {
                              if (!partSnap.hasData) return const SizedBox.shrink();
                              return Column(
                                children: partSnap.data!.docs.map((partDoc) {
                                  var data = partDoc.data() as Map<String, dynamic>;
                                  String encryptedUrl = data['videoUrl'] ?? "";
                                  String decUrl = AuthService.decryptLink(encryptedUrl);
                                  
                                  return FutureBuilder<String>(
                                    future: _fetchSize(decUrl),
                                    builder: (context, sizeSnap) {
                                      return ListTile(
                                        title: Text(partDoc.id, style: const TextStyle(color: Colors.white54, fontSize: 13)),
                                        subtitle: Text(sizeSnap.data ?? "Calculating Size...", style: const TextStyle(color: Colors.white24, fontSize: 10)),
                                        trailing: IconButton(
                                          icon: const Icon(Icons.download_for_offline_rounded, color: Colors.cyanAccent, size: 20),
                                          onPressed: () => _startDownload(context, decUrl, "${unitDoc.id}⦙${partDoc.id}", false, subject, unitDoc.id),
                                        ),
                                        onTap: () {
                                          Navigator.push(context, MaterialPageRoute(builder: (c) => MXStylePlayer(url: decUrl, title: "${unitDoc.id} - ${partDoc.id}", subjectCode: subject, unitName: "One-Shot")));
                                        },
                                      );
                                    },
                                  );
                                }).toList(),
                              );
                            },
                          )
                        ],
                      );
                    }),
                    const Divider(color: Colors.white10, height: 40),
                  ],
                );
              },
            ),
          ),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('content').doc(category).collection('subjects').doc(subject).collection('units').snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const SliverToBoxAdapter(child: Center(child: CircularProgressIndicator()));
              }
              final docs = snapshot.data!.docs;
              return SliverList(delegate: SliverChildBuilderDelegate((context, index) => Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), child: Card(color: Colors.grey[900], shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: const BorderSide(color: Colors.white10)), child: ListTile(title: Text(docs[index].id, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.amber), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => ContentListScreen(category: category, subject: subject, unit: docs[index].id)))))), childCount: docs.length));
            },
          ),
        ],
      ),
    );
  }
}

class ContentListScreen extends StatelessWidget {
  final String category;
  final String subject;
  final String unit;
  const ContentListScreen({super.key, required this.category, required this.subject, required this.unit});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(length: 2, child: Scaffold(backgroundColor: const Color(0xFF000814), appBar: AppBar(title: Text(unit), bottom: const TabBar(indicatorColor: Colors.amber, labelColor: Colors.amber, unselectedLabelColor: Colors.white38, tabs: [Tab(text: "Lectures"), Tab(text: "Notes")]), backgroundColor: Colors.transparent), body: TabBarView(children: [_buildList(context, "lectures"), _buildList(context, "notes")])));
  }

  Widget _buildList(BuildContext context, String type) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('content').doc(category).collection('subjects').doc(subject).collection('units').doc(unit).collection(type).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data!.docs;
        return ListView.builder(padding: const EdgeInsets.all(12), itemCount: docs.length, itemBuilder: (context, index) {
          final data = docs[index].data() as Map<String, dynamic>;
          final String title = data['title'] ?? "No Title";
          final String url = data[type == "lectures" ? 'videoUrl' : 'fileUrl'] ?? "";
          return FutureBuilder<String>(
            future: _fetchSize(url),
            builder: (context, sizeSnapshot) {
              final String size = sizeSnapshot.data ?? "Loading...";
              return Card(
                color: Colors.grey[900], shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: const BorderSide(color: Colors.white10)),
                child: ListTile(
                  leading: Icon(type == "lectures" ? Icons.play_circle : Icons.description, color: Colors.amber),
                  title: Text(title, style: const TextStyle(color: Colors.white)),
                  subtitle: Text(size, style: const TextStyle(color: Colors.white38, fontSize: 11)),
                  trailing: IconButton(icon: const Icon(Icons.download_for_offline, color: Colors.amber), onPressed: () { String decryptedUrl = AuthService.decryptLink(url); _startDownload(context, decryptedUrl, title, type == "notes"); }),
                  onTap: () { if (type == "lectures") { String decryptedUrl = AuthService.decryptLink(url); Navigator.push(context, MaterialPageRoute(builder: (c) => MXStylePlayer(url: decryptedUrl, title: title, subjectCode: subject, unitName: unit))); } },
                ),
              );
            },
          );
        });
      },
    );
  }

  Future<String> _fetchSize(String url) async {
    if (url.isEmpty || url.contains("youtube.com") || url.contains("youtu.be")) {
      return "Stream Only";
    }
    try {
      final response = await http.get(Uri.parse(url), headers: {"Range": "bytes=0-0"}).timeout(const Duration(seconds: 3));
      if (response.headers.containsKey('content-range')) {
        double totalBytes = double.parse(response.headers['content-range']!.split('/').last);
        return "${(totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB";
      } else if (response.headers.containsKey('content-length')) {
        double mb = double.parse(response.headers['content-length']!) / (1024 * 1024);
        return "${mb.toStringAsFixed(1)} MB";
      }
      return "Size Unknown";
    } catch (_) {
      return "Size Unknown";
    }
  }

  Future<void> _startDownload(BuildContext context, String url, String title, bool isNotes) async {
    if (url.isEmpty) {
      return;
    }
    if (Platform.isAndroid) {
      await Permission.notification.request();
    }
    final directory = await getApplicationDocumentsDirectory();
    final String fileName = "$subject⦙$unit⦙${title.replaceAll(' ', '_')}${isNotes ? ".pdf" : ".mp4"}";
    await FlutterDownloader.enqueue(url: url, savedDir: directory.path, fileName: fileName, showNotification: true, openFileFromNotification: false, saveInPublicStorage: false);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Download Started...")));
    }
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
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      return;
    }
    setState(() => _isLoading = true);
    String? result = await AuthService().signIn(email: _emailController.text.trim(), password: _passwordController.text.trim());
    if (mounted) {
      setState(() => _isLoading = false);
    }
    if (result != null) {
      String msg = result == "DEVICE_MISMATCH" ? "Locked to another device!" : result;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.redAccent));
      }
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

class _DownloadsScreenState extends State<DownloadsScreen> with WidgetsBindingObserver {
  final ReceivePort _port = ReceivePort();
  List<FileSystemEntity> _files = [];
  List<DownloadTask> _tasks = [];
  final Map<String, double> _totalSizes = {}; 
  Timer? _refreshTimer;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    IsolateNameServer.registerPortWithName(_port.sendPort, 'downloader_send_port');
    _port.listen((dynamic data) => _loadAll());
    FlutterDownloader.registerCallback(downloadCallback);
    _loadAll();
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (timer) => _loadAll());
  }
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    IsolateNameServer.removePortNameMapping('downloader_send_port');
    super.dispose();
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _pauseAll();
    }
  }
  Future<void> _pauseAll() async {
    final ts = await FlutterDownloader.loadTasks();
    if (ts != null) {
      for (var t in ts) {
        if (t.status == DownloadTaskStatus.running) {
          await FlutterDownloader.pause(taskId: t.taskId);
        }
      }
    }
    _loadAll();
  }
  Future<void> _loadAll() async {
    final ts = await FlutterDownloader.loadTasks();
    if (ts != null) {
      for (var t in ts) {
        if ((t.status == DownloadTaskStatus.running || t.status == DownloadTaskStatus.paused) && (!_totalSizes.containsKey(t.taskId) || _totalSizes[t.taskId] == 0)) {
          _fetchFileSize(t.taskId, t.url);
        }
      }
      setState(() => _tasks = ts);
    }
    final dir = await getApplicationDocumentsDirectory();
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
        if (mounted) {
          setState(() => _totalSizes[tid] = b / (1024 * 1024));
        }
      }
    } catch (_) {}
  }
  @override
  Widget build(BuildContext context) {
    final activeTasks = _tasks.where((t) => t.status == DownloadTaskStatus.running || t.status == DownloadTaskStatus.enqueued || t.status == DownloadTaskStatus.paused || t.status == DownloadTaskStatus.failed).toList();
    Map<String, Map<String, List<FileSystemEntity>>> grouped = {};
    for (var f in _files) {
      String n = p.basename(f.path);
      List<String> ps = n.split('⦙');
      String s = ps.length > 2 ? ps[0] : "General";
      String u = ps.length > 2 ? ps[1] : "Misc";
      grouped.putIfAbsent(s, () => {});
      grouped[s]!.putIfAbsent(u, () => []);
      grouped[s]![u]!.add(f);
    }
    return Scaffold(backgroundColor: Colors.black, appBar: AppBar(title: const Text("My Downloads")), body: ListView(padding: const EdgeInsets.all(12), children: [
      if (activeTasks.isNotEmpty) ...[
        const Text("ACTIVE DOWNLOADS", style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 12)),
        const SizedBox(height: 10),
        ...activeTasks.map((t) => _buildActiveTaskTile(t)),
        const Divider(color: Colors.white10, height: 40)
      ],
      ...grouped.entries.map((se) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Text(se.key, style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold))),
        ...se.value.entries.map((ue) => Card(color: Colors.grey[900], child: ExpansionTile(initiallyExpanded: true, title: Text(ue.key, style: const TextStyle(color: Colors.white70, fontSize: 14)), children: ue.value.map((f) => _buildFileTile(f)).toList())))
      ]))
    ]));
  }
  Widget _buildActiveTaskTile(DownloadTask t) {
    double total = _totalSizes[t.taskId] ?? 0;
    double current = (t.progress / 100) * total;
    return Card(color: Colors.grey[900], child: Padding(padding: const EdgeInsets.all(12.0), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Expanded(child: Text(t.filename ?? "File", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold), maxLines: 1)), Row(mainAxisSize: MainAxisSize.min, children: [if (t.status == DownloadTaskStatus.running) IconButton(icon: const Icon(Icons.pause, color: Colors.amber), onPressed: () => FlutterDownloader.pause(taskId: t.taskId)), if (t.status == DownloadTaskStatus.paused) IconButton(icon: const Icon(Icons.play_arrow, color: Colors.green), onPressed: () => FlutterDownloader.resume(taskId: t.taskId)), if (t.status == DownloadTaskStatus.failed) IconButton(icon: const Icon(Icons.refresh, color: Colors.orange), onPressed: () => FlutterDownloader.retry(taskId: t.taskId)), IconButton(icon: const Icon(Icons.cancel, color: Colors.red), onPressed: () => FlutterDownloader.remove(taskId: t.taskId, shouldDeleteContent: true))])]), LinearProgressIndicator(value: t.progress / 100, color: Colors.amber), Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text("${t.progress}%", style: const TextStyle(color: Colors.amber, fontSize: 11)), if (total > 0) Text("${current.toStringAsFixed(1)} MB / ${total.toStringAsFixed(1)} MB", style: const TextStyle(color: Colors.white38, fontSize: 11))])])));
  }
  Widget _buildFileTile(FileSystemEntity f) {
    String n = p.basename(f.path);
    List<String> ps = n.split('⦙');
    String t = ps.last.replaceAll('.mp4', '').replaceAll('.pdf', '');
    bool v = n.endsWith('.mp4');
    String s = "0 MB";
    try {
      s = "${(f.statSync().size / (1024 * 1024)).toStringAsFixed(1)} MB";
    } catch (_) {}
    return ListTile(leading: Icon(v ? Icons.play_circle : Icons.description, color: Colors.amber), title: Text(t, style: const TextStyle(color: Colors.white60)), subtitle: Text(s, style: const TextStyle(color: Colors.white24)), onTap: () => v ? Navigator.push(context, MaterialPageRoute(builder: (c) => MXStylePlayer(url: f.path, title: t, subjectCode: "Offline", unitName: "Downloads"))) : OpenFilex.open(f.path), trailing: IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () { f.deleteSync(); _loadAll(); }));
  }
}
