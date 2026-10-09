import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:kazumi/utils/constants.dart';

class ThemeProvider extends ChangeNotifier {
  ThemeMode themeMode = ThemeMode.system;
  bool useDynamicColor = false;
  late ThemeData light;
  late ThemeData dark;
  String? currentFontFamily = customAppFontFamily;

  /// 主界面背景图的本地路径，空串表示不使用
  String backgroundImagePath = '';
  double backgroundImageOpacity = 0.3;

  /// Returns true if the effective theme is dark mode.
  /// Automatically gets platform brightness when themeMode is ThemeMode.system.
  bool isEffectiveDark() {
    if (themeMode == ThemeMode.dark) return true;
    if (themeMode == ThemeMode.light) return false;
    final platformBrightness =
        SchedulerBinding.instance.platformDispatcher.platformBrightness;
    return platformBrightness == Brightness.dark;
  }

  void setTheme(ThemeData light, ThemeData dark, {bool notify = true}) {
    this.light = light;
    this.dark = dark;
    if (notify) notifyListeners();
  }

  void setThemeMode(ThemeMode mode, {bool notify = true}) {
    themeMode = mode;
    if (notify) notifyListeners();
  }

  void setDynamic(bool useDynamicColor, {bool notify = true}) {
    this.useDynamicColor = useDynamicColor;
    if (notify) notifyListeners();
  }

  void setFontFamily(bool useSystemFont, {bool notify = true}) {
    currentFontFamily = useSystemFont ? null : customAppFontFamily;
    if (notify) notifyListeners();
  }

  void setBackgroundImage(String path, {bool notify = true}) {
    backgroundImagePath = path;
    if (notify) notifyListeners();
  }

  void setBackgroundImageOpacity(double opacity, {bool notify = true}) {
    backgroundImageOpacity = opacity.clamp(0.0, 1.0);
    if (notify) notifyListeners();
  }
}
