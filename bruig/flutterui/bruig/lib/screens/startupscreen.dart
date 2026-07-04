import 'package:bruig/components/buttons.dart';
import 'package:bruig/components/empty_widget.dart';
import 'package:bruig/models/uistate.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:bruig/theme_manager.dart';

class StartupScreen extends StatelessWidget {
  final List<Widget> widgetList;
  final bool hideAboutButton;
  final Widget? fab;
  final double? childrenWidth;

  // When true, shows the full-bleed portal background behind the content.
  // Pass showPortal: false on any startup screen that should stay plain.
  final bool showPortal;

  const StartupScreen(this.widgetList,
      {this.hideAboutButton = false,
      this.fab,
      this.childrenWidth,
      this.showPortal = true,
      super.key});

  Widget _buildChildren() {
    return Column(
        mainAxisAlignment: MainAxisAlignment.center, children: widgetList);
  }

  @override
  Widget build(BuildContext context) {
    bool isScreenSmall = checkIsScreenSmall(context);
    return Scaffold(
        body: Consumer<ThemeNotifier>(
            builder: (context, theme, child) => Container(
                decoration: const BoxDecoration(color: Color(0xFF0E0E0E)),
                child: Stack(children: [
                  // Full-bleed portal background (static image -> painted once).
                  if (showPortal) ...[
                    Positioned.fill(
                        child: ClipRect(
                            child: Transform.scale(
                      scale: 1.0,
                      child: Image.asset(
                        "assets/images/login_bg.png",
                        fit: BoxFit.cover,
                        alignment: Alignment.center,
                        errorBuilder: (context, error, stack) =>
                            const SizedBox.shrink(),
                      ),
                    ))),
                    // Soft radial scrim: darkens the eye so the centered login
                    // stays legible over the glow, fading out to reveal the rings.
                    Positioned.fill(
                        child: DecoratedBox(
                            decoration: BoxDecoration(
                                gradient: RadialGradient(
                      center: Alignment.center,
                      radius: 0.55,
                      colors: [
                        Colors.black.withValues(alpha: 0.62),
                        Colors.black.withValues(alpha: 0.30),
                        Colors.black.withValues(alpha: 0.0),
                      ],
                      stops: const [0.0, 0.45, 0.8],
                    )))),
                  ],
                  Container(
                      alignment: showPortal
                          ? const Alignment(0.0, -0.06)
                          : Alignment.center,
                      padding: const EdgeInsets.all(30),
                      child: SingleChildScrollView(
                          child: childrenWidth != null
                              ? SizedBox(
                                  width: childrenWidth, child: _buildChildren())
                              : _buildChildren())),
                  !hideAboutButton
                      ? Positioned(
                          top: 5,
                          left: 5,
                          child: SizedBox(
                              height: isScreenSmall ? 70 : 100,
                              width: isScreenSmall ? 70 : 100,
                              child: const Center(child: AboutButton())))
                      : const Empty(),
                  if (fab != null)
                    Positioned(right: 10, bottom: 10, child: fab!),
                ]))));
  }
}
