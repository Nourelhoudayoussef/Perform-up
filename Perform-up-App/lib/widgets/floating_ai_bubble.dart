import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class FloatingAIBubble extends StatefulWidget {
  final VoidCallback onTap;
  const FloatingAIBubble({Key? key, required this.onTap}) : super(key: key);

  @override
  State<FloatingAIBubble> createState() => _FloatingAIBubbleState();
}

class _FloatingAIBubbleState extends State<FloatingAIBubble> with SingleTickerProviderStateMixin {
  Offset position = const Offset(20, 500);
  late double screenWidth;
  late double screenHeight;
  bool isDragging = false;
  bool isVisible = true;

  void hideBubble() {
    setState(() {
      isVisible = false;
    });
  }

  void showBubble() {
    setState(() {
      isVisible = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    screenWidth = MediaQuery.of(context).size.width;
    screenHeight = MediaQuery.of(context).size.height;

    if (!isVisible) {
      return Positioned(
        right: 16,
        bottom: 16,
        child: FloatingActionButton(
          onPressed: showBubble,
          backgroundColor: const Color(0xFF6BBFB5),
          child: const Icon(Icons.smart_toy, color: Colors.white),
        ),
      );
    }

    return Positioned(
      left: position.dx,
      top: position.dy,
      child: GestureDetector(
        onPanStart: (_) => setState(() => isDragging = true),
        onPanUpdate: (details) {
          setState(() {
            position = Offset(
              (position.dx + details.delta.dx).clamp(0, screenWidth - 80),
              (position.dy + details.delta.dy).clamp(0, screenHeight - 80),
            );
          });
        },
        onPanEnd: (_) {
          setState(() => isDragging = false);
          // Snap to nearest edge
          final snapX = position.dx < screenWidth / 2 ? 16.0 : screenWidth - 80 - 16.0;
          setState(() {
            position = Offset(snapX, position.dy);
          });
        },
        child: AnimatedScale(
          scale: isDragging ? 1.1 : 1.0,
          duration: const Duration(milliseconds: 150),
          child: Material(
            elevation: 8,
            shape: const CircleBorder(),
            color: const Color(0xFF6BBFB5),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: widget.onTap,
              onLongPress: hideBubble,
              child: Container(
                width: 80,
                height: 80,
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.smart_toy, color: Colors.white, size: 32),
                    const SizedBox(height: 4),
                    Text(
                      'AI Help',
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
} 