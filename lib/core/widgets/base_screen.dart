import 'package:flutter/material.dart';

import 'keyboard_dismiss_on_tap.dart';
import 'loading_overlay.dart';

class BaseScreen extends StatelessWidget {
  const BaseScreen({
    super.key,
    required this.body,
    this.title,
    this.actions,
    this.leading,
    this.automaticallyImplyLeading = true,
    this.drawer,
    this.floatingActionButton,
    this.isLoading = false,
    this.bottomNavigationBar,
    this.extendBodyBehindAppBar = false,
  });

  final Widget body;
  final String? title;
  final List<Widget>? actions;
  final Widget? leading;
  final bool automaticallyImplyLeading;
  final Widget? drawer;
  final Widget? floatingActionButton;
  final bool isLoading;
  final Widget? bottomNavigationBar;
  final bool extendBodyBehindAppBar;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: extendBodyBehindAppBar,
      appBar: title == null
          ? null
          : AppBar(
              title: Text(title!),
              leading: leading,
              automaticallyImplyLeading: automaticallyImplyLeading,
              actions: actions,
            ),
      drawer: drawer,
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: bottomNavigationBar,
      body: SafeArea(
        child: KeyboardDismissOnTap(
          child: LoadingOverlay(isLoading: isLoading, child: body),
        ),
      ),
    );
  }
}
