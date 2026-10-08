import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// 电视遥控器焦点高亮层。
///
/// 包在整个 App 外面，用遥控器 / 键盘方向键移动焦点时，在当前焦点控件外圈画一个醒目的描边框；
/// 触摸或鼠标操作时（highlightMode 为 touch）自动隐藏，不影响手机和桌面端。
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

  @override
  void initState() {
    super.initState();
    // 焦点控件可能随滚动、动画移动，所以键盘模式下逐帧跟踪它的位置
    _ticker = createTicker((_) => _syncRect());
    FocusManager.instance.addListener(_onFocusChanged);
    FocusManager.instance.addHighlightModeListener(_onHighlightModeChanged);
    _onHighlightModeChanged(FocusManager.instance.highlightMode);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_onFocusChanged);
    FocusManager.instance.removeHighlightModeListener(_onHighlightModeChanged);
    _ticker.dispose();
    super.dispose();
  }

  void _onHighlightModeChanged(FocusHighlightMode mode) {
    if (mode == FocusHighlightMode.traditional) {
      if (!_ticker.isActive) _ticker.start();
    } else {
      if (_ticker.isActive) _ticker.stop();
      if (_rect != null && mounted) setState(() => _rect = null);
    }
  }

  void _onFocusChanged() => _syncRect();

  void _syncRect() {
    if (!mounted) return;
    Rect? next;
    final node = FocusManager.instance.primaryFocus;
    if (FocusManager.instance.highlightMode == FocusHighlightMode.traditional &&
        node != null &&
        node.context != null &&
        node.context!.mounted) {
      final renderObject = node.context!.findRenderObject();
      if (renderObject is RenderBox &&
          renderObject.attached &&
          renderObject.hasSize) {
        final rect = node.rect;
        final screen = MediaQuery.sizeOf(context);
        // 整页大小的焦点（比如播放器的快捷键区域、页面级 FocusScope）不画框
        final tooBig = rect.width * rect.height >
            screen.width * screen.height * 0.6;
        if (!tooBig && !rect.isEmpty && rect.isFinite) {
          next = rect;
        }
      }
    }
    if (next != _rect) setState(() => _rect = next);
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    final rect = _rect;
    return Stack(
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
    );
  }
}
