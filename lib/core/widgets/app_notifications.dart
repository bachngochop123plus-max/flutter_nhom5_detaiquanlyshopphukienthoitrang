import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';

/// A centralized utility for showing luxury-themed dialogs and snackbars.
/// Designed with a sharp, minimalist aesthetic (small border radius)
/// and haptic feedback.
class AppNotifications {
  static const double _luxuryRadius = 2.0;

  // ---------------------------------------------------------------------------
  // SNACKBARS
  // ---------------------------------------------------------------------------

  static void showSuccessSnackBar(BuildContext context, String message) {
    HapticFeedback.lightImpact();
    _showSnackBar(
      context: context,
      message: message,
      icon: Icons.check_circle_outline,
      iconColor: AppColors.luxuryGold,
      borderColor: AppColors.luxuryGold.withValues(alpha: 0.5),
    );
  }

  static void showErrorSnackBar(BuildContext context, String message) {
    HapticFeedback.mediumImpact();
    _showSnackBar(
      context: context,
      message: message,
      icon: Icons.error_outline,
      iconColor: Colors.redAccent,
      borderColor: Colors.redAccent.withValues(alpha: 0.5),
    );
  }

  static void showInfoSnackBar(BuildContext context, String message) {
    HapticFeedback.lightImpact();
    _showSnackBar(
      context: context,
      message: message,
      icon: Icons.info_outline,
      iconColor: Colors.white,
      borderColor: Colors.white.withValues(alpha: 0.2),
    );
  }

  static void _showSnackBar({
    required BuildContext context,
    required String message,
    required IconData icon,
    required Color iconColor,
    required Color borderColor,
  }) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: iconColor, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 2.0),
                child: Text(
                  message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ),
          ],
        ),
        backgroundColor: AppColors.deepBlack,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_luxuryRadius),
          side: BorderSide(color: borderColor, width: 1.0),
        ),
        elevation: 10,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        duration: const Duration(seconds: 3),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // DIALOGS
  // ---------------------------------------------------------------------------

  /// Shows a minimalist, luxury confirmation dialog.
  static Future<void> showConfirmationDialog(
    BuildContext context, {
    required String title,
    String? content,
    Widget? customContent,
    String confirmText = 'Xác nhận',
    String cancelText = 'Huỷ',
    required VoidCallback onConfirm,
    VoidCallback? onCancel,
    bool isDanger = false,
  }) async {
    HapticFeedback.lightImpact();
    
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? AppColors.deepBlack : Colors.white;
    final textColor = isDark ? Colors.white : AppColors.deepBlack;
    final confirmColor = isDanger ? Colors.red[700] : AppColors.luxuryGold;
    final confirmTextColor = Colors.white;

    return showDialog(
      context: context,
      barrierDismissible: onCancel != null,
      builder: (context) {
        return PopScope(
          canPop: onCancel == null,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop && onCancel != null) {
              Navigator.pop(context);
              onCancel();
            }
          },
          child: Dialog(
            backgroundColor: bgColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(_luxuryRadius),
              side: BorderSide(
                color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.1),
              ),
            ),
            elevation: 24,
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title.toUpperCase(),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: textColor,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (customContent != null)
                    customContent
                  else if (content != null)
                    Text(
                      content,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        color: textColor.withValues(alpha: 0.8),
                      ),
                    ),
                  const SizedBox(height: 32),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          if (onCancel != null) onCancel();
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: textColor,
                          side: BorderSide(color: textColor.withValues(alpha: 0.3)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(_luxuryRadius),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        ),
                        child: Text(cancelText),
                      ),
                      const SizedBox(width: 12),
                      FilledButton(
                        onPressed: () {
                          Navigator.pop(context);
                          onConfirm();
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: confirmColor,
                          foregroundColor: confirmTextColor,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(_luxuryRadius),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        ),
                        child: Text(confirmText, style: const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Shows a simple info dialog.
  static Future<void> showInfoDialog(
    BuildContext context, {
    required String title,
    String? content,
    Widget? customContent,
    String closeText = 'Đóng',
  }) async {
    HapticFeedback.lightImpact();
    
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? AppColors.deepBlack : Colors.white;
    final textColor = isDark ? Colors.white : AppColors.deepBlack;

    return showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: bgColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_luxuryRadius),
            side: BorderSide(
              color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.1),
            ),
          ),
          elevation: 24,
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title.toUpperCase(),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: textColor,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 16),
                if (customContent != null)
                  customContent
                else if (content != null)
                  Text(
                    content,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.5,
                      color: textColor.withValues(alpha: 0.8),
                    ),
                  ),
                const SizedBox(height: 32),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.luxuryGold,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(_luxuryRadius),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                    child: Text(closeText, style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
