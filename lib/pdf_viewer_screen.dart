import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// PREMIUM PDF VIEWER (EXTERNAL SECTION)
/// Features: Strict Portrait Flow, Sequential Loading, Horizontal Swiping, and Secure External Sharing.
class AppPdfViewer extends StatefulWidget {
  final String? pdfUrl;
  final String? filePath;
  final String noteTitle;

  const AppPdfViewer({
    super.key,
    this.pdfUrl,
    this.filePath,
    required this.noteTitle,
  });

  @override
  State<AppPdfViewer> createState() => _AppPdfViewerState();
}

class _AppPdfViewerState extends State<AppPdfViewer> {
  final PdfViewerController _pdfController = PdfViewerController();
  String? _localPath;
  bool _isDownloading = false;
  String _statusText = "INITIALIZING LINK...";
  double _progress = 0;
  int _totalPages = 0;
  int _currentPage = 1;

  @override
  void initState() {
    super.initState();
    // 1. Strict Portrait Lock on Open
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    if (widget.pdfUrl != null) {
      _downloadFile(widget.pdfUrl!);
    } else {
      _localPath = widget.filePath;
    }
  }

  @override
  void dispose() {
    // 2. Safe Reset on Close
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _downloadFile(String url) async {
    setState(() {
      _isDownloading = true;
      _statusText = "INITIALIZING LINK...";
    });

    try {
      final client = http.Client();
      final request = http.Request('GET', Uri.parse(url));
      final response = await client.send(request);
      
      final contentLength = response.contentLength ?? 0;
      int downloaded = 0;
      final List<int> bytes = [];

      await response.stream.listen((chunk) {
        bytes.addAll(chunk);
        downloaded += chunk.length;
        if (mounted && contentLength > 0) {
          setState(() {
            _progress = downloaded / contentLength;
            _statusText = "DOWNLOADING: ${(_progress * 100).toInt()}%";
          });
        }
      }).asFuture();

      final dir = await getTemporaryDirectory();
      // Use noteTitle for a cleaner filename in the share sheet
      final String safeName = widget.noteTitle.replaceAll(RegExp(r'[^\w\s]+'), '_').replaceAll(' ', '_');
      final file = File("${dir.path}/$safeName.pdf");
      await file.writeAsBytes(bytes);

      if (mounted) {
        setState(() {
          _localPath = file.path;
          _isDownloading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Failed to fetch document. Check connection.")),
        );
        Navigator.pop(context);
      }
    }
  }

  /// SECURE INTERNAL-CACHE-ONLY SHARING LOGIC
  /// Saves the file strictly inside the app's secure temporary cache and shares from there.
  Future<void> _openFileExternallySecurely(String? url, String fileName) async {
    try {
      // 1. Get secure isolated app temporary directory
      final tempDir = await getTemporaryDirectory();
      final String safeName = fileName.replaceAll(RegExp(r'[^\w\s]+'), '_').replaceAll(' ', '_');
      final filePath = "${tempDir.path}/$safeName.pdf";
      final file = File(filePath);

      // 2. Use existing local path if available, otherwise download into cache
      if (_localPath != null && await File(_localPath!).exists()) {
        // Already downloaded in _downloadFile, just ensure the filename matches for the share sheet
        if (_localPath != filePath) {
          await File(_localPath!).copy(filePath);
        }
      } else if (url != null) {
        // Download into temporary cache if it doesn't exist yet
        final response = await http.get(Uri.parse(url));
        await file.writeAsBytes(response.bodyBytes);
      } else {
        throw Exception("No source available to share.");
      }

      // 3. Open OS share sheet directly using the cache path
      await Share.shareXFiles(
        [XFile(filePath)],
        text: 'View Document: $fileName',
      );
    } catch (e) {
      debugPrint("Error sharing file: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error sharing document: ${e.toString()}")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isDownloading) {
      return Scaffold(
        backgroundColor: const Color(0xFF0D0D0D),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(color: Color(0xFFFFB300), strokeWidth: 2),
              const SizedBox(height: 24),
              Text(
                _statusText,
                style: const TextStyle(
                  color: Colors.white, 
                  fontWeight: FontWeight.bold, 
                  letterSpacing: 1.5,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: Stack(
        children: [
          // --- CENTRAL VIEWPORT (Portrait Horizontal Snapping) ---
          if (_localPath != null)
            SfPdfViewer.file(
              File(_localPath!),
              controller: _pdfController,
              scrollDirection: PdfScrollDirection.horizontal,
              pageLayoutMode: PdfPageLayoutMode.single,
              enableDoubleTapZooming: true,
              onDocumentLoaded: (details) {
                setState(() => _totalPages = details.document.pages.count);
              },
              onPageChanged: (details) {
                setState(() => _currentPage = details.newPageNumber);
              },
            ),

          // --- TOP BAR OVERLAY ---
          Positioned(
            top: 0, left: 0, right: 0,
            child: Container(
              padding: const EdgeInsets.only(top: 40, left: 20, right: 10, bottom: 15),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black.withValues(alpha: 0.8), Colors.transparent],
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.noteTitle.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF00F0FF),
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  // SECURE SHARE ACTION
                  IconButton(
                    icon: const Icon(Icons.open_in_new_rounded, color: Color(0xFFFFB300), size: 22),
                    onPressed: () => _openFileExternallySecurely(widget.pdfUrl, widget.noteTitle),
                  ),
                ],
              ),
            ),
          ),

          // --- BOTTOM SYNCED TRACKER ---
          Positioned(
            bottom: 30, left: 25, right: 25,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Expanded(
                        child: Text(
                          "PREVIEWING: FULL NOTES",
                          style: TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        "P: $_currentPage / $_totalPages",
                        style: const TextStyle(
                          color: Color(0xFFFFB300), 
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: const Color(0xFFFFB300),
                      thumbColor: const Color(0xFFFFB300),
                      inactiveTrackColor: Colors.white12,
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 0),
                    ),
                    child: Slider(
                      value: _currentPage.toDouble(),
                      min: 1,
                      max: _totalPages > 0 ? _totalPages.toDouble() : 1,
                      onChanged: (val) {
                        _pdfController.jumpToPage(val.toInt());
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
