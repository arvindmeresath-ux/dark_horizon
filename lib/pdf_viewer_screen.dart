import 'dart:io';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

class AppPdfViewer extends StatefulWidget {
  final String? pdfUrl;
  final String? filePath;
  final String noteTitle;

  const AppPdfViewer({
    super.key,
    this.pdfUrl,
    this.filePath,
    required this.noteTitle,
  }) : assert(pdfUrl != null || filePath != null, 'Either pdfUrl or filePath must be provided');

  @override
  State<AppPdfViewer> createState() => _AppPdfViewerState();
}

class _AppPdfViewerState extends State<AppPdfViewer> {
  final GlobalKey<SfPdfViewerState> _pdfViewerKey = GlobalKey();
  bool _isLoading = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.noteTitle,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.bookmark, color: Colors.amber),
            onPressed: () {
              _pdfViewerKey.currentState?.openBookmarkView();
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          widget.pdfUrl != null
              ? SfPdfViewer.network(
                  widget.pdfUrl!,
                  key: _pdfViewerKey,
                  onDocumentLoaded: (PdfDocumentLoadedDetails details) {
                    setState(() => _isLoading = false);
                  },
                  onDocumentLoadFailed: (PdfDocumentLoadFailedDetails details) {
                    setState(() => _isLoading = false);
                    _showError(details.description);
                  },
                )
              : SfPdfViewer.file(
                  File(widget.filePath!),
                  key: _pdfViewerKey,
                  onDocumentLoaded: (PdfDocumentLoadedDetails details) {
                    setState(() => _isLoading = false);
                  },
                  onDocumentLoadFailed: (PdfDocumentLoadFailedDetails details) {
                    setState(() => _isLoading = false);
                    _showError(details.description);
                  },
                ),
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(
                color: Colors.amber,
              ),
            ),
        ],
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Failed to load PDF: $message'),
        backgroundColor: Colors.redAccent,
      ),
    );
  }
}
