import 'dart:async';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityWrapper extends StatefulWidget {
  final Widget child;
  const ConnectivityWrapper({super.key, required this.child});

  @override
  State<ConnectivityWrapper> createState() => _ConnectivityWrapperState();
}

class _ConnectivityWrapperState extends State<ConnectivityWrapper> with SingleTickerProviderStateMixin {
  late StreamSubscription<List<ConnectivityResult>> _subscription;
  bool _isOffline = false;
  late AnimationController _flashController;

  @override
  void initState() {
    super.initState();
    
    // Setup Neon Flashing Animation
    _flashController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);

    // Initial check
    _checkInitialConnection();

    // Listen for real-time changes
    _subscription = Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> result) {
      _updateStatus(result);
    });
  }

  Future<void> _checkInitialConnection() async {
    final result = await Connectivity().checkConnectivity();
    _updateStatus(result);
  }

  void _updateStatus(List<ConnectivityResult> result) {
    bool offline = result.contains(ConnectivityResult.none);
    if (offline != _isOffline) {
      setState(() => _isOffline = offline);
    }
  }

  @override
  void dispose() {
    _subscription.cancel();
    _flashController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        
        // Floating Sleek Banner
        AnimatedPositioned(
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOutBack,
          top: _isOffline ? MediaQuery.of(context).padding.top + 10 : -100,
          left: 20,
          right: 20,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF000814),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.8), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.cyanAccent.withValues(alpha: 0.2),
                    blurRadius: 15,
                    spreadRadius: 2,
                  )
                ],
              ),
              child: Row(
                children: [
                  const Icon(Icons.wifi_off_rounded, color: Colors.cyanAccent, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FadeTransition(
                      opacity: _flashController,
                      child: const Text(
                        "CONNECTION INTERRUPTED || ACCESSING CACHED DATA",
                        style: TextStyle(
                          color: Colors.cyanAccent,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.1,
                          fontFamily: 'monospace', // Gives a system-access look
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
