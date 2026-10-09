import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// 电视遥控器焦点高亮层。
///
/// 包在整个 App 外面，用遥控器 / 键盘方向键移动焦点时，在当前焦点控件外圈画一个醒目的描边框；
/// 触摸操作时自动隐藏，不影响手机端。
///
/// 注意：不依赖 [FocusManager.highlightMode]，因为在 Android TV 上 D-pad 事件不会让
/// Flutter 把 highlightMode 从 touch 切到 traditional（实测高亮层永远不会激活）。
/// 这里直接监听键盘 / D-pad 按键，并默认按 TV 模式启动。
class TvFocusOverlay extends StatefulWidget {
  const TvFocusOverlay({super.key, required this.child});

  final Widget child;

  @override
  State<TvFocusOverlay> createState() => _TvFocusOverlayState();
}

class _TvFocusOverlayState extends State<TvFocusOverlay>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Rect? _rect;

  /// 是否处于"键盘 / 遥控器导航"模式。TV 默认 true，触摸屏幕后转 false。
  bool _kbMode = true;

  @override
  void initState() {
    super.initState();
    // 焦点控件可能随滚动、动画移动，所以逐帧跟踪它的位置
    _ticker = createTicker((_) => _syncRect());
    _ticker.start();
    FocusManager.instance.addListener(_onFocusChanged);
    HardwareKeyboard.instance.addHandler(_onKeyEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKeyEvent);
    FocusManager.instance.removeListener(_onFocusChanged);
    _ticker.dispose();
    super.dispose();
  }

  bool _onKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final key = event.logicalKey;
    final isNavKey = key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.tab ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.gameButtonA ||
        key == LogicalKeyboardKey.gameButtonB ||
        key == LogicalKeyboardKey.mediaPlay ||
        key == LogicalKeyboardKey.mediaPause ||
        key == LogicalKeyboardKey.mediaPlayPause ||
        key == LogicalKeyboardKey.mediaStop ||
        key == LogicalKeyboardKey.mediaTrackNext ||
        key == LogicalKeyboardKey.mediaTrackPrevious;
    if (isNavKey && !_kbMode && mounted) {
      setState(() => _kbMode = true);
    }
    return false;
  }

  void _onFocusChanged() => _syncRect();

  void _syncRect() {
    if (!mounted || !_kbMode) return;
    Rect? next;
    final node = FocusManager.instance.primaryFocus;
    if (node != null && node.context != null && node.context!.mounted) {
      final renderObject = node.context!.findRenderObject();
      if (renderObject is RenderBox &&
          renderObject.attached &&
          renderObject.hasSize) {
        final rect = node.rect;
        final screen = MediaQuery.sizeOf(context);
        // 整页大小的焦点（比如播放器的快捷键区域、页面级 FocusScope）不画框
        final tooBig =
            rect.width * rect.height > screen.width * screen.height * 0.6;
        if (!tooBig && !rect.isEmpty && rect.isFinite) {
          next = rect;
        }
      }
    }
    if (next != _rect) {
      setState(() => _rect = next);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    final rect = _rect;
    return Listener(
      // 触摸屏幕时切回 touch 模式，隐藏焦点框
      onPointerDown: (event) {
        if (event.kind != PointerDeviceKind.touch) return;
        if (_kbMode || _rect != null) {
          setState(() {
            _kbMode = false;
            _rect = null;
          });
        }
      },
      child: Stack(
        textDirection: TextDirection.ltr,
        children: [
          widget.child,
          if (rect != null)
            Positioned.fromRect(
              rect: rect.inflate(3),
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: color, width: 3),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.45),
                        blurRadius: 14,
                        spreadRadius: 1,
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
