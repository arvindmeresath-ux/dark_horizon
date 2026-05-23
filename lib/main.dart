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
import 'custom_video_player.dart';
import 'auth_service.dart';

@pragma('vm:entry-point')
void downloadCallback(String id, int status, int progress) {
  final SendPort? send = IsolateNameServer.lookupPortByName('downloader_send_port');
  send?.send([id, status, progress]);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await FlutterDownloader.initialize(debug: true, ignoreSsl: false);
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
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.amber, 
          brightness: Brightness.dark,
          primary: Colors.amber,
          secondary: const Color(0xFF00B4D8),
        ),
        useMaterial3: true,
      ),
      home: const AuthWrapper(),
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

// --- STUDENT DASHBOARD (DARK WORLD UI) ---
class SubjectListScreen extends StatefulWidget {
  const SubjectListScreen({super.key});
  @override
  State<SubjectListScreen> createState() => _SubjectListScreenState();
}

class _SubjectListScreenState extends State<SubjectListScreen> {
  final List<String> _allCategories = ["EE3rdsem", "EE5thsem", "EL3rdsem", "EL5thsem", "CSE3rdsem", "CSE5thsem"];

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final bool isAdmin = user?.email == "a13a14gt@gmail.com";

    return Scaffold(
      backgroundColor: const Color(0xFF000814),
      appBar: AppBar(
        title: Text(isAdmin ? "Command Center" : "Dark Horizon", style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.amber),
        actions: [
          IconButton(onPressed: () {}, icon: const Icon(Icons.notifications_none_rounded)),
          const SizedBox(width: 8),
          const CircleAvatar(backgroundColor: Colors.amber, radius: 15, child: Icon(Icons.person, size: 18, color: Colors.black)),
          const SizedBox(width: 16),
        ],
      ),
      drawer: _buildModernDrawer(context, user),
      body: isAdmin 
        ? _buildAdminCategoryGrid() // Admin sees all parts
        : _buildStudentSubjectGrid(user), // Student sees only their part
    );
  }

  // --- ADMIN VIEW: ALL CATEGORIES ---
  Widget _buildAdminCategoryGrid() {
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(child: _buildDarkHeader("Administrator", "SYSTEM ACCESS: ALL")),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 16, mainAxisSpacing: 16, childAspectRatio: 1.1),
            delegate: SliverChildBuilderDelegate(
              (context, index) => _categoryCard(_allCategories[index]),
              childCount: _allCategories.length,
            ),
          ),
        ),
      ],
    );
  }

  Widget _categoryCard(String cat) {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => AdminCategorySubjectsScreen(category: cat))),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey[900], borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.3)),
          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF001219), Colors.black]),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.folder_special_rounded, color: Colors.cyanAccent, size: 32),
            const SizedBox(height: 12),
            Text(cat, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  // --- STUDENT VIEW: SEGMENTED SUBJECTS ---
  Widget _buildStudentSubjectGrid(User? user) {
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('users').doc(user?.uid).get(),
      builder: (context, userSnapshot) {
        if (userSnapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Colors.amber));
        
        final userData = userSnapshot.data?.data() as Map<String, dynamic>?;
        final String category = userData?['assigned_category'] ?? "EE3rdsem";
        final String studentName = userData?['name'] ?? 'Student';

        return CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: _buildDarkHeader(studentName, category)),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('content').doc(category).collection('subjects').snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const SliverFillRemaining(child: Center(child: CircularProgressIndicator()));
                final docs = snapshot.data!.docs;
                if (docs.isEmpty) return const SliverFillRemaining(child: Center(child: Text("No content available for your batch.", style: TextStyle(color: Colors.white24))));

                return SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 16, mainAxisSpacing: 16, childAspectRatio: 0.85),
                    delegate: SliverChildBuilderDelegate((context, index) => _darkSubjectCard(context, docs[index].id, category), childCount: docs.length),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildDarkHeader(String name, String cat) {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text("Welcome, $name 👋", style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Colors.white)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.amber.withValues(alpha: 0.3))),
          child: Text(cat, style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 12)),
        ),
        const SizedBox(height: 30),
        const Text("Your Learning Path", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white70)),
      ]),
    );
  }

  Widget _darkSubjectCard(BuildContext context, String title, String category) {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => UnitListScreen(subject: title, category: category))),
      child: Container(
        decoration: BoxDecoration(color: Colors.grey[900], borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.white10), gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Colors.grey[900]!, Colors.black])),
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(width: 50, height: 50, decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.1), shape: BoxShape.circle), child: const Icon(Icons.menu_book_rounded, color: Colors.amber, size: 28)),
          const Spacer(),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Colors.white), maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 8),
          const Row(children: [Text("Explore", style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold)), SizedBox(width: 4), Icon(Icons.arrow_forward, color: Colors.white38, size: 12)]),
        ]),
      ),
    );
  }

  Widget _buildModernDrawer(BuildContext context, User? user) {
    return Drawer(
      backgroundColor: Colors.black,
      child: Column(children: [
        const DrawerHeader(decoration: BoxDecoration(color: Colors.amber), child: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.bolt, size: 50, color: Colors.black), Text("Dark Horizon", style: TextStyle(color: Colors.black, fontSize: 20, fontWeight: FontWeight.bold))]))),
        ListTile(leading: const Icon(Icons.download_done, color: Colors.amber), title: const Text("My Downloads"), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => const DownloadsScreen()))),
        if (user?.email == "a13a14gt@gmail.com")
          ListTile(leading: const Icon(Icons.admin_panel_settings, color: Colors.cyanAccent), title: const Text("Admin Dashboard"), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => const AdminPanelScreen()))),
        const Spacer(),
        ListTile(leading: const Icon(Icons.logout, color: Colors.redAccent), title: const Text("Sign Out"), onTap: () => AuthService().signOut()),
        const SizedBox(height: 20),
      ]),
    );
  }
}

// --- ADMIN HELPER: VIEW SUBJECTS FOR SPECIFIC CATEGORY ---
class AdminCategorySubjectsScreen extends StatelessWidget {
  final String category;
  const AdminCategorySubjectsScreen({super.key, required this.category});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF000814),
      appBar: AppBar(title: Text(category, style: const TextStyle(fontWeight: FontWeight.bold)), backgroundColor: Colors.transparent, iconTheme: const IconThemeData(color: Colors.amber)),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('content').doc(category).collection('subjects').snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final docs = snapshot.data!.docs;
          if (docs.isEmpty) return const Center(child: Text("No content in this segment.", style: TextStyle(color: Colors.white24)));

          return GridView.builder(
            padding: const EdgeInsets.all(20),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 16, mainAxisSpacing: 16, childAspectRatio: 0.85),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              String subject = docs[index].id;
              return GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => UnitListScreen(subject: subject, category: category))),
                child: Container(
                  decoration: BoxDecoration(color: Colors.grey[900], borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.white10)),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.menu_book_rounded, color: Colors.amber, size: 28),
                      const Spacer(),
                      Text(subject, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white), maxLines: 2),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// --- UNIT & CONTENT LIST SCREENS ---
class UnitListScreen extends StatelessWidget {
  final String subject;
  final String category;
  const UnitListScreen({super.key, required this.subject, required this.category});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF000814),
      appBar: AppBar(title: Text(subject), backgroundColor: Colors.transparent),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('content').doc(category).collection('subjects').doc(subject).collection('units').snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final docs = snapshot.data!.docs;
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: docs.length,
            itemBuilder: (context, index) => Card(color: Colors.grey[900], shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: const BorderSide(color: Colors.white10)), child: ListTile(title: Text(docs[index].id, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.amber), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => ContentListScreen(category: category, subject: subject, unit: docs[index].id))))),
          );
        },
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
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFF000814),
        appBar: AppBar(title: Text(unit), bottom: const TabBar(indicatorColor: Colors.amber, labelColor: Colors.amber, unselectedLabelColor: Colors.white38, tabs: [Tab(text: "Lectures"), Tab(text: "Notes")]), backgroundColor: Colors.transparent),
        body: TabBarView(children: [_buildList(context, "lectures"), _buildList(context, "notes")]),
      ),
    );
  }

  Widget _buildList(BuildContext context, String type) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('content').doc(category).collection('subjects').doc(subject).collection('units').doc(unit).collection(type).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snapshot.data!.docs;
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          itemBuilder: (context, index) {
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
                    trailing: IconButton(icon: const Icon(Icons.download_for_offline, color: Colors.amber), onPressed: () => _startDownload(context, url, title, type == "notes")),
                    onTap: () { if (type == "lectures") Navigator.push(context, MaterialPageRoute(builder: (c) => MXStylePlayer(url: url, title: title, subjectCode: subject, unitName: unit))); },
                  ),
                );
              }
            );
          },
        );
      },
    );
  }

  Future<String> _fetchSize(String url) async {
    if (url.isEmpty || url.contains("youtube.com") || url.contains("youtu.be")) return "Stream Only";
    try {
      // Robust fetching for Internet Archive & others using Range header
      final response = await http.get(Uri.parse(url), headers: {"Range": "bytes=0-0"}).timeout(const Duration(seconds: 3));
      
      if (response.headers.containsKey('content-range')) {
        String range = response.headers['content-range']!;
        double totalBytes = double.parse(range.split('/').last);
        return "${(totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB";
      } else if (response.headers.containsKey('content-length')) {
        double mb = double.parse(response.headers['content-length']!) / (1024 * 1024);
        return "${mb.toStringAsFixed(1)} MB";
      }
      return "Size Unknown";
    } catch (_) {
      try {
        final headRes = await http.head(Uri.parse(url)).timeout(const Duration(seconds: 2));
        if (headRes.headers.containsKey('content-length')) {
          double mb = double.parse(headRes.headers['content-length']!) / (1024 * 1024);
          return "${mb.toStringAsFixed(1)} MB";
        }
      } catch (__) {}
      return "Size Unknown";
    }
  }

  Future<void> _startDownload(BuildContext context, String url, String title, bool isNotes) async {
    if (url.isEmpty) return;
    if (Platform.isAndroid) await Permission.notification.request();
    final directory = await getApplicationDocumentsDirectory();
    final String fileName = "$subject⦙$unit⦙${title.replaceAll(' ', '_')}${isNotes ? ".pdf" : ".mp4"}";
    await FlutterDownloader.enqueue(url: url, savedDir: directory.path, fileName: fileName, showNotification: true, openFileFromNotification: false, saveInPublicStorage: false);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Download Started...")));
  }
}

// --- LOGIN SCREEN (MODERN DARK) ---
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please fill all fields")));
      return;
    }
    setState(() => _isLoading = true);
    String? result = await AuthService().signIn(email: _emailController.text.trim(), password: _passwordController.text.trim());
    if (mounted) setState(() => _isLoading = false);
    if (result != null) {
      String msg = result == "DEVICE_MISMATCH" ? "This account is locked to another device!" : result;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.redAccent));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32.0),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.05), shape: BoxShape.circle, border: Border.all(color: Colors.amber.withValues(alpha: 0.1), width: 2)), child: const Icon(Icons.bolt_rounded, size: 80, color: Colors.amber)),
            const SizedBox(height: 20),
            const Text("DARK HORIZON", style: TextStyle(color: Colors.amber, fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: 4)),
            const SizedBox(height: 60),
            _darkInput(controller: _emailController, label: "Student Email", icon: Icons.alternate_email_rounded),
            const SizedBox(height: 16),
            _darkInput(controller: _passwordController, label: "Security Key", icon: Icons.vpn_key_rounded, isPassword: true),
            const SizedBox(height: 40),
            SizedBox(width: double.infinity, height: 60, child: ElevatedButton(onPressed: _isLoading ? null : _login, style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), elevation: 10), child: _isLoading ? const CircularProgressIndicator(color: Colors.black) : const Text("INITIALIZE SYSTEM", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)))),
          ]),
        ),
      ),
    );
  }

  Widget _darkInput({required TextEditingController controller, required String label, required IconData icon, bool isPassword = false}) {
    return Container(decoration: BoxDecoration(color: Colors.grey[900], borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white10)), child: TextField(controller: controller, obscureText: isPassword, style: const TextStyle(color: Colors.white), decoration: InputDecoration(labelText: label, labelStyle: const TextStyle(color: Colors.white38, fontSize: 14), prefixIcon: Icon(icon, color: Colors.amber), border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18))));
  }
}

// --- ADMIN PANEL SCREEN ---
class AdminPanelScreen extends StatefulWidget {
  const AdminPanelScreen({super.key});
  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen> {
  final _subjectController = TextEditingController();
  final _regName = TextEditingController();
  final _regEmail = TextEditingController();
  final _regPass = TextEditingController();
  final List<String> _allCategories = ["EE3rdsem", "EE5thsem", "EL3rdsem", "EL5thsem", "CSE3rdsem", "CSE5thsem"];
  String _category = "EE3rdsem";
  String _regCat = "EE3rdsem";
  String _suggestedUnit = "Unit 1";
  bool _isUploading = false;
  final List<TextEditingController> _lectureControllers = [TextEditingController()];

  @override
  void initState() {
    super.initState();
    _setupController(0);
  }

  void _setupController(int index) {
    _lectureControllers[index].addListener(() {
      if (_lectureControllers[index].text.isNotEmpty && index == _lectureControllers.length - 1) {
        setState(() {
          _lectureControllers.add(TextEditingController());
          _setupController(_lectureControllers.length - 1);
        });
      }
    });
  }

  Future<void> _checkNextUnit() async {
    final String subject = _subjectController.text.trim();
    if (subject.isEmpty) {
      setState(() => _suggestedUnit = "Unit 1");
      return;
    }
    var snapshot = await FirebaseFirestore.instance.collection('content').doc(_category).collection('subjects').doc(subject).collection('units').get();
    
    if (snapshot.docs.isEmpty) {
      setState(() => _suggestedUnit = "Unit 1");
    } else {
      int maxUnit = 0;
      for (var doc in snapshot.docs) {
        String id = doc.id;
        if (id.startsWith("Unit ")) {
          int? num = int.tryParse(id.replaceFirst("Unit ", ""));
          if (num != null && num > maxUnit) maxUnit = num;
        }
      }
      setState(() { _suggestedUnit = "Unit ${maxUnit + 1}"; });
    }
  }

  Future<void> _uploadUnit() async {
    final String subject = _subjectController.text.trim();
    if (subject.isEmpty) return;
    setState(() => _isUploading = true);
    try {
      final batch = FirebaseFirestore.instance.batch();
      final unitPath = FirebaseFirestore.instance.collection('content').doc(_category).collection('subjects').doc(subject).collection('units').doc(_suggestedUnit);
      batch.set(unitPath, {'id': _suggestedUnit});
      batch.set(FirebaseFirestore.instance.collection('content').doc(_category).collection('subjects').doc(subject), {'id': subject});
      int count = 0;
      for (int i = 0; i < _lectureControllers.length; i++) {
        if (_lectureControllers[i].text.trim().isNotEmpty) {
          batch.set(unitPath.collection('lectures').doc(), {
            'title': "Lecture ${count + 1}",
            'videoUrl': _lectureControllers[i].text.trim(),
            'createdAt': FieldValue.serverTimestamp(),
          });
          count++;
        }
      }
      await batch.commit();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Batch Upload Successful!"), backgroundColor: Colors.green));
      setState(() { _lectureControllers.clear(); _lectureControllers.add(TextEditingController()); _setupController(0); });
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"))); }
    finally { if (mounted) setState(() => _isUploading = false); }
  }

  Future<void> _registerStudent() async {
    if (_regEmail.text.isEmpty || _regPass.text.isEmpty) return;
    try {
      await AuthService().signUp(email: _regEmail.text.trim(), password: _regPass.text.trim(), name: _regName.text.trim());
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) await FirebaseFirestore.instance.collection('users').doc(user.uid).set({'assigned_category': _regCat, 'name': _regName.text.trim(), 'email': _regEmail.text.trim()}, SetOptions(merge: true));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Student Registered!"), backgroundColor: Colors.green));
      _regEmail.clear(); _regPass.clear(); _regName.clear();
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Reg Error: $e"))); }
  }

  @override
  void dispose() {
    _subjectController.dispose(); _regName.dispose(); _regEmail.dispose(); _regPass.dispose();
    for (var c in _lectureControllers) { c.dispose(); }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text("System Dashboard"), actions: [IconButton(icon: const Icon(Icons.logout), onPressed: () => AuthService().signOut())]),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildFolder(
            title: "UPLOAD CONTENT",
            icon: Icons.cloud_upload_rounded,
            color: Colors.amber,
            child: Column(children: [
              DropdownButton<String>(value: _category, isExpanded: true, items: ["EE3rdsem", "EE5thsem", "EL3rdsem", "EL5thsem", "CSE3rdsem", "CSE5thsem"].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: (v) => setState(() { _category = v!; _checkNextUnit(); })),
              TextField(controller: _subjectController, decoration: const InputDecoration(labelText: "Subject Name"), onChanged: (_) => _checkNextUnit()),
              const SizedBox(height: 10),
              Text("Target: $_suggestedUnit", style: const TextStyle(color: Colors.amber, fontSize: 12, fontWeight: FontWeight.bold)),
              ListView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: _lectureControllers.length, itemBuilder: (c, i) => TextField(controller: _lectureControllers[i], decoration: InputDecoration(labelText: "Lecture ${i+1} URL"))),
              const SizedBox(height: 20),
              _isUploading ? const CircularProgressIndicator() : ElevatedButton(onPressed: _uploadUnit, style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black), child: const Text("INITIALIZE BULK UPLOAD")),
            ]),
          ),
          _buildFolder(
            title: "MANAGE SYSTEM",
            icon: Icons.settings_suggest_rounded,
            color: Colors.cyanAccent,
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('content').doc(_category).collection('subjects').snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const LinearProgressIndicator();
                return Column(children: snapshot.data!.docs.map((doc) => ListTile(
                  title: Text(doc.id, style: const TextStyle(color: Colors.white70)),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_forever, color: Colors.redAccent),
                    onPressed: () => _deleteSubjectDeep(doc.id),
                  )
                )).toList());
              },
            ),
          ),
          _buildFolder(
            title: "REGISTER STUDENT",
            icon: Icons.person_add_alt_1_rounded,
            color: Colors.greenAccent,
            child: Column(children: [
              TextField(controller: _regName, decoration: const InputDecoration(labelText: "Full Name")),
              TextField(controller: _regEmail, decoration: const InputDecoration(labelText: "Email")),
              TextField(controller: _regPass, decoration: const InputDecoration(labelText: "Password")),
              DropdownButton<String>(value: _regCat, isExpanded: true, items: ["EE3rdsem", "EE5thsem", "EL3rdsem", "EL5thsem", "CSE3rdsem", "CSE5thsem"].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: (v) => setState(() => _regCat = v!)),
              const SizedBox(height: 15),
              ElevatedButton(onPressed: _registerStudent, child: const Text("CREATE ACCOUNT")),
            ]),
          ),
          _buildFolder(
            title: "FIRESTORE DATABASE",
            icon: Icons.storage_rounded,
            color: Colors.orangeAccent,
            child: _buildLiveFirestoreView(),
          ),
          // 5. MANAGE USERS
          _buildFolder(
            title: "MANAGE USERS",
            icon: Icons.group_rounded,
            color: Colors.lightBlueAccent,
            child: _buildUserManagerView(),
          ),
        ],
      ),
    );
  }

  Widget _buildUserManagerView() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('users').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final users = snapshot.data!.docs;
        if (users.isEmpty) return const Center(child: Text("No users registered.", style: TextStyle(color: Colors.white24)));

        return Column(
          children: users.map((uDoc) {
            final uData = uDoc.data() as Map<String, dynamic>;
            final String name = uData['name'] ?? "Unknown";
            final String email = uData['email'] ?? "No Email";
            final String cat = uData['assigned_category'] ?? "None";
            
            return Card(
              color: Colors.black38,
              child: ListTile(
                title: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                subtitle: Text("$email • $cat", style: const TextStyle(color: Colors.white38, fontSize: 11)),
                trailing: IconButton(
                  icon: const Icon(Icons.person_remove_rounded, color: Colors.redAccent, size: 20),
                  onPressed: () => _deleteUser(uDoc.id, name),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Future<void> _deleteUser(String uid, String name) async {
    bool? confirm = await showDialog(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text("Delete User?", style: TextStyle(color: Colors.redAccent)),
        content: Text("Are you sure you want to remove '$name' from the system?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text("Remove", style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (confirm == true) {
      await FirebaseFirestore.instance.collection('users').doc(uid).delete();
    }
  }

  Widget _buildFolder({required String title, required IconData icon, required Color color, required Widget child}) {
    return Card(
      color: Colors.grey[900],
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: color.withValues(alpha: 0.2))),
      child: ExpansionTile(
        leading: Icon(icon, color: color),
        title: Text(title, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 1.1)),
        children: [Padding(padding: const EdgeInsets.all(16), child: child)],
      ),
    );
  }

  Widget _buildLiveFirestoreView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. CONTENT COLLECTION NODE
        ExpansionTile(
          leading: const Icon(Icons.folder_open_rounded, color: Colors.amber, size: 20),
          title: const Text("Collection: content", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
          children: _allCategories.map((cat) => Padding(
            padding: const EdgeInsets.only(left: 16.0),
            child: ExpansionTile(
              leading: const Icon(Icons.category_rounded, color: Colors.cyanAccent, size: 18),
              title: Text(cat, style: const TextStyle(color: Colors.white70, fontSize: 12)),
              children: [
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection('content').doc(cat).collection('subjects').snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return const SizedBox.shrink();
                    return Column(
                      children: snapshot.data!.docs.map((subDoc) => Padding(
                        padding: const EdgeInsets.only(left: 16.0),
                        child: ExpansionTile(
                          title: Text(subDoc.id, style: const TextStyle(color: Colors.white60, fontSize: 12)),
                          trailing: IconButton(icon: const Icon(Icons.delete_sweep_rounded, size: 16, color: Colors.redAccent), onPressed: () => _deleteSubjectDeep(subDoc.id)),
                          children: [
                            StreamBuilder<QuerySnapshot>(
                              stream: subDoc.reference.collection('units').snapshots(),
                              builder: (context, uSnap) {
                                if (!uSnap.hasData) return const SizedBox.shrink();
                                return Column(
                                  children: uSnap.data!.docs.map((uDoc) => Padding(
                                    padding: const EdgeInsets.only(left: 16.0),
                                    child: ExpansionTile(
                                      title: Text(uDoc.id, style: const TextStyle(color: Colors.white54, fontSize: 11)),
                                      trailing: IconButton(icon: const Icon(Icons.delete_outline, size: 16, color: Colors.redAccent), onPressed: () async {
                                        // Delete Unit and its contents
                                        final lecturesSnap = await uDoc.reference.collection('lectures').get();
                                        for (var l in lecturesSnap.docs) { await l.reference.delete(); }
                                        final notes = await uDoc.reference.collection('notes').get();
                                        for (var n in notes.docs) { await n.reference.delete(); }
                                        await uDoc.reference.delete();
                                        _checkNextUnit();
                                      }),
                                      children: [
                                        _buildItemList(uDoc.reference, "lectures"),
                                        _buildItemList(uDoc.reference, "notes"),
                                      ],
                                    ),
                                  )).toList(),
                                );
                              },
                            )
                          ],
                        ),
                      )).toList(),
                    );
                  },
                )
              ],
            ),
          )).toList(),
        ),

        // 2. USERS COLLECTION NODE
        ExpansionTile(
          leading: const Icon(Icons.folder_open_rounded, color: Colors.greenAccent, size: 20),
          title: const Text("Collection: users", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
          children: [
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('users').snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const SizedBox.shrink();
                return Column(
                  children: snapshot.data!.docs.map((uDoc) {
                    final data = uDoc.data() as Map<String, dynamic>;
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.person, size: 16, color: Colors.white38),
                      title: Text(data['name'] ?? uDoc.id, style: const TextStyle(color: Colors.white54, fontSize: 11)),
                      subtitle: Text(data['email'] ?? "No Email", style: const TextStyle(color: Colors.white24, fontSize: 9)),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, size: 16, color: Colors.redAccent),
                        onPressed: () => _deleteUser(uDoc.id, data['name'] ?? "User"),
                      ),
                    );
                  }).toList(),
                );
              },
            )
          ],
        ),
      ],
    );
  }

  Widget _buildItemList(DocumentReference ref, String type) {
    return StreamBuilder<QuerySnapshot>(
      stream: ref.collection(type).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        return Column(children: snapshot.data!.docs.map((doc) => ListTile(
          dense: true,
          leading: Icon(type == "lectures" ? Icons.play_circle : Icons.description, size: 16, color: Colors.white38),
          title: Text(doc['title'] ?? "", style: const TextStyle(color: Colors.white54, fontSize: 12)),
          trailing: IconButton(
            icon: const Icon(Icons.delete, size: 16, color: Colors.redAccent),
            onPressed: () async {
              await doc.reference.delete();
              _checkNextUnit(); // Refresh numbering
            },
          ),
        )).toList());
      },
    );
  }

  Future<void> _deleteSubjectDeep(String subName) async {
    bool? confirm = await showDialog(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text("Clean System Wipe?", style: TextStyle(color: Colors.redAccent)),
        content: Text("Deleting '$subName' will remove all its units and lectures from the database. Re-uploading will start from Unit 1."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text("Wipe All", style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isUploading = true);
      try {
        final subjectRef = FirebaseFirestore.instance.collection('content').doc(_category).collection('subjects').doc(subName);
        final unitsSnap = await subjectRef.collection('units').get();
        
        for (var unitDoc in unitsSnap.docs) {
          final lecturesSnap = await unitDoc.reference.collection('lectures').get();
          for (var lec in lecturesSnap.docs) { await lec.reference.delete(); }
          final notesSnap = await unitDoc.reference.collection('notes').get();
          for (var note in notesSnap.docs) { await note.reference.delete(); }
          await unitDoc.reference.delete();
        }
        await subjectRef.delete();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("'$subName' and all sub-folders wiped!")));
          _checkNextUnit();
        }
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Wipe Error: $e")));
      } finally {
        if (mounted) setState(() => _isUploading = false);
      }
    }
  }
}

// --- DOWNLOADS SCREEN ---
class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});
  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  final ReceivePort _port = ReceivePort();
  List<FileSystemEntity> _files = [];
  List<DownloadTask> _tasks = [];
  final Map<String, double> _totalSizes = {}; // TaskID -> Total MB
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    
    // Bind Downloader Isolate
    IsolateNameServer.registerPortWithName(_port.sendPort, 'downloader_send_port');
    _port.listen((dynamic data) => _loadAll());
    FlutterDownloader.registerCallback(downloadCallback);

    _loadAll();
    _refreshTimer = Timer.periodic(const Duration(seconds: 2), (timer) => _loadAll());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    IsolateNameServer.removePortNameMapping('downloader_send_port');
    super.dispose();
  }

  Future<void> _loadAll() async {
    // Load Active Tasks
    final tasks = await FlutterDownloader.loadTasks();
    if (tasks != null) {
      for (var task in tasks) {
        // Fetch size if not known or if it's currently downloading
        if ((task.status == DownloadTaskStatus.running || task.status == DownloadTaskStatus.paused) && 
            (!_totalSizes.containsKey(task.taskId) || _totalSizes[task.taskId] == 0)) {
          _fetchFileSize(task.taskId, task.url);
        }
      }
      setState(() => _tasks = tasks);
    }

    // Load Completed Files
    final dir = await getApplicationDocumentsDirectory();
    if (await dir.exists()) {
      setState(() {
        _files = dir.listSync()
            .where((file) => file.path.endsWith('.mp4') || file.path.endsWith('.pdf'))
            .toList();
        _files.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
      });
    }
  }

  // Logic to fetch total MB from URL headers
  Future<void> _fetchFileSize(String taskId, String url) async {
    try {
      final response = await http.head(Uri.parse(url)).timeout(const Duration(seconds: 3));
      if (response.headers.containsKey('content-length')) {
        double bytes = double.parse(response.headers['content-length']!);
        if (mounted) setState(() => _totalSizes[taskId] = bytes / (1024 * 1024));
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    // Filter active tasks
    final activeTasks = _tasks.where((t) => 
      t.status == DownloadTaskStatus.running || 
      t.status == DownloadTaskStatus.enqueued || 
      t.status == DownloadTaskStatus.paused
    ).toList();

    // Grouping for completed files
    Map<String, Map<String, List<FileSystemEntity>>> grouped = {};
    for (var file in _files) {
      String name = p.basename(file.path);
      List<String> parts = name.split('⦙');
      String sub = parts.length > 2 ? parts[0] : "General";
      String unit = parts.length > 2 ? parts[1] : "Misc";
      grouped.putIfAbsent(sub, () => {}); grouped[sub]!.putIfAbsent(unit, () => []); grouped[sub]![unit]!.add(file);
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text("My Downloads"), actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _loadAll)]),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // 1. ACTIVE DOWNLOADS SECTION
          if (activeTasks.isNotEmpty) ...[
            const Text("ACTIVE DOWNLOADS", style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.2)),
            const SizedBox(height: 10),
            ...activeTasks.map((task) => _buildActiveTaskTile(task)),
            const Divider(color: Colors.white10, height: 40),
          ],

          // 2. LIBRARY SECTION
          const Text("LIBRARY", style: TextStyle(color: Colors.white38, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.2)),
          const SizedBox(height: 10),
          ...grouped.entries.map((subEntry) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Text(subEntry.key, style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold))),
              ...subEntry.value.entries.map((unitEntry) => Card(
                color: Colors.grey[900],
                child: ExpansionTile(
                  initiallyExpanded: true,
                  title: Text(unitEntry.key, style: const TextStyle(color: Colors.white70, fontSize: 14)),
                  children: unitEntry.value.map((file) => _buildFileTile(file)).toList(),
                ),
              )),
            ],
          )),
          
          if (_files.isEmpty && activeTasks.isEmpty)
            const Center(child: Padding(padding: EdgeInsets.only(top: 100), child: Text("No files in system", style: TextStyle(color: Colors.white10)))),
        ],
      ),
    );
  }

  Widget _buildActiveTaskTile(DownloadTask task) {
    double totalMB = _totalSizes[task.taskId] ?? 0;
    double currentMB = (task.progress / 100) * totalMB;

    bool isRunning = task.status == DownloadTaskStatus.running;
    bool isPaused = task.status == DownloadTaskStatus.paused;

    return Card(
      color: Colors.grey[900],
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(task.filename ?? "File", style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isRunning)
                      IconButton(
                        constraints: const BoxConstraints(),
                        padding: const EdgeInsets.all(4),
                        icon: const Icon(Icons.pause_circle_filled, color: Colors.amber, size: 24),
                        onPressed: () async {
                          await FlutterDownloader.pause(taskId: task.taskId);
                          _loadAll();
                        },
                      ),
                    if (isPaused)
                      IconButton(
                        constraints: const BoxConstraints(),
                        padding: const EdgeInsets.all(4),
                        icon: const Icon(Icons.play_circle_fill, color: Colors.greenAccent, size: 24),
                        onPressed: () async {
                          await FlutterDownloader.resume(taskId: task.taskId);
                          _loadAll();
                        },
                      ),
                    IconButton(
                      constraints: const BoxConstraints(),
                      padding: const EdgeInsets.all(4),
                      icon: const Icon(Icons.cancel, color: Colors.redAccent, size: 24),
                      onPressed: () async {
                        await FlutterDownloader.remove(taskId: task.taskId, shouldDeleteContent: true);
                        _loadAll();
                      },
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: task.progress / 100, color: Colors.amber, backgroundColor: Colors.white10),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("${task.progress}% Complete", style: const TextStyle(color: Colors.amber, fontSize: 11)),
                if (totalMB > 0)
                  Text("${currentMB.toStringAsFixed(1)} MB / ${totalMB.toStringAsFixed(1)} MB", style: const TextStyle(color: Colors.white38, fontSize: 11)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFileTile(FileSystemEntity file) {
    String name = p.basename(file.path);
    List<String> parts = name.split('⦙');
    String title = parts.last.replaceAll('_', ' ').replaceAll('.mp4', '').replaceAll('.pdf', '');
    bool isVideo = name.endsWith('.mp4');

    return ListTile(
      leading: Icon(isVideo ? Icons.play_circle : Icons.description, color: Colors.amber, size: 20),
      title: Text(title, style: const TextStyle(color: Colors.white60, fontSize: 13)),
      onTap: () => isVideo 
        ? Navigator.push(context, MaterialPageRoute(builder: (c) => MXStylePlayer(url: file.path, title: title, subjectCode: "Offline", unitName: "Downloads")))
        : OpenFilex.open(file.path),
      trailing: IconButton(
        icon: const Icon(Icons.delete, color: Colors.redAccent, size: 18),
        onPressed: () { file.deleteSync(); _loadAll(); },
      ),
    );
  }
}
