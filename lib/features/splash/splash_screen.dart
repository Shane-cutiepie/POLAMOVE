import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/constants/app_colors.dart';
import '../../core/services/auth_service.dart';
import '../driver/driver_home_screen.dart';
import '../passenger/passenger_home_screen.dart';
import '../role_selection/role_selection_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _fadeUpController;
  late AnimationController _trikeController;
  late AnimationController _wheelController;
  late AnimationController _tagController;

  late Animation<double> _fadeUpOpacity;
  late Animation<Offset> _fadeUpSlide;
  late Animation<double> _trikeOpacity;
  late Animation<Offset> _trikeSlide;
  late Animation<double> _wheelSpin;
  late Animation<double> _tagOpacity;
  late Animation<Offset> _tagSlide;

  @override
  void initState() {
    super.initState();

    // Trike slide in
    _trikeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _trikeOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _trikeController, curve: Curves.easeOut),
    );
    _trikeSlide = Tween<Offset>(
      begin: const Offset(-0.6, 0),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
          parent: _trikeController,
          curve: const Cubic(0.34, 1.1, 0.64, 1)),
    );

    // Fade up for logo row
    _fadeUpController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    );
    _fadeUpOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _fadeUpController, curve: Curves.easeOut),
    );
    _fadeUpSlide = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
          parent: _fadeUpController,
          curve: const Cubic(0.34, 1.2, 0.64, 1)),
    );

    // Wheel spin
    _wheelController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _wheelSpin = Tween<double>(begin: -1.0, end: 0.0).animate(
      CurvedAnimation(
          parent: _wheelController,
          curve: const Cubic(0.25, 0.46, 0.45, 0.94)),
    );

    // Tag fade up
    _tagController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _tagOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _tagController, curve: Curves.easeOut),
    );
    _tagSlide = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
          parent: _tagController,
          curve: const Cubic(0.34, 1.2, 0.64, 1)),
    );

    // Start animation sequence
    _runAnimations();
  }

  Future<void> _runAnimations() async {
    await Future.delayed(const Duration(milliseconds: 50));
    _trikeController.forward();
    await Future.delayed(const Duration(milliseconds: 120));
    _fadeUpController.forward();
    _wheelController.forward();
    await Future.delayed(const Duration(milliseconds: 600));
    _tagController.forward();

    // Navigate after 2.5s
    await Future.delayed(const Duration(milliseconds: 1800));
    await _route();
  }

  Future<void> _route() async {
    Widget destination = const RoleSelectionScreen();

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final role = await AuthService.userRole(user.uid);
        if (role == 'driver') {
          destination = const DriverHomeScreen();
        } else if (role == 'passenger') {
          destination = const PassengerHomeScreen();
        } else {
          // Auth account exists but no user doc — a signup that died halfway.
          await FirebaseAuth.instance.signOut();
        }
      } catch (_) {
        // Offline or Firestore unreachable. Fall through to role selection
        // rather than hanging on the splash forever.
      }
    }

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => destination,
        transitionDuration: const Duration(milliseconds: 350),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  void dispose() {
    _fadeUpController.dispose();
    _trikeController.dispose();
    _wheelController.dispose();
    _tagController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: Stack(
        children: [
          // Decorative background orbs
          Positioned(
            top: -200,
            left: -140,
            child: Container(
              width: 480,
              height: 480,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
          ),
          Positioned(
            bottom: -90,
            right: -70,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withValues(alpha: 0.12),
              ),
            ),
          ),
          // Main content
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Tricycle emoji
                SlideTransition(
                  position: _trikeSlide,
                  child: FadeTransition(
                    opacity: _trikeOpacity,
                    child: const Text(
                      '🛺',
                      style: TextStyle(fontSize: 64),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                // PolaMove logo row
                SlideTransition(
                  position: _fadeUpSlide,
                  child: FadeTransition(
                    opacity: _fadeUpOpacity,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _buildLogoText('P'),
                        _buildLogoText('o'),
                        _buildLogoText('l'),
                        _buildLogoText('a'),
                        _buildLogoText('M'),
                        // Wheel SVG replacing 'o'
                        AnimatedBuilder(
                          animation: _wheelSpin,
                          builder: (context, child) {
                            return Transform.rotate(
                              angle: _wheelSpin.value * 2 * 3.14159,
                              child: child,
                            );
                          },
                          child: SizedBox(
                            width: 28,
                            height: 28,
                            child: CustomPaint(
                              painter: _WheelPainter(),
                            ),
                          ),
                        ),
                        _buildLogoText('v'),
                        _buildLogoText('e'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Tagline
                SlideTransition(
                  position: _tagSlide,
                  child: FadeTransition(
                    opacity: _tagOpacity,
                    child: const Text(
                      'P O L A N G U I   ·   A L B A Y',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: Colors.white60,
                        letterSpacing: 4,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogoText(String letter) {
    return Text(
      letter,
      style: const TextStyle(
        fontFamily: 'Syne',
        fontSize: 42,
        fontWeight: FontWeight.w800,
        color: Colors.white,
        height: 1,
        letterSpacing: -1,
      ),
    );
  }
}

class _WheelPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final fillPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 1.5;
    final spokeInner = size.width * 0.125;
    final spokeOuter = radius;

    // Outer circle
    canvas.drawCircle(center, radius, paint);

    // Center hub
    canvas.drawCircle(center, size.width * 0.125, fillPaint);

    // Spokes (8 directions)
    final spokePaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;

    final angles = [0.0, 0.785, 1.571, 2.356]; // 0, 45, 90, 135 degrees
    for (final angle in angles) {
      final cos = angle == 0
          ? 1.0
          : angle == 0.785
              ? 0.707
              : angle == 1.571
                  ? 0.0
                  : -0.707;
      final sin = angle == 0
          ? 0.0
          : angle == 0.785
              ? 0.707
              : angle == 1.571
                  ? 1.0
                  : 0.707;

      canvas.drawLine(
        Offset(center.dx + cos * spokeInner, center.dy + sin * spokeInner),
        Offset(center.dx + cos * spokeOuter, center.dy + sin * spokeOuter),
        spokePaint,
      );
      canvas.drawLine(
        Offset(center.dx - cos * spokeInner, center.dy - sin * spokeInner),
        Offset(center.dx - cos * spokeOuter, center.dy - sin * spokeOuter),
        spokePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}