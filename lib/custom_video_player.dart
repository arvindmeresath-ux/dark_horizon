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
      if (mounted && _controller!.value.isPlaying) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
      if (_showControls) {
        _startControlsTimer();
      }
    });
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return "${twoDigits(d.inMinutes)}:${twoDigits(d.inSeconds.remainder(60))}";
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) {
          _resetOrientation();
        }
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
    if (!_isInitialized) {
      return const Center(child: CircularProgressIndicator(color: neonCyan));
    }
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
        // Dark Gradient Overlay
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.8),
                Colors.transparent,
                Colors.transparent,
                Colors.black.withValues(alpha: 0.8),
              ],
            ),
          ),
        ),

        // 1. TOP BAR: Close & Title Info
        Positioned(
          top: MediaQuery.of(context).padding.top + 10,
          left: 20, right: 20,
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 22),
                onPressed: () => Navigator.pop(context),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.subjectCode.toUpperCase(),
                      style: const TextStyle(color: neonCyan, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.5),
                    ),
                    Text(
                      _currentTitle ?? widget.title,
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // 2. SIDE CONTROLS: Brightness (Left) & Volume (Right)
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Brightness Capsule
                RotatedBox(
                  quarterTurns: 3,
                  child: _buildCapsuleControl(Icons.wb_sunny_rounded, _brightness, brightYellow, (v) {
                    setState(() => _brightness = v);
                    ScreenBrightness().setScreenBrightness(v);
                  }),
                ),
                // Volume Capsule
                RotatedBox(
                  quarterTurns: 3,
                  child: _buildCapsuleControl(Icons.volume_up_rounded, _volume, neonCyan, (v) {
                    setState(() => _volume = v);
                    FlutterVolumeController.setVolume(v);
                  }),
                ),
              ],
            ),
          ),
        ),

        // 3. CENTER PLAYBACK CONTROLS
        Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.replay_10_rounded, color: Colors.white, size: 35),
                onPressed: () => _controller?.seekTo(_controller!.value.position - const Duration(seconds: 10)),
              ),
              const SizedBox(width: 40),
              GestureDetector(
                onTap: () {
                  if (_controller!.value.isPlaying) {
                    _controller!.pause();
                    AppRadarSyncService.instance.updateWatchingStatus(isWatching: false);
                  } else {
                    _controller!.play();
                    AppRadarSyncService.instance.updateWatchingStatus(
                      isWatching: true, 
                      lectureTitle: _currentTitle ?? widget.title, 
                      unitName: widget.unitName, 
                      subjectName: widget.subjectCode
                    );
                  }
                  setState(() {});
                },
                child: Container(
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                    border: Border.all(color: neonCyan.withValues(alpha: 0.5), width: 2),
                  ),
                  child: Icon(
                    _controller!.value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 50,
                  ),
                ),
              ),
              const SizedBox(width: 40),
              IconButton(
                icon: const Icon(Icons.forward_10_rounded, color: Colors.white, size: 35),
                onPressed: () => _controller?.seekTo(_controller!.value.position + const Duration(seconds: 10)),
              ),
            ],
          ),
        ),

        // 4. BOTTOM SECTION: Seekbar & Utility Buttons
        Positioned(
          bottom: 20, left: 20, right: 20,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Seek Bar
              Row(
                children: [
                  Text(_formatDuration(_controller?.value.position ?? Duration.zero), 
                    style: const TextStyle(color: neonCyan, fontSize: 11, fontWeight: FontWeight.bold)),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 2,
                        activeTrackColor: neonCyan,
                        inactiveTrackColor: Colors.white24,
                        thumbColor: Colors.white,
                        overlayColor: neonCyan.withValues(alpha: 0.2),
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                      ),
                      child: Slider(
                        value: _controller?.value.position.inSeconds.toDouble() ?? 0,
                        max: _controller?.value.duration.inSeconds.toDouble() ?? 1,
                        onChanged: (v) => _controller?.seekTo(Duration(seconds: v.toInt())),
                      ),
                    ),
                  ),
                  Text(_formatDuration(_controller?.value.duration ?? Duration.zero), 
                    style: const TextStyle(color: Colors.white60, fontSize: 11)),
                ],
              ),
              const SizedBox(height: 10),
              // Utility Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Unit Name Label
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(8)),
                    child: Text(widget.unitName, style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                  // Action Buttons
                  Row(
                    children: [
                      _buildSmallIconButton(Icons.settings_outlined, _showSpeedMenu),
                      const SizedBox(width: 15),
                      _buildSmallIconButton(Icons.aspect_ratio_rounded, () {
                        setState(() => _videoFit = _videoFit == BoxFit.contain ? BoxFit.cover : BoxFit.contain);
                      }),
                      const SizedBox(width: 15),
                      _buildSmallIconButton(Icons.screen_rotation_rounded, () async {
                        if (MediaQuery.of(context).orientation == Orientation.portrait) {
                          await SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
                          await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
                        } else {
                          await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
                          await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
                        }
                        setState(() {});
                      }),
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

  Widget _buildSmallIconButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white24),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }

  Widget _buildCapsuleControl(IconData icon, double value, Color color, ValueChanged<double> onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          SizedBox(
            width: 100,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 0),
                activeTrackColor: color,
                inactiveTrackColor: Colors.white12,
                thumbColor: Colors.white,
              ),
              child: Slider(value: value, onChanged: onChanged),
            ),
          ),
        ],
      ),
    );
  }

  void _showSpeedMenu() {
    showModalBottomSheet(context: context, backgroundColor: Colors.grey[900], builder: (c) => ListView(shrinkWrap: true, children: [0.5, 1.0, 1.5, 2.0, 2.5, 3.0].map((s) => ListTile(title: Text("${s}x Speed", style: TextStyle(color: _playbackSpeed == s ? neonCyan : Colors.white)), onTap: () { setState(() { _playbackSpeed = s; _controller?.setPlaybackSpeed(s); }); Navigator.pop(c); })).toList()));
  }
}
