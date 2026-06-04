import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class MainShell extends StatelessWidget {
  const MainShell({super.key, required this.child});

  final Widget child;

  int _destinationIndex(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    if (location.startsWith('/cart')) {
      return 0;
    }
    if (location.startsWith('/favorites')) {
      return 1;
    }
    if (location.startsWith('/stores')) {
      return 3;
    }
    if (location.startsWith('/profile')) {
      return 4;
    }
    return 2; // Home is default (index 2)
  }

  @override
  Widget build(BuildContext context) {
    final selectedIndex = _destinationIndex(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: child,
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          height: 68,
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF111111) : Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: const Color(0xFFC6A15B).withValues(alpha: isDark ? 0.35 : 0.25),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.08),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildNavItem(
                      context,
                      icon: Icons.shopping_bag_outlined,
                      activeIcon: Icons.shopping_bag,
                      isSelected: selectedIndex == 0,
                      onTap: () => context.go('/cart'),
                      label: 'Giỏ hàng',
                    ),
                    _buildNavItem(
                      context,
                      icon: Icons.favorite_outline,
                      activeIcon: Icons.favorite,
                      isSelected: selectedIndex == 1,
                      onTap: () => context.go('/favorites'),
                      label: 'Yêu thích',
                    ),
                    const SizedBox(width: 56), // spacer for middle button
                    _buildNavItem(
                      context,
                      icon: Icons.place_outlined,
                      activeIcon: Icons.place,
                      isSelected: selectedIndex == 3,
                      onTap: () => context.go('/stores'),
                      label: 'Cửa hàng',
                    ),
                    _buildNavItem(
                      context,
                      icon: Icons.person_outline,
                      activeIcon: Icons.person,
                      isSelected: selectedIndex == 4,
                      onTap: () => context.go('/profile'),
                      label: 'Tài khoản',
                    ),
                  ],
                ),
              ),
              Positioned(
                top: -20,
                left: 0,
                right: 0,
                child: Center(
                  child: GestureDetector(
                    onTap: () => context.go('/home'),
                    child: AnimatedScale(
                      scale: selectedIndex == 2 ? 1.12 : 1.0,
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOutBack,
                      child: Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          gradient: selectedIndex == 2
                              ? const LinearGradient(
                                  colors: [
                                    Color(0xFFF1D38E),
                                    Color(0xFFC6A15B),
                                    Color(0xFF9E783B),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                )
                              : LinearGradient(
                                  colors: isDark
                                      ? [const Color(0xFF252525), const Color(0xFF111111)]
                                      : [const Color(0xFFE8E8E8), const Color(0xFFF5F5F5)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFFC6A15B).withValues(alpha: selectedIndex == 2 ? 0.8 : 0.4),
                            width: 2.0,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFC6A15B).withValues(alpha: selectedIndex == 2 ? 0.45 : 0.15),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Icon(
                          selectedIndex == 2 ? Icons.home_rounded : Icons.home_outlined,
                          color: selectedIndex == 2 ? const Color(0xFF111111) : const Color(0xFFC6A15B),
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(
    BuildContext context, {
    required IconData icon,
    required IconData activeIcon,
    required bool isSelected,
    required VoidCallback onTap,
    required String label,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          highlightColor: const Color(0xFFC6A15B).withValues(alpha: 0.08),
          splashColor: const Color(0xFFC6A15B).withValues(alpha: 0.08),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFFC6A15B).withValues(alpha: 0.15)
                      : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected
                        ? const Color(0xFFC6A15B).withValues(alpha: 0.45)
                        : Colors.transparent,
                    width: 1.2,
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: const Color(0xFFC6A15B).withValues(alpha: 0.1),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : [],
                ),
                child: Icon(
                  isSelected ? activeIcon : icon,
                  color: isSelected
                      ? const Color(0xFFC6A15B)
                      : (isDark ? Colors.grey[400]! : Colors.grey[600]!),
                  size: 20,
                ),
              ),
              const SizedBox(height: 3),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: isSelected ? 4 : 0,
                height: 4,
                decoration: const BoxDecoration(
                  color: Color(0xFFC6A15B),
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
