import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

class AppTextStyles {
  static TextTheme buildTextTheme(TextTheme base) {
    final headlineFont = GoogleFonts.playfairDisplayTextTheme(base).copyWith(
      headlineLarge: GoogleFonts.playfairDisplay(
        textStyle: base.headlineLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: AppColors.deepBlack,
        ),
      ),
      headlineMedium: GoogleFonts.playfairDisplay(
        textStyle: base.headlineMedium?.copyWith(
          fontWeight: FontWeight.w700,
          color: AppColors.deepBlack,
        ),
      ),
      headlineSmall: GoogleFonts.playfairDisplay(
        textStyle: base.headlineSmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: AppColors.deepBlack,
        ),
      ),
    );

    return headlineFont.copyWith(
      bodyLarge: GoogleFonts.inter(
        textStyle: base.bodyLarge?.copyWith(
          fontWeight: FontWeight.w500,
          color: AppColors.ink,
        ),
      ),
      bodyMedium: GoogleFonts.inter(
        textStyle: base.bodyMedium?.copyWith(
          fontWeight: FontWeight.w400,
          color: AppColors.ink,
        ),
      ),
      bodySmall: GoogleFonts.inter(
        textStyle: base.bodySmall?.copyWith(
          fontWeight: FontWeight.w400,
          color: AppColors.softGray,
        ),
      ),
      labelLarge: GoogleFonts.inter(
        textStyle: base.labelLarge?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}
