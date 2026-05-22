import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

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

class _MXStylePlayerState extends State<MXStylePlayer> {
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

  @override
  void initState() {
    super.initState();
    _initializeController();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
  }

  void _initializeController() async {
    String videoUrl = widget.url;

    // YouTube Stream Extraction Logic
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
      debugPrint("Video Init Error: $error");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Error loading video. Please check your connection.")),
        );
      }
    });

    _controller.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _controlsTimer?.cancel();
    _overlayTimer?.cancel();
    _controller.dispose();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _startControlsTimer() {
    _controlsTimer?.cancel();
    _controlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _controller.value.isPlaying) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
      if (_showControls) _startControlsTimer();
    });
  }

  void _showOverlay(String text, IconData icon) {
    setState(() {
      _overlayText = text;
      _overlayIcon = icon;
    });
    _overlayTimer?.cancel();
    _overlayTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) setState(() => _overlayIcon = null);
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

  void _skip(int seconds) {
    final newPos = _controller.value.position + Duration(seconds: seconds);
    _controller.seekTo(newPos);
    _showOverlay("${seconds > 0 ? '+' : ''}$seconds s", seconds > 0 ? Icons.fast_forward : Icons.fast_rewind);
  }

  void _toggleFit() {
    setState(() {
      if (_videoFit == BoxFit.contain) _videoFit = BoxFit.cover;
      else if (_videoFit == BoxFit.cover) _videoFit = BoxFit.fill;
      else _videoFit = BoxFit.contain;
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
                      // Video Content
                      if (_isInitialized)
                        Center(
                          child: FittedBox(
                            fit: _videoFit,
                            child: SizedBox(
                              width: _controller.value.size.width,
                              height: _controller.value.size.height,
                              child: VideoPlayer(_controller),
                            ),
                          ),
                        )
                      else
                        const Center(child: CircularProgressIndicator(color: Colors.amber)),

                      // Gesture Layers
                      Row(
                        children: [
                          Expanded(child: GestureDetector(
                            onVerticalDragUpdate: (d) => _onVerticalDrag(d, true),
                            onDoubleTap: () => _skip(-10),
                            onTap: _toggleControls,
                          )),
                          Expanded(child: GestureDetector(
                            onVerticalDragUpdate: (d) => _onVerticalDrag(d, false),
                            onDoubleTap: () => _skip(10),
                            onTap: _toggleControls,
                          )),
                        ],
                      ),

                      // Overlay Indicators (Volume/Brightness)
                      if (_overlayIcon != null)
                        Center(
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(_overlayIcon, color: Colors.amber, size: 40),
                                const SizedBox(height: 8),
                                Text(_overlayText, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        ),

                      // UI CONTROLS
                      if (_isInitialized && _showControls) ...[
                        // Header
                        _buildHeader(),
                        
                        // Center Play/Pause (PREMIUM LOOK)
                        Center(child: _buildPremiumPlayButton()),

                        // Bottom Controls Layer
                        Positioned(
                          bottom: 0, left: 0, right: 0,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildUtilityRow(),
                              _buildPremiumSeekBar(),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                
                // Content Details below player (Portrait only)
                if (!_isFullScreen) _buildDetailsSection(),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildPremiumPlayButton() {
    return GestureDetector(
      onTap: () {
        setState(() => _controller.value.isPlaying ? _controller.pause() : _controller.play());
        _startControlsTimer();
      },
      child: Container(
        height: 70, width: 70,
        decoration: BoxDecoration(
          color: Colors.cyanAccent.withValues(alpha: 0.1),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.3), width: 1.5),
          boxShadow: [
            BoxShadow(color: Colors.cyanAccent.withValues(alpha: 0.1), blurRadius: 15, spreadRadius: 1)
          ],
        ),
        child: Icon(
          _controller.value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
          color: Colors.cyanAccent, size: 45,
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black87, Colors.transparent])),
      child: Row(
        children: [
          IconButton(icon: const Icon(Icons.arrow_back, color: Colors.yellowAccent), onPressed: () => Navigator.pop(context)),
          Expanded(child: Text(widget.title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }

  Widget _buildUtilityRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Left Side: Fit & Speed
          Row(
            children: [
              _iconButton(Icons.aspect_ratio_rounded, _toggleFit, "Fit", Colors.yellowAccent),
              const SizedBox(width: 25),
              _iconButton(Icons.speed_rounded, _showSpeedMenu, "${_playbackSpeed}x", Colors.cyanAccent),
            ],
          ),
          // Right Side: Orientation
          _iconButton(_isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen, _toggleOrientation, "", Colors.yellowAccent),
        ],
      ),
    );
  }

  Widget _iconButton(IconData icon, VoidCallback onTap, String label, Color color) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 22),
          if (label.isNotEmpty) Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildPremiumSeekBar() {
    return Container(
      color: Colors.black45,
      padding: const EdgeInsets.only(bottom: 2), 
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_formatDuration(_controller.value.position), style: const TextStyle(color: Colors.cyanAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                Text(_formatDuration(_controller.value.duration), style: const TextStyle(color: Colors.yellowAccent, fontSize: 11, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2.5,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              thumbColor: Colors.cyanAccent,
              activeTrackColor: Colors.yellowAccent,
              inactiveTrackColor: Colors.white12,
            ),
            child: Slider(
              value: _controller.value.position.inSeconds.toDouble(),
              max: _controller.value.duration.inSeconds.toDouble(),
              onChanged: (v) => _controller.seekTo(Duration(seconds: v.toInt())),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsSection() {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.subjectCode, style: const TextStyle(color: Colors.yellowAccent, fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 8),
            Text(widget.title, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
            Text(widget.unitName, style: const TextStyle(color: Colors.cyanAccent, fontSize: 14)),
          ],
        ),
      ),
    );
  }

  void _showSpeedMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (c) => Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [0.5, 1.0, 1.5, 2.0, 2.5, 3.0].map((s) => ListTile(
              dense: true,
              title: Text("${s}x Speed", style: TextStyle(color: _playbackSpeed == s ? Colors.yellowAccent : Colors.white, fontWeight: _playbackSpeed == s ? FontWeight.bold : FontWeight.normal)),
              trailing: _playbackSpeed == s ? const Icon(Icons.check, color: Colors.cyanAccent, size: 18) : null,
              onTap: () {
                setState(() { _playbackSpeed = s; _controller.setPlaybackSpeed(s); });
                Navigator.pop(c);
              },
            )).toList(),
          ),
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return "${twoDigits(d.inMinutes)}:${twoDigits(d.inSeconds.remainder(60))}";
  }
}
