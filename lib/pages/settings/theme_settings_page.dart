import 'dart:io';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:kazumi/request/core/dio_factory.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/bean/card/palette_card.dart';
import 'package:kazumi/utils/constants.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/settings/theme_provider.dart';
import 'package:kazumi/bean/settings/color_type.dart';
import 'package:kazumi/bean/settings/settings_detail_scaffold.dart';
import 'package:kazumi/bean/settings/settings_dropdown_tile.dart';
import 'package:kazumi/bean/settings/settings_list.dart';
import 'package:window_manager/window_manager.dart';
import 'package:kazumi/utils/device.dart';
import 'package:kazumi/utils/theme.dart';

class ThemeSettingsPage extends StatefulWidget {
  const ThemeSettingsPage({super.key});

  @override
  State<ThemeSettingsPage> createState() => _ThemeSettingsPageState();
}

class _ThemeSettingsPageState extends State<ThemeSettingsPage> {
  late dynamic defaultThemeMode;
  late dynamic defaultThemeColor;
  late bool oledEnhance;
  late bool useDynamicColor;
  late bool showWindowButton;
  late bool useSystemFont;
  late String backgroundImagePath;
  late double backgroundImageOpacity;
  bool _savingBackgroundImage = false;
  late final ThemeProvider themeProvider;

  @override
  void initState() {
    super.initState();
    defaultThemeMode = GStorage.getSetting(SettingsKeys.themeMode);
    defaultThemeColor = GStorage.getSetting(SettingsKeys.themeColor);
    oledEnhance = GStorage.getSetting(SettingsKeys.oledEnhance);
    useDynamicColor = GStorage.getSetting(SettingsKeys.useDynamicColor);
    showWindowButton = GStorage.getSetting(SettingsKeys.showWindowButton);
    useSystemFont = GStorage.getSetting(SettingsKeys.useSystemFont);
    themeProvider = context.read<ThemeProvider>();
    backgroundImagePath = themeProvider.backgroundImagePath;
    backgroundImageOpacity = themeProvider.backgroundImageOpacity;
  }

  static const _backgroundImageExtensions = [
    'jpg',
    'jpeg',
    'png',
    'webp',
    'gif',
    'bmp',
  ];

  /// 把图片存进应用数据目录再启用，避免原文件被移动或删除后背景丢失。
  Future<void> _saveBackgroundImage(List<int> bytes, String extension) async {
    final supportDir = await getApplicationSupportDirectory();
    final dir = Directory(path.join(supportDir.path, 'background'));
    await dir.create(recursive: true);
    // 文件名带时间戳，换图后不会命中旧图的图片缓存
    final file = File(path.join(
      dir.path,
      'background_${DateTime.now().millisecondsSinceEpoch}.$extension',
    ));
    await file.writeAsBytes(bytes, flush: true);
    final oldPath = backgroundImagePath;
    await GStorage.putSetting(SettingsKeys.backgroundImagePath, file.path);
    themeProvider.setBackgroundImage(file.path);
    if (mounted) setState(() => backgroundImagePath = file.path);
    await _deleteBackgroundFile(oldPath);
  }

  Future<void> _deleteBackgroundFile(String filePath) async {
    if (filePath.isEmpty) return;
    try {
      final file = File(filePath);
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // 旧图删不掉不影响使用
    }
  }

  static String _imageExtensionOf(String name) {
    final extension = path.extension(name).replaceFirst('.', '').toLowerCase();
    return _backgroundImageExtensions.contains(extension) ? extension : 'jpg';
  }

  Future<void> _runBackgroundImageTask(Future<void> Function() task) async {
    if (_savingBackgroundImage) return;
    setState(() => _savingBackgroundImage = true);
    try {
      await task();
    } catch (error, stackTrace) {
      KazumiLogger().e('Theme: failed to set background image',
          error: error, stackTrace: stackTrace);
      KazumiDialog.showToast(message: '设置背景图失败：$error');
    } finally {
      if (mounted) setState(() => _savingBackgroundImage = false);
    }
  }

  Future<void> _pickBackgroundImage() => _runBackgroundImageTask(() async {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: _backgroundImageExtensions,
          withData: true,
        );
        if (result == null) return;
        final picked = result.files.single;
        final bytes = picked.bytes ??
            (picked.path == null
                ? null
                : await File(picked.path!).readAsBytes());
        if (bytes == null) throw const FileSystemException('无法读取所选图片');
        await _saveBackgroundImage(bytes, _imageExtensionOf(picked.name));
      });

  Future<void> _downloadBackgroundImage() async {
    final url = await KazumiDialog.show<String>(builder: (context) {
      var input = '';
      return AlertDialog(
        title: const Text('图片链接'),
        content: SizedBox(
          width: 480,
          child: TextField(
            autofocus: true,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(hintText: 'https://'),
            onChanged: (value) => input = value,
            onSubmitted: (value) =>
                KazumiDialog.dismiss(popWith: value.trim()),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => KazumiDialog.dismiss(),
            child: Text(
              '取消',
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
          ),
          TextButton(
            onPressed: () => KazumiDialog.dismiss(popWith: input.trim()),
            child: const Text('确定'),
          ),
        ],
      );
    });
    if (url == null || url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || !uri.scheme.startsWith('http')) {
      KazumiDialog.showToast(message: '请输入 http 或 https 开头的图片链接');
      return;
    }
    await _runBackgroundImageTask(() async {
      final response = await DioFactory.downloadDio.getUri<List<int>>(
        uri,
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = response.data;
      if (bytes == null || bytes.isEmpty) {
        throw const FileSystemException('图片内容为空');
      }
      await _saveBackgroundImage(bytes, _imageExtensionOf(uri.path));
    });
  }

  Future<void> _clearBackgroundImage() async {
    final oldPath = backgroundImagePath;
    await GStorage.putSetting(SettingsKeys.backgroundImagePath, '');
    themeProvider.setBackgroundImage('');
    setState(() => backgroundImagePath = '');
    await _deleteBackgroundFile(oldPath);
  }

  void _updateBackgroundImageOpacity(double value) {
    themeProvider.setBackgroundImageOpacity(value);
    setState(() => backgroundImageOpacity = value);
    GStorage.putSetting(SettingsKeys.backgroundImageOpacity, value);
  }

  void setTheme(Color? color) {
    var defaultDarkTheme = ThemeData(
        useMaterial3: true,
        fontFamily: themeProvider.currentFontFamily,
        brightness: Brightness.dark,
        colorSchemeSeed: color,
        progressIndicatorTheme: progressIndicatorTheme2024,
        sliderTheme: sliderTheme2024,
        pageTransitionsTheme: pageTransitionsTheme2024);
    var oledTheme = oledDarkTheme(defaultDarkTheme);
    themeProvider.setTheme(
      ThemeData(
          useMaterial3: true,
          fontFamily: themeProvider.currentFontFamily,
          brightness: Brightness.light,
          colorSchemeSeed: color,
          progressIndicatorTheme: progressIndicatorTheme2024,
          sliderTheme: sliderTheme2024,
          pageTransitionsTheme: pageTransitionsTheme2024),
      oledEnhance ? oledTheme : defaultDarkTheme,
    );
    defaultThemeColor = color?.toARGB32().toRadixString(16) ?? 'default';
    GStorage.putSetting(SettingsKeys.themeColor, defaultThemeColor);
  }

  void resetTheme() {
    var defaultDarkTheme = ThemeData(
        useMaterial3: true,
        fontFamily: themeProvider.currentFontFamily,
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.green,
        progressIndicatorTheme: progressIndicatorTheme2024,
        sliderTheme: sliderTheme2024,
        pageTransitionsTheme: pageTransitionsTheme2024);
    var oledTheme = oledDarkTheme(defaultDarkTheme);
    themeProvider.setTheme(
      ThemeData(
          useMaterial3: true,
          fontFamily: themeProvider.currentFontFamily,
          brightness: Brightness.light,
          colorSchemeSeed: Colors.green,
          progressIndicatorTheme: progressIndicatorTheme2024,
          sliderTheme: sliderTheme2024,
          pageTransitionsTheme: pageTransitionsTheme2024),
      oledEnhance ? oledTheme : defaultDarkTheme,
    );
    defaultThemeColor = 'default';
    GStorage.putSetting(SettingsKeys.themeColor, 'default');
  }

  void updateTheme(String theme) async {
    if (theme == 'dark') {
      themeProvider.setThemeMode(ThemeMode.dark);
    }
    if (theme == 'light') {
      themeProvider.setThemeMode(ThemeMode.light);
    }
    if (theme == 'system') {
      themeProvider.setThemeMode(ThemeMode.system);
    }
    await GStorage.putSetting(SettingsKeys.themeMode, theme);
    setState(() {
      defaultThemeMode = theme;
    });

    // Update Windows title bar theme
    if (Platform.isWindows) {
      await windowManager.setBrightness(
          themeProvider.isEffectiveDark() ? Brightness.dark : Brightness.light);
    }
  }

  void updateOledEnhance() {
    dynamic color;
    oledEnhance = GStorage.getSetting(SettingsKeys.oledEnhance);
    if (defaultThemeColor == 'default') {
      color = Colors.green;
    } else {
      color = Color(int.parse(defaultThemeColor, radix: 16));
    }
    setTheme(color);
  }

  @override
  Widget build(BuildContext context) {
    return SettingsDetailScaffold(
      title: const Text('外观设置'),
      body: SettingsList(
        sections: [
          SettingsSection(
            title: Text('外观'),
            tiles: [
              SettingsDropdownTile<String>(
                leading: Icons.dark_mode_rounded,
                title: const Text('深色模式'),
                value: defaultThemeMode,
                fallbackLabel: '跟随系统',
                options: const {'system': '跟随系统', 'light': '浅色', 'dark': '深色'},
                onChanged: updateTheme,
              ),
              SettingsTile(
                leading: Icons.palette_rounded,
                enabled: !useDynamicColor,
                onPressed: (_) async {
                  KazumiDialog.show(builder: (context) {
                    return AlertDialog(
                      title: Text('配色方案'),
                      content: StatefulBuilder(builder:
                          (BuildContext context, StateSetter setState) {
                        final List<Map<String, dynamic>> colorThemes =
                            colorThemeTypes;
                        return Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 8,
                          runSpacing: isDesktop() ? 8 : 0,
                          children: [
                            ...colorThemes.map(
                              (e) {
                                final index = colorThemes.indexOf(e);
                                return InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () {
                                    index == 0
                                        ? resetTheme()
                                        : setTheme(e['color']);
                                    KazumiDialog.dismiss();
                                  },
                                  child: Column(
                                    children: [
                                      PaletteCard(
                                        color: e['color'],
                                        selected: (e['color']
                                                    .value
                                                    .toRadixString(16) ==
                                                defaultThemeColor ||
                                            (defaultThemeColor == 'default' &&
                                                index == 0)),
                                      ),
                                      Text(e['label']),
                                    ],
                                  ),
                                );
                              },
                            )
                          ],
                        );
                      }),
                    );
                  });
                },
                title: Text('配色方案'),
              ),
              SettingsTile.switchTile(
                leading: Icons.colorize_rounded,
                enabled: !Platform.isIOS,
                onToggle: (value) async {
                  useDynamicColor = value ?? !useDynamicColor;
                  await GStorage.putSetting(
                      SettingsKeys.useDynamicColor, useDynamicColor);
                  themeProvider.setDynamic(useDynamicColor);
                  setState(() {});
                },
                title: Text('动态配色'),
                initialValue: useDynamicColor,
              ),
              SettingsTile.switchTile(
                leading: Icons.font_download_rounded,
                onToggle: (value) async {
                  useSystemFont = value ?? !useSystemFont;
                  await GStorage.putSetting(
                      SettingsKeys.useSystemFont, useSystemFont);
                  themeProvider.setFontFamily(useSystemFont);
                  dynamic color;
                  if (defaultThemeColor == 'default') {
                    color = Colors.green;
                  } else {
                    color = Color(int.parse(defaultThemeColor, radix: 16));
                  }
                  setTheme(color);
                  setState(() {});
                },
                title: Text('使用系统字体'),
                description: Text('关闭后使用 MI Sans 字体'),
                initialValue: useSystemFont,
              ),
            ],
            bottomInfo: Text('动态配色仅支持安卓12及以上和桌面平台'),
          ),
          SettingsSection(
            title: const Text('背景图'),
            tiles: [
              SettingsTile(
                leading: Icons.image_rounded,
                enabled: !_savingBackgroundImage,
                onPressed: (_) => _pickBackgroundImage(),
                title: const Text('选择本地图片'),
                value: Text(backgroundImagePath.isEmpty ? '未设置' : '已设置'),
              ),
              SettingsTile(
                leading: Icons.link_rounded,
                enabled: !_savingBackgroundImage,
                onPressed: (_) => _downloadBackgroundImage(),
                title: const Text('从图片链接下载'),
              ),
              if (backgroundImagePath.isNotEmpty) ...[
                SettingsSliderTile(
                  leading: Icons.opacity_rounded,
                  title: const Text('背景图不透明度'),
                  value: backgroundImageOpacity,
                  valueLabel: '${(backgroundImageOpacity * 100).round()}%',
                  min: 0.05,
                  max: 1,
                  divisions: 19,
                  onChanged: _updateBackgroundImageOpacity,
                ),
                SettingsTile(
                  leading: Icons.hide_image_rounded,
                  onPressed: (_) => _clearBackgroundImage(),
                  title: const Text('移除背景图'),
                ),
              ],
            ],
            bottomInfo: const Text('背景图显示在推荐、时间表、追番和我的这几个主界面'),
          ),
          SettingsSection(
            title: Text('显示'),
            tiles: [
              SettingsTile.switchTile(
                leading: Icons.contrast_rounded,
                onToggle: (value) async {
                  oledEnhance = value ?? !oledEnhance;
                  await GStorage.putSetting(
                      SettingsKeys.oledEnhance, oledEnhance);
                  updateOledEnhance();
                  setState(() {});
                },
                title: Text('OLED优化'),
                description: Text('深色模式下使用纯黑背景'),
                initialValue: oledEnhance,
              ),
            ],
          ),
          if (isDesktop())
            SettingsSection(
              title: Text('窗口'),
              tiles: [
                SettingsTile.switchTile(
                  leading: Icons.web_asset_rounded,
                  onToggle: (value) async {
                    showWindowButton = value ?? !showWindowButton;
                    await GStorage.putSetting(
                        SettingsKeys.showWindowButton, showWindowButton);
                    setState(() {});
                  },
                  title: Text('使用系统标题栏'),
                  description: Text('重启应用生效'),
                  initialValue: showWindowButton,
                ),
              ],
            ),
          if (Platform.isAndroid)
            SettingsSection(
              title: Text('屏幕'),
              tiles: [
                SettingsTile(
                  leading: Icons.sixty_fps_rounded,
                  onPressed: (_) async {
                    context.pushNamed('/settings/theme/display');
                  },
                  title: Text('屏幕帧率'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
