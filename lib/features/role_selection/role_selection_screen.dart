import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../auth/auth_passenger_screen.dart';
import '../auth/auth_driver_screen.dart';

class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Radial gradient background
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(-0.7, -1.0),
                  radius: 1.0,
                  colors: [
                    Color(0x2EC41E3A),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          // Main body
          SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 28),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Tricycle emoji
                    const Text('🛺', style: TextStyle(fontSize: 40)),
                    const SizedBox(height: 12),
                    // Title
                    Text(
                      'Welcome to PolaMove',
                      style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                            fontSize: 25,
                          ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Your tricycle app in Polangui, Albay',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontSize: 13,
                          ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    // Passenger card
                    _RoleCard(
                      emoji: '🧍',
                      title: 'Passenger',
                      subtitle: 'Book a tricycle ride',
                      onTap: () {
                        Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => const AuthPassengerScreen(),
                        ));
                      },
                    ),
                    const SizedBox(height: 12),
                    // Driver card
                    _RoleCard(
                      emoji: '🛺',
                      title: 'Driver',
                      subtitle: 'Accept ride requests',
                      onTap: () {
                        Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => const AuthDriverScreen(),
                        ));
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoleCard extends StatefulWidget {
  final String emoji;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _RoleCard({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  State<_RoleCard> createState() => _RoleCardState();
}

class _RoleCardState extends State<_RoleCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _hovered = true),
      onTapUp: (_) {
        setState(() => _hovered = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        padding: const EdgeInsets.all(19),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: _hovered ? AppColors.primaryLight : const Color(0x1C14142A),
            width: 1.5,
          ),
          boxShadow: _hovered
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.14),
                    blurRadius: 36,
                    offset: const Offset(0, 10),
                  )
                ]
              : [],
        ),
        child: Row(
          children: [
            // Icon box
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: AppColors.primaryTint,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.22),
                  width: 1,
                ),
              ),
              child: Center(
                child: Text(widget.emoji, style: const TextStyle(fontSize: 23)),
              ),
            ),
            const SizedBox(width: 15),
            // Text
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontSize: 18,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.subtitle,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontSize: 12,
                        ),
                  ),
                ],
              ),
            ),
            // Arrow circle
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: _hovered ? AppColors.primary : AppColors.primaryTint,
                shape: BoxShape.circle,
                border: Border.all(
                  color: _hovered
                      ? AppColors.primary
                      : AppColors.primary.withValues(alpha: 0.22),
                  width: 1,
                ),
              ),
              child: Icon(
                Icons.chevron_right_rounded,
                color: _hovered ? Colors.white : AppColors.primaryLight,
                size: 18,
              ),
            ),
          ],
        ),
      ),
    );
  }
}