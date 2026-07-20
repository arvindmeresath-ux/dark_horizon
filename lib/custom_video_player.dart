import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'radar_sync_service.dart';

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

  // Colors
  static const Color neonCyan = Color(0xFF00F0FF);
  static const Color brightYellow = Color(0xFFFFD600);

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.url;
    _currentTitle = widget.title;
    WidgetsBinding.instance.addObserver(this);
    _setupPlayer();
  }

  void _setupPlayer() async {
    _initializeController(_currentUrl!);
    
    // Open in Portrait initially
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    WakelockPlus.enable();
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
    
    _controller = videoUrl.startsWith('http') 
        ? VideoPlayerController.networkUrl(Uri.parse(videoUrl)) 
        : VideoPlayerController.file(File(videoUrl));
        
    _controller!.initialize().then((_) {
      if (mounted) {
        setState(() { _isInitialized = true; _controller!.play(); });
        _startControlsTimer();
        
        AppRadarSyncService.instance.updateWatchingStatus(
          isWatching: true, 
          lectureTitle: widget.title, 
          unitName: widget.unitName,
          subjectName: widget.subjectCode,
        );
      }
    });
    _controller!.addListener(() { if (mounted) setState(() {}); });
  }

  @override
  void dispose() {
    AppRadarSyncService.instance.updateWatchingStatus(isWatching: false);
    WakelockPlus.disable();
    WidgetsBinding.instance.removeObserver(this);
    _controlsTimer?.cancel();
    _controller?.dispose();
    _resetOrientation();
    super.dispose();
  }

  void _resetOrientation() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
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
    return PopScope(
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) _resetOrientation();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: RepaintBoundary(
          child: SizedBox.expand(
            child: GestureDetector(
              onTap: _toggleControls,
              child: Stack(
                children: [
                  Positioned.fill(child: _buildVideoSurface()),
                  if (_showControls) _buildVideoControls(),
                ],
              ),
            ),
          ),
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
          child: VideoPlayer(_controller!)
        )
      )
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
              Row(children: [
                IconButton(icon: const Icon(Icons.close, color: Colors.white, size: 28), onPressed: () => Navigator.pop(context)),
                const SizedBox(width: 15), 
                GestureDetector(
                  onTap: () async {
                    if (MediaQuery.of(context).orientation == Orientation.portrait) {
                      await SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
                      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
                    } else {
                      await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
                      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
                    }
                    setState(() {});
                  },
                  child: Container(
                    padding: const EdgeInsets.all(5), 
                    decoration: BoxDecoration(border: Border.all(color: neonCyan, width: 1), borderRadius: BorderRadius.circular(8)), 
                    child: const Icon(Icons.screen_rotation_rounded, color: neonCyan, size: 18)
                  )
                ),
                const SizedBox(width: 15), 
                GestureDetector(onTap: () => setState(() => _videoFit = _videoFit == BoxFit.contain ? BoxFit.cover : BoxFit.contain), child: Container(padding: const EdgeInsets.all(5), decoration: BoxDecoration(border: Border.all(color: neonCyan, width: 1), borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.aspect_ratio_rounded, color: neonCyan, size: 18)))]),
              Flexible(child: _buildCapsuleControl(Icons.volume_up, _volume, neonCyan, (v) { setState(() => _volume = v); FlutterVolumeController.setVolume(v); })),
            ],
          ),
        ),
        Center(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          IconButton(icon: const Icon(Icons.replay_10, color: Colors.white, size: 30), onPressed: () => _controller?.seekTo(_controller!.value.position - const Duration(seconds: 10))),
          const SizedBox(width: 60),
          GestureDetector(
            onTap: () {
              if (_controller!.value.isPlaying) {
                _controller!.pause();
                AppRadarSyncService.instance.updateWatchingStatus(isWatching: false);
              } else {
                _controller!.play();
                AppRadarSyncService.instance.updateWatchingStatus(isWatching: true, lectureTitle: _currentTitle ?? widget.title, unitName: widget.unitName, subjectName: widget.subjectCode);
              }
              setState(() {});
            },
            child: Container(padding: const EdgeInsets.all(18), decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.tealAccent, width: 3)), child: Icon(_controller!.value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.white, size: 45)),
          ),
          const SizedBox(width: 60),
          IconButton(icon: const Icon(Icons.forward_10, color: Colors.white, size: 30), onPressed: () => _controller?.seekTo(_controller!.value.position + const Duration(seconds: 10))),
        ])),
        Positioned(
          bottom: 20, left: 25, right: 25,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("${widget.subjectCode} : ${widget.unitName}", style: const TextStyle(color: Colors.white70, fontSize: 11)),
              Text(_currentTitle ?? widget.title, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 1)),
              const SizedBox(height: 15),
              Row(children: [Text(_formatDuration(_controller?.value.position ?? Duration.zero), style: const TextStyle(color: neonCyan, fontSize: 12, fontWeight: FontWeight.bold)), Expanded(child: SliderTheme(data: SliderTheme.of(context).copyWith(trackHeight: 1.5, activeTrackColor: Colors.white24, inactiveTrackColor: Colors.white12, thumbColor: brightYellow, overlayColor: Colors.transparent, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5, elevation: 0)), child: Slider(value: _controller?.value.position.inSeconds.toDouble() ?? 0, max: _controller?.value.duration.inSeconds.toDouble() ?? 1, onChanged: (v) => _controller?.seekTo(Duration(seconds: v.toInt()))))), Text(_formatDuration(_controller?.value.duration ?? Duration.zero), style: const TextStyle(color: Colors.white38, fontSize: 12))]),
              const SizedBox(height: 10),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                Row(mainAxisSize: MainAxisSize.min, children: [
                  _buildCapsuleControl(Icons.wb_sunny_rounded, _brightness, brightYellow, (v) { setState(() => _brightness = v); ScreenBrightness().setScreenBrightness(v); }), 
                  const SizedBox(width: 20), 
                  IconButton(icon: const Icon(Icons.settings, color: Colors.white, size: 26), onPressed: _showSpeedMenu)
                ])
              ]),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCapsuleControl(IconData icon, double value, Color color, ValueChanged<double> onChanged) {
    return Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2), decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(20)), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, color: color, size: 16), SizedBox(width: 80, child: SliderTheme(data: SliderTheme.of(context).copyWith(trackHeight: 1.5, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4), overlayShape: const RoundSliderOverlayShape(overlayRadius: 0)), child: Slider(value: value, activeColor: color, inactiveColor: Colors.white12, onChanged: onChanged)))]));
  }

  void _showSpeedMenu() {
    showModalBottomSheet(context: context, backgroundColor: Colors.grey[900], builder: (c) => ListView(shrinkWrap: true, children: [0.5, 1.0, 1.5, 2.0, 2.5, 3.0].map((s) => ListTile(title: Text("${s}x Speed", style: TextStyle(color: _playbackSpeed == s ? neonCyan : Colors.white)), onTap: () { setState(() { _playbackSpeed = s; _controller?.setPlaybackSpeed(s); }); Navigator.pop(c); })).toList()));
  }
}
