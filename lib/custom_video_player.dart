import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pdfx/pdfx.dart';
import 'package:http/http.dart' as http;
import 'auth_service.dart';

enum ViewMode { video, notes }

class MXStylePlayer extends StatefulWidget {
  final String url;
  final String title;
  final String subjectCode;
  final String unitName;
  final String category;

  const MXStylePlayer({
    super.key,
    required this.url,
    required this.title,
    required this.subjectCode,
    required this.unitName,
    required this.category,
  });

  @override
  State<MXStylePlayer> createState() => _MXStylePlayerState();
}

class _MXStylePlayerState extends State<MXStylePlayer> with WidgetsBindingObserver {
  // Video Logic
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _showControls = true;
  Timer? _controlsTimer;

  double _volume = 0.5;
  double _brightness = 0.5;
  double _playbackSpeed = 1.0;
  BoxFit _videoFit = BoxFit.contain;

  String? _currentUrl;
  String? _currentTitle;

  // REFACTORED PDFX DECODER LOGIC
  ViewMode _currentMode = ViewMode.video;
  PdfController? _pdfController;
  int _currentPageIndex = 0;
  int _totalPagesCount = 0;
  bool _isLoadingNotes = false;

  // Theme
  //
  // Colors
  static const Color neonCyan = Color(0xFF00F0FF);
  static const Color brightYellow = Color(0xFFFFD600);
  static const Color amberAccent = Color(0xFFFFB300);
  static const Color darkSlate = Color(0xFF0D0D0D);

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.url;
    _currentTitle = widget.title;
    WidgetsBinding.instance.addObserver(this);
    _initializeController(_currentUrl!);
    SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  void _initializeController(String url) async {
    setState(() => _isInitialized = false);
    _controller?.dispose();
    String videoUrl = url;
    if (videoUrl.contains("youtube.com") || videoUrl.contains("youtu.be")) {
      try {
        var yt = YoutubeExplode();
        var videoId = videoUrl.contains("youtu.be") ? videoUrl.split("/").last.split("?").first : videoUrl.split("v=")[1].split("&")[0];
        var manifest = await yt.videos.streamsClient.getManifest(videoId);
        videoUrl = manifest.muxed.withHighestBitrate().url.toString();
        yt.close();
      } catch (_) {}
    }
    _controller = videoUrl.startsWith('http') ? VideoPlayerController.networkUrl(Uri.parse(videoUrl)) : VideoPlayerController.file(File(videoUrl));
    _controller!.initialize().then((_) {
      if (mounted) {
        setState(() { _isInitialized = true; _controller!.play(); });
        _startControlsTimer();
      }
    });
    _controller!.addListener(() { if (mounted) setState(() {}); });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controlsTimer?.cancel();
    _controller?.dispose();
    _pdfController?.dispose();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _startControlsTimer() {
    _controlsTimer?.cancel();
    _controlsTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && _controller!.value.isPlaying) setState(() => _showControls = false);
    });
  }

  void _toggleControls() {
    setState(() { _showControls = !_showControls; if (_showControls) _startControlsTimer(); });
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return "${twoDigits(d.inMinutes)}:${twoDigits(d.inSeconds.remainder(60))}";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _toggleControls,
        child: Stack(
          children: [
            // --- 1. MAIN CONTENT AREA ---
            Positioned.fill(
              child: _currentMode == ViewMode.video 
                  ? _buildVideoSurface() 
                  : _buildPdfSurface(),
            ),

            // --- 2. UI OVERLAYS ---
            if (_currentMode == ViewMode.video && _showControls) _buildVideoControls(),
            if (_currentMode == ViewMode.notes) _buildPdfControls(),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoSurface() {
    if (!_isInitialized) return const Center(child: CircularProgressIndicator(color: neonCyan));
    return Center(
      child: FittedBox(
        fit: _videoFit,
        child: SizedBox(
          width: _controller!.value.size.width,
          height: _controller!.value.size.height,
          child: VideoPlayer(_controller!),
        ),
      ),
    );
  }

  Widget _buildPdfSurface() {
    if (_isLoadingNotes) {
      return Container(
        color: darkSlate,
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: amberAccent, strokeWidth: 2),
              SizedBox(height: 20),
              Text("DECODING DOCUMENT...", style: TextStyle(color: Colors.white60, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 2)),
            ],
          ),
        ),
      );
    }

    if (_pdfController == null) {
      return Container(
        color: darkSlate,
        child: const Center(
          child: Text("SELECT A DOCUMENT FROM PDFs", style: TextStyle(color: Colors.white24, fontWeight: FontWeight.bold, fontSize: 12)),
        ),
      );
    }

    return Container(
      color: darkSlate,
      child: InteractiveViewer(
        maxScale: 4.0,
        minScale: 1.0,
        child: PdfView(
          controller: _pdfController!,
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          onPageChanged: (pageNumber) {
            setState(() {
              _currentPageIndex = pageNumber - 1;
              _totalPagesCount = _pdfController!.pagesCount ?? 0;
            });
          },
          onDocumentLoaded: (document) {
            setState(() {
              _totalPagesCount = document.pagesCount;
            });
          },
          onDocumentError: (error) {
            setState(() => _isLoadingNotes = false);
          },
        ),
      ),
    );
  }

  Widget _buildVideoControls() {
    return Stack(
      children: [
        Container(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black.withValues(alpha: 0.7), Colors.transparent, Colors.black.withValues(alpha: 0.7)]))),
        Positioned(
          top: 20, left: 20, right: 20,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  IconButton(icon: const Icon(Icons.close, color: Colors.white, size: 28), onPressed: () => Navigator.pop(context)),
                  const SizedBox(width: 15),
                  GestureDetector(
                    onTap: () => setState(() => _videoFit = _videoFit == BoxFit.contain ? BoxFit.cover : BoxFit.contain),
                    child: Container(padding: const EdgeInsets.all(5), decoration: BoxDecoration(border: Border.all(color: neonCyan, width: 1), borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.aspect_ratio_rounded, color: neonCyan, size: 18)),
                  ),
                ],
              ),
              Flexible(child: _buildCapsuleControl(Icons.volume_up, _volume, neonCyan, (v) { setState(() => _volume = v); FlutterVolumeController.setVolume(v); })),
            ],
          ),
        ),
        Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _iconBtn(Icons.replay_10, () => _controller?.seekTo(_controller!.value.position - const Duration(seconds: 10))),
              const SizedBox(width: 60),
              GestureDetector(
                onTap: () => setState(() => _controller!.value.isPlaying ? _controller!.pause() : _controller!.play()),
                child: Container(padding: const EdgeInsets.all(18), decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.tealAccent, width: 3)), child: Icon(_controller!.value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.white, size: 45)),
              ),
              const SizedBox(width: 60),
              _iconBtn(Icons.forward_10, () => _controller?.seekTo(_controller!.value.position + const Duration(seconds: 10))),
            ],
          ),
        ),
        Positioned(
          bottom: 20, left: 25, right: 25,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("${widget.subjectCode} : ${widget.unitName}", style: const TextStyle(color: Colors.white70, fontSize: 11)),
              Text(_currentTitle ?? widget.title, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 1)),
              const SizedBox(height: 15),
              Row(
                children: [
                  Text(_formatDuration(_controller?.value.position ?? Duration.zero), style: const TextStyle(color: neonCyan, fontSize: 12, fontWeight: FontWeight.bold)),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(trackHeight: 1.5, activeTrackColor: Colors.white24, inactiveTrackColor: Colors.white12, thumbColor: brightYellow, overlayColor: Colors.transparent, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5, elevation: 0)),
                      child: Slider(value: _controller?.value.position.inSeconds.toDouble() ?? 0, max: _controller?.value.duration.inSeconds.toDouble() ?? 1, onChanged: (v) => _controller?.seekTo(Duration(seconds: v.toInt()))),
                    ),
                  ),
                  Text(_formatDuration(_controller?.value.duration ?? Duration.zero), style: const TextStyle(color: Colors.white38, fontSize: 12)),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      child: Row(
                        children: [
                          _buildChip("PDFs", Icons.description_outlined, _currentMode == ViewMode.notes, () => _showPDFsDrawer()),
                          const SizedBox(width: 12),
                          _buildChip("LECTURES", Icons.menu_book_rounded, _currentMode == ViewMode.video, () => setState(() => _currentMode = ViewMode.video)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildCapsuleControl(Icons.wb_sunny_rounded, _brightness, brightYellow, (v) { setState(() => _brightness = v); ScreenBrightness().setScreenBrightness(v); }), 
                      const SizedBox(width: 20), 
                      _iconBtn(Icons.settings, _showSpeedMenu)
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPdfControls() {
    return Stack(
      children: [
        Positioned(
          top: 0, left: 0, right: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 20),
            decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black.withValues(alpha: 0.8), Colors.transparent])),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      IconButton(icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20), onPressed: () => setState(() => _currentMode = ViewMode.video)),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          "PREVIEWING: COMBINED FULL NOTES", 
                          style: TextStyle(color: neonCyan, fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 1.2),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          bottom: 20, left: 40, right: 40,
          child: Row(
            children: [
              Text("P: ${_currentPageIndex + 1} / $_totalPagesCount", style: const TextStyle(color: brightYellow, fontWeight: FontWeight.bold, fontSize: 12)),
              const SizedBox(width: 20),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(activeTrackColor: amberAccent, thumbColor: amberAccent, inactiveTrackColor: Colors.white12, trackHeight: 3, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7)),
                  child: Slider(
                    value: _currentPageIndex.toDouble(),
                    min: 0,
                    max: _totalPagesCount > 0 ? (_totalPagesCount - 1).toDouble() : 0,
                    onChanged: (val) {
                      if (_pdfController != null) {
                        _pdfController!.jumpToPage(val.toInt() + 1);
                        setState(() => _currentPageIndex = val.toInt());
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showPDFsDrawer() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF000814).withValues(alpha: 0.95),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (c) => StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('content').doc(widget.category).collection('subjects').doc(widget.subjectCode).collection('units').doc(widget.unitName).collection('notes').snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: brightYellow));
          final docs = snapshot.data!.docs;
          if (docs.isEmpty) return const Center(child: Text("No documents found.", style: TextStyle(color: Colors.white38)));
          return ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              return ListTile(
                leading: const Icon(Icons.picture_as_pdf, color: brightYellow, size: 24),
                title: Text(data['title'] ?? "Document", style: const TextStyle(color: Colors.white, fontSize: 13)),
                onTap: () {
                  Navigator.pop(c);
                  _loadPdfDocument(AuthService.decryptLink(data['fileUrl'] ?? ""));
                },
              );
            },
          );
        },
      ),
    );
  }

  void _loadPdfDocument(String url) async {
    setState(() {
      _isLoadingNotes = true;
      _currentMode = ViewMode.notes;
    });

    try {
      _pdfController?.dispose();
      
      // Download PDF data into memory
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        _pdfController = PdfController(
          document: PdfDocument.openData(response.bodyBytes),
        );
        
        if (mounted) {
          setState(() {
            _currentPageIndex = 0;
            _isLoadingNotes = false;
          });
        }
      } else {
        throw Exception("Failed to download PDF");
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingNotes = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Error decoding document. Please try again."))
        );
      }
    }
  }

  Widget _buildCapsuleControl(IconData icon, double value, Color color, ValueChanged<double> onChanged) {
    return Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2), decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(20)), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, color: color, size: 16), SizedBox(width: 80, child: SliderTheme(data: SliderTheme.of(context).copyWith(trackHeight: 1.5, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4), overlayShape: const RoundSliderOverlayShape(overlayRadius: 0)), child: Slider(value: value, activeColor: color, inactiveColor: Colors.white12, onChanged: onChanged)))]));
  }

  Widget _buildChip(String label, IconData icon, bool isActive, VoidCallback onTap) {
    final activeColor = _currentMode == ViewMode.video ? neonCyan : amberAccent;
    return InkWell(onTap: onTap, child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), decoration: BoxDecoration(color: isActive ? Colors.black45 : Colors.transparent, borderRadius: BorderRadius.circular(10), border: Border.all(color: isActive ? activeColor : Colors.white24, width: 1)), child: Row(children: [Icon(icon, color: isActive ? neonCyan : Colors.white, size: 16), const SizedBox(width: 8), Text(label, style: TextStyle(color: isActive ? neonCyan : Colors.white, fontSize: 11, fontWeight: FontWeight.bold))])));
  }

  Widget _iconBtn(IconData icon, VoidCallback onTap) {
    return InkWell(onTap: onTap, child: Icon(icon, color: Colors.white, size: 26));
  }

  void _showSpeedMenu() {
    showModalBottomSheet(context: context, backgroundColor: Colors.grey[900], builder: (c) => ListView(shrinkWrap: true, children: [0.5, 1.0, 1.5, 2.0, 2.5, 3.0].map((s) => ListTile(title: Text("${s}x Speed", style: TextStyle(color: _playbackSpeed == s ? neonCyan : Colors.white)), onTap: () { setState(() { _playbackSpeed = s; _controller?.setPlaybackSpeed(s); }); Navigator.pop(c); })).toList()));
  }
}
