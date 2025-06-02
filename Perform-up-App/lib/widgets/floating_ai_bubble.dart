import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FloatingAIBubble extends StatefulWidget {
  final VoidCallback onTap;

  const FloatingAIBubble({
    Key? key,
    required this.onTap,
  }) : super(key: key);

  @override
  State<FloatingAIBubble> createState() => _FloatingAIBubbleState();
}

class _FloatingAIBubbleState extends State<FloatingAIBubble> {
  double _size = 60.0;
  double _x = 20.0;
  double _y = 100.0;
  bool _isDragging = false;
  static const String _sizeKey = 'ai_bubble_size';
  static const String _xKey = 'ai_bubble_x';
  static const String _yKey = 'ai_bubble_y';

  @override
  void initState() {
    super.initState();
    _loadBubbleState();
  }

  Future<void> _loadBubbleState() async {
    final prefs = await SharedPreferences.getInstance();
    final mediaQuery = WidgetsBinding.instance.platformDispatcher.views.first.physicalSize.isEmpty
        ? null
        : WidgetsBinding.instance.platformDispatcher.views.first;
    double screenWidth = 0;
    double screenHeight = 0;
    if (mediaQuery != null) {
      screenWidth = mediaQuery.physicalSize.width / mediaQuery.devicePixelRatio;
      screenHeight = mediaQuery.physicalSize.height / mediaQuery.devicePixelRatio;
    }
    const bottomNavBarHeight = 56.0;
    double loadedSize = prefs.getDouble(_sizeKey) ?? 60.0;
    double loadedX = prefs.getDouble(_xKey) ?? 20.0;
    double loadedY = prefs.getDouble(_yKey) ?? 100.0;
    // Clamp loaded position
    if (screenWidth > 0 && screenHeight > 0) {
      loadedX = loadedX.clamp(0.0, screenWidth - loadedSize);
      loadedY = loadedY.clamp(0.0, screenHeight - loadedSize - bottomNavBarHeight);
    }
    setState(() {
      _size = loadedSize;
      _x = loadedX;
      _y = loadedY;
    });
  }

  Future<void> _saveBubbleState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_sizeKey, _size);
    await prefs.setDouble(_xKey, _x);
    await prefs.setDouble(_yKey, _y);
  }

  void _handleDragStart(DragStartDetails details) {
    setState(() {
      _isDragging = true;
    });
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final screenHeight = mediaQuery.size.height;
    const bottomNavBarHeight = 56.0;

    setState(() {
      _x = (_x + details.delta.dx).clamp(0.0, screenWidth - _size);
      _y = (_y + details.delta.dy).clamp(0.0, screenHeight - _size - bottomNavBarHeight);
    });
  }

  void _handleDragEnd(DragEndDetails details) {
    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    // Snap to nearest edge
    double targetX = _x < (screenWidth - _size) / 2 ? 0.0 : (screenWidth - _size);
    setState(() {
      _isDragging = false;
      _x = targetX;
    });
    _saveBubbleState();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: _x,
      top: _y,
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPress: () {
          setState(() {
            if (_size > 60.0) {
              _size = 60.0;
            } else {
              _size = 80.0;
            }
          });
          _saveBubbleState();
        },
        onPanStart: _handleDragStart,
        onPanUpdate: _handleDragUpdate,
        onPanEnd: _handleDragEnd,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: _size,
          height: _size,
          decoration: BoxDecoration(
            color: const Color(0xFF6BBFB5),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.smart_toy,
                color: Colors.white,
                size: _size * 0.4,
              ),
              if (_size > 60.0) ...[
                const SizedBox(height: 4),
                const Text(
                  'AI Help',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
} 