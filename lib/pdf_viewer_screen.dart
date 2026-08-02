import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
// ignore: unused_import
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;

/// PREMIUM PDF VIEWER (EXTERNAL SECTION)
/// Features: Vertical Flow, Sequential Loading, 3-Dot Menu (Share, Save, Open With).
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
  final ValueNotifier<int> _currentPageNotifier = ValueNotifier<int>(1);
  final ValueNotifier<int> _totalPagesNotifier = ValueNotifier<int>(0);
  
  String? _localPath;
  final bool _isDownloading = false;
  final String _statusText = "INITIALIZING LINK...";

  @override
  void initState() {
    super.initState();
    // Force Portrait for reading
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    if (widget.pdfUrl != null) {
      // No manual download needed anymore, SfPdfViewer handles it via network
    } else {
      _localPath = widget.filePath;
    }
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }



  // --- 3-DOT MENU ACTIONS ---

  void _shareFile() async {
    if (_localPath == null) {
      return;
    }
    await Share.shareXFiles([XFile(_localPath!)], text: widget.noteTitle);
  }

  void _saveToDevice() async {
    if (_localPath == null) {
      return;
    }
    try {
      Directory? downloadsDir;
      if (Platform.isAndroid) {
        downloadsDir = Directory('/storage/emulated/0/Download');
      } else {
        downloadsDir = await getApplicationDocumentsDirectory();
      }

      if (!await downloadsDir.exists()) {
        downloadsDir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
      }

      final String fileName = "${widget.noteTitle.replaceAll(' ', '_')}.pdf";
      final String destinationPath = p.join(downloadsDir.path, fileName);
      
      await File(_localPath!).copy(destinationPath);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Saved to: $destinationPath"), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to save: $e"), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  void _openWithExternalApp() async {
    if (_localPath == null) {
      return;
    }
    final result = await OpenFilex.open(_localPath!);
    if (result.type != ResultType.done && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("No app found to open PDF: ${result.message}")),
      );
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
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.5, fontSize: 12),
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
          // --- CENTRAL VIEWPORT (Vertical Flow) ---
          RepaintBoundary(
            child: widget.filePath != null
              ? SfPdfViewer.file(
                  File(widget.filePath!),
                  controller: _pdfController,
                  scrollDirection: PdfScrollDirection.vertical,
                  pageLayoutMode: PdfPageLayoutMode.continuous,
                  enableDoubleTapZooming: true,
                  enableTextSelection: false,
                  canShowPaginationDialog: false,
                  onDocumentLoaded: (details) {
                    _totalPagesNotifier.value = details.document.pages.count;
                  },
                  onPageChanged: (details) {
                    _currentPageNotifier.value = details.newPageNumber;
                  },
                )
              : SfPdfViewer.network(
                  widget.pdfUrl!,
                  controller: _pdfController,
                  scrollDirection: PdfScrollDirection.vertical,
                  pageLayoutMode: PdfPageLayoutMode.continuous,
                  enableDoubleTapZooming: true,
                  enableTextSelection: false,
                  canShowPaginationDialog: false,
                  onDocumentLoaded: (details) {
                    _totalPagesNotifier.value = details.document.pages.count;
                  },
                  onPageChanged: (details) {
                    _currentPageNotifier.value = details.newPageNumber;
                  },
                ),
          ),

          // --- TOP BAR OVERLAY ---
          Positioned(
            top: 0, left: 0, right: 0,
            child: RepaintBoundary(
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
                        style: const TextStyle(color: Color(0xFF00F0FF), fontWeight: FontWeight.w900, letterSpacing: 1.2, fontSize: 13),
                      ),
                    ),
                    
                    // 3-DOT MENU
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, color: Color(0xFFFFB300)),
                      color: const Color(0xFF1A1A1A),
                      onSelected: (value) {
                        if (value == 'share') {
                          _shareFile();
                        }
                        if (value == 'save') {
                          _saveToDevice();
                        }
                        if (value == 'open') {
                          _openWithExternalApp();
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(value: 'share', child: Row(children: [Icon(Icons.share, color: Colors.white, size: 18), SizedBox(width: 12), Text("Share", style: TextStyle(color: Colors.white, fontSize: 13))])),
                        const PopupMenuItem(value: 'save', child: Row(children: [Icon(Icons.save_alt, color: Colors.white, size: 18), SizedBox(width: 12), Text("Save to Device", style: TextStyle(color: Colors.white, fontSize: 13))])),
                        const PopupMenuItem(value: 'open', child: Row(children: [Icon(Icons.open_in_new, color: Colors.white, size: 18), SizedBox(width: 12), Text("Open With...", style: TextStyle(color: Colors.white, fontSize: 13))])),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          // --- BOTTOM SYNCED TRACKER ---
          Positioned(
            bottom: 30, left: 25, right: 25,
            child: RepaintBoundary(
              child: ValueListenableBuilder<int>(
                valueListenable: _totalPagesNotifier,
                builder: (context, totalPages, _) {
                  if (totalPages == 0) {
                    return const SizedBox.shrink();
                  }
                  return ValueListenableBuilder<int>(
                    valueListenable: _currentPageNotifier,
                    builder: (context, currentPage, _) {
                      return Container(
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
                                  "P: $currentPage / $totalPages",
                                  style: const TextStyle(color: Color(0xFFFFB300), fontWeight: FontWeight.w900, fontSize: 12),
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
                                value: currentPage.toDouble().clamp(1.0, totalPages.toDouble()),
                                min: 1,
                                max: totalPages.toDouble(),
                                onChanged: (val) {
                                  _pdfController.jumpToPage(val.toInt());
                                },
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                  );
                }
              ),
            ),
          ),
        ],
      ),
    );
  }
}
