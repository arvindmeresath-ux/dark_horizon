import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:screen_protector/screen_protector.dart';

class MXStylePlayer extends StatefulWidget {
  final String url;
  final String title;
  final String subjectCode;
  final String unitName;

  const MXStylePlayer({
    super.key,
    required this.url,
    required this.title,
    required this.subjectCode,
    required this.unitName,
  });

  @override
  State<MXStylePlayer> createState() => _MXStylePlayerState();
}

class _MXStylePlayerState extends State<MXStylePlayer> with WidgetsBindingObserver {
  late VideoPlayerController _controller;
  bool _isInitialized = false;
  bool _showControls = true;
  bool _isFullScreen = false;
  Timer? _controlsTimer;

  double _volume = 0.5;
  double _brightness = 0.5;
  String _overlayText = "";
  IconData? _overlayIcon;
  Timer? _overlayTimer;

  double _playbackSpeed = 1.0;
  BoxFit _videoFit = BoxFit.contain;

  // For Double Tap Animation
  bool _showForwardIcon = false;
  bool _showBackwardIcon = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ScreenProtector.preventScreenshotOn();
    _initializeController();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      if (_isInitialized && _controller.value.isPlaying) {
        _controller.pause();
      }
    }
  }

  void _initializeController() async {
    String videoUrl = widget.url;

    if (videoUrl.contains("youtube.com") || videoUrl.contains("youtu.be")) {
      try {
        var yt = YoutubeExplode();
        var videoId = videoUrl.contains("youtu.be") 
            ? videoUrl.split("/").last.split("?").first
            : videoUrl.split("v=")[1].split("&")[0];
            
        var manifest = await yt.videos.streamsClient.getManifest(videoId);
        var streamInfo = manifest.muxed.withHighestBitrate();
        videoUrl = streamInfo.url.toString();
        yt.close();
      } catch (e) {
        debugPrint("YouTube Error: $e");
      }
    }

    if (videoUrl.startsWith('http')) {
      _controller = VideoPlayerController.networkUrl(Uri.parse(videoUrl));
    } else {
      _controller = VideoPlayerController.file(File(videoUrl));
    }

    _controller.initialize().then((_) {
      if (mounted) {
        setState(() {
          _isInitialized = true;
          _controller.play();
        });
        _startControlsTimer();
      }
    }).catchError((error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Error loading video.")));
      }
    });

    _controller.addListener(() {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ScreenProtector.preventScreenshotOff();
    _controlsTimer?.cancel();
    _overlayTimer?.cancel();
    _controller.dispose();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _startControlsTimer() {
    _controlsTimer?.cancel();
    _controlsTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _controller.value.isPlaying) {
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

  void _onVerticalDrag(DragUpdateDetails details, bool isLeft) async {
    double delta = -details.primaryDelta! / 200;
    if (isLeft) {
      _brightness = (_brightness + delta).clamp(0.0, 1.0);
      await ScreenBrightness().setScreenBrightness(_brightness);
      _showOverlay("${(_brightness * 100).toInt()}%", Icons.brightness_6);
    } else {
      _volume = (_volume + delta).clamp(0.0, 1.0);
      await FlutterVolumeController.setVolume(_volume);
      _showOverlay("${(_volume * 100).toInt()}%", Icons.volume_up);
    }
  }

  void _showOverlay(String text, IconData icon) {
    setState(() { _overlayText = text; _overlayIcon = icon; });
    _overlayTimer?.cancel();
    _overlayTimer = Timer(const Duration(milliseconds: 600), () {
      if (mounted) {
        setState(() => _overlayIcon = null);
      }
    });
  }

  void _skip(int seconds) {
    final newPos = _controller.value.position + Duration(seconds: seconds);
    _controller.seekTo(newPos);
    
    // Animation Feedback
    setState(() {
      if (seconds > 0) {
        _showForwardIcon = true;
      } else {
        _showBackwardIcon = true;
      }
    });
    
    Timer(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() { _showForwardIcon = false; _showBackwardIcon = false; });
      }
    });
  }

  void _toggleOrientation() {
    setState(() {
      _isFullScreen = !_isFullScreen;
      if (_isFullScreen) {
        SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      } else {
        SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        top: !_isFullScreen,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final double videoHeight = _isFullScreen ? constraints.maxHeight : constraints.maxWidth * 9 / 16;
            return Column(
              children: [
                SizedBox(
                  width: constraints.maxWidth,
                  height: videoHeight,
                  child: Stack(
                    children: [
                      // 1. VIDEO LAYER
                      if (_isInitialized)
                        Center(child: FittedBox(fit: _videoFit, child: SizedBox(width: _controller.value.size.width, height: _controller.value.size.height, child: VideoPlayer(_controller))))
                      else
                        const Center(child: CircularProgressIndicator(color: Colors.amber)),

                      // 2. GESTURE INTERCEPTOR (Invisible)
                      Row(
                        children: [
                          Expanded(child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: _toggleControls,
                            onDoubleTap: () => _skip(-10),
                            onVerticalDragUpdate: (d) => _onVerticalDrag(d, true),
                            child: Container(color: Colors.transparent),
                          )),
                          Expanded(child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: _toggleControls,
                            onDoubleTap: () => _skip(10),
                            onVerticalDragUpdate: (d) => _onVerticalDrag(d, false),
                            child: Container(color: Colors.transparent),
                          )),
                        ],
                      ),

                      // 3. ANIMATED OVERLAYS (Double Tap Ripple)
                      if (_showBackwardIcon) _buildSkipRipple(isForward: false),
                      if (_showForwardIcon) _buildSkipRipple(isForward: true),

                      // 4. BRIGHTNESS/VOLUME INDICATOR
                      if (_overlayIcon != null)
                        Center(child: Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)), child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(_overlayIcon, color: Colors.amber, size: 40), const SizedBox(height: 8), Text(_overlayText, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))]))),

                      // 5. UI CONTROLS (Top Layer)
                      if (_isInitialized && _showControls) ...[
                        _buildHeader(),
                        Center(child: _buildPlayButton()),
                        Positioned(bottom: 0, left: 0, right: 0, child: Column(mainAxisSize: MainAxisSize.min, children: [_buildUtilityRow(), _buildSeekBar()])),
                      ],
                    ],
                  ),
                ),
                if (!_isFullScreen) _buildDetails(),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildSkipRipple({required bool isForward}) {
    return Align(
      alignment: isForward ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        width: MediaQuery.of(context).size.width / 3,
        height: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.horizontal(
            left: isForward ? const Radius.circular(100) : Radius.zero,
            right: isForward ? Radius.zero : const Radius.circular(100),
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(isForward ? Icons.fast_forward_rounded : Icons.fast_rewind_rounded, color: Colors.white, size: 40),
              Text(isForward ? "+10s" : "-10s", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlayButton() {
    return GestureDetector(
      onTap: () => setState(() => _controller.value.isPlaying ? _controller.pause() : _controller.play()),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.tealAccent.withValues(alpha: 0.1), // Soft glow
          shape: BoxShape.circle, 
          border: Border.all(color: Colors.tealAccent.withValues(alpha: 0.3), width: 1.5)
        ),
        child: Icon(
          _controller.value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, 
          color: Colors.tealAccent, 
          size: 45
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black87, Colors.transparent])),
      child: Row(children: [
        IconButton(icon: const Icon(Icons.arrow_back, color: Colors.tealAccent), onPressed: () => Navigator.pop(context)), 
        Expanded(child: Text(widget.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis))
      ]),
    );
  }

  Widget _buildUtilityRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(children: [
            _iconBtn(Icons.aspect_ratio, () => setState(() => _videoFit = _videoFit == BoxFit.contain ? BoxFit.cover : BoxFit.contain), "Fit", Colors.tealAccent),
            const SizedBox(width: 20),
            _iconBtn(Icons.speed, _showSpeedMenu, "${_playbackSpeed}x", Colors.tealAccent),
          ]),
          _iconBtn(_isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen, _toggleOrientation, "", Colors.tealAccent),
        ],
      ),
    );
  }

  Widget _iconBtn(IconData icon, VoidCallback onTap, String label, Color color) {
    return GestureDetector(onTap: onTap, child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(icon, color: color, size: 22), if (label.isNotEmpty) Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold))]));
  }

  Widget _buildSeekBar() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_formatDuration(_controller.value.position), style: const TextStyle(color: Colors.tealAccent, fontSize: 10, fontWeight: FontWeight.bold)),
              Text(_formatDuration(_controller.value.duration), style: const TextStyle(color: Colors.white54, fontSize: 10)),
            ],
          ),
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 2.0,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
            thumbColor: Colors.tealAccent,
            activeTrackColor: Colors.yellowAccent,
            inactiveTrackColor: Colors.white12,
            trackShape: const RectangularSliderTrackShape(),
          ),
          child: SizedBox(
            height: 20,
            child: Slider(
              value: _controller.value.position.inSeconds.toDouble(),
              max: _controller.value.duration.inSeconds.toDouble() > 0 ? _controller.value.duration.inSeconds.toDouble() : 1.0,
              onChanged: (v) => _controller.seekTo(Duration(seconds: v.toInt())),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDetails() {
    return Expanded(child: Container(padding: const EdgeInsets.all(24), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(widget.subjectCode, style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)), const SizedBox(height: 8), Text(widget.title, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)), Text(widget.unitName, style: const TextStyle(color: Colors.white38))])));
  }

  void _showSpeedMenu() {
    showModalBottomSheet(context: context, backgroundColor: Colors.grey[900], builder: (c) => ListView(shrinkWrap: true, children: [0.5, 1.0, 1.5, 2.0, 2.5, 3.0].map((s) => ListTile(title: Text("${s}x Speed", style: TextStyle(color: _playbackSpeed == s ? Colors.tealAccent : Colors.white)), onTap: () { setState(() { _playbackSpeed = s; _controller.setPlaybackSpeed(s); }); Navigator.pop(c); })).toList()));
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return "${twoDigits(d.inMinutes)}:${twoDigits(d.inSeconds.remainder(60))}";
  }
}
