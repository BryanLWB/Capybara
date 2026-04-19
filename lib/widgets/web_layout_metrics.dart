import 'package:flutter/material.dart';

class WebLayoutMetrics {
  const WebLayoutMetrics._();

  static double horizontalPadding(double width) {
    if (width >= 1440) return 24;
    if (width >= 1120) return 20;
    if (width >= 980) return 16;
    if (width >= 860) return 18;
    if (width >= 640) return 16;
    return 12;
  }

  static double maxContentWidth(double width, {double base = 1520}) {
    if (width >= 1760) return 1600;
    return base;
  }

  static bool useWideNav(double width) => width >= 980;

  static bool useWidePanels(double width) => width >= 1024;

  static bool useMediumGrid(double width) => width >= 760;

  static bool useWideProfileRow(double width) => width >= 980;

  static bool mediumDesktop(double width) => width >= 900 && width < 1280;

  static bool compact(double width) => width < 960;

  static bool mobile(double width) => width < 640;

  static double sectionGap(double width) {
    if (width >= 1280) return 18;
    if (width >= 900) return 14;
    return 16;
  }

  static EdgeInsets heroPadding(double width) {
    if (width >= 1280) {
      return const EdgeInsets.fromLTRB(28, 28, 28, 24);
    }
    if (width >= 980) {
      return const EdgeInsets.fromLTRB(22, 22, 22, 18);
    }
    if (width >= 860) {
      return const EdgeInsets.fromLTRB(20, 20, 20, 18);
    }
    if (width >= 640) {
      return const EdgeInsets.fromLTRB(20, 20, 20, 18);
    }
    return const EdgeInsets.fromLTRB(18, 18, 18, 16);
  }

  static double heroTitleSize(double width) {
    if (width >= 1280) return 42;
    if (width >= 980) return 36;
    if (width >= 860) return 34;
    if (width >= 640) return 34;
    return 30;
  }

  static double heroSubtitleSize(double width) {
    if (width >= 1280) return 17;
    if (width >= 980) return 15;
    if (width >= 860) return 16;
    return 15;
  }

  static double heroRadius(double width) {
    if (width >= 1120) return 32;
    if (width >= 640) return 28;
    return 24;
  }

  static double cardPadding(double width) {
    if (width >= 1280) return 24;
    if (width >= 980) return 18;
    if (width >= 860) return 20;
    return 18;
  }

  static double dialogMaxHeight(BuildContext context,
      {double fraction = 0.88}) {
    return MediaQuery.of(context).size.height * fraction;
  }
}
