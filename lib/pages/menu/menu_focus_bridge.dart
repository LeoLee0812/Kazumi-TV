import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 让方向键 / 遥控器 D-pad 能在导航栏和页面内容之间来回移动焦点。
///
/// 页面内容放在嵌套 Navigator 里，每个路由都有自己的 FocusScope，而 Flutter 的
/// 方向键焦点遍历不会越过当前 FocusScope，所以焦点一旦进了内容区就再也回不到导航栏。
/// 这里在内容区走到边缘时把焦点手动交给导航栏，反方向同理。
class MenuFocusBridge {
  final FocusNode menuNode = FocusNode(
    debugLabel: 'MenuFocusBridge.menu',
    canRequestFocus: false,
    skipTraversal: true,
  );
  final FocusNode contentNode = FocusNode(
    debugLabel: 'MenuFocusBridge.content',
    canRequestFocus: false,
    skipTraversal: true,
  );

  /// 离开内容区时的焦点，回来时优先还原到它
  FocusNode? _lastContentFocus;

  void dispose() {
    menuNode.dispose();
    contentNode.dispose();
  }

  static TraversalDirection? _directionOf(KeyEvent event) {
    if (event is KeyUpEvent) return null;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft) return TraversalDirection.left;
    if (key == LogicalKeyboardKey.arrowRight) return TraversalDirection.right;
    if (key == LogicalKeyboardKey.arrowUp) return TraversalDirection.up;
    if (key == LogicalKeyboardKey.arrowDown) return TraversalDirection.down;
    return null;
  }

  static bool _isUsable(FocusNode node) {
    if (node is FocusScopeNode || node.context == null) return false;
    final rect = node.rect;
    return node.canRequestFocus && rect.isFinite && !rect.isEmpty;
  }

  /// 内容区的按键处理：[toMenu] 方向上已经没有可去的控件时，把焦点交给导航栏里
  /// 第 [selectedIndex] 个目的地。
  KeyEventResult handleContentKey(
    KeyEvent event, {
    required TraversalDirection toMenu,
    required int selectedIndex,
    required int destinationCount,
  }) {
    if (_directionOf(event) != toMenu) return KeyEventResult.ignored;
    final focus = FocusManager.instance.primaryFocus;
    final focusContext = focus?.context;
    if (focus == null || focusContext == null) return KeyEventResult.ignored;
    // 输入框里的方向键要留给光标
    if (focusContext.widget is EditableText ||
        focusContext.findAncestorWidgetOfExactType<EditableText>() != null) {
      return KeyEventResult.ignored;
    }
    if (focus.focusInDirection(toMenu)) return KeyEventResult.handled;

    final horizontal =
        toMenu == TraversalDirection.left || toMenu == TraversalDirection.right;
    final targets = menuNode.traversalDescendants.where(_isUsable).toList()
      ..sort(
        (a, b) => horizontal
            ? a.rect.top.compareTo(b.rect.top)
            : a.rect.left.compareTo(b.rect.left),
      );
    if (targets.isEmpty) return KeyEventResult.ignored;
    // 目的地排在最后（侧边栏顶部还有一个搜索按钮）
    final index = (targets.length - destinationCount + selectedIndex).clamp(
      0,
      targets.length - 1,
    );
    _lastContentFocus = focus;
    targets[index].requestFocus();
    return KeyEventResult.handled;
  }

  /// 导航栏的按键处理：按 [toContent] 方向时把焦点送回内容区。
  KeyEventResult handleMenuKey(
    KeyEvent event, {
    required TraversalDirection toContent,
  }) {
    if (_directionOf(event) != toContent) return KeyEventResult.ignored;
    final focus = FocusManager.instance.primaryFocus;
    if (focus == null) return KeyEventResult.ignored;

    final last = _lastContentFocus;
    _lastContentFocus = null;
    if (last != null &&
        _isUsable(last) &&
        last.ancestors.contains(contentNode)) {
      last.requestFocus();
      return KeyEventResult.handled;
    }

    final origin = focus.rect.center;
    FocusNode? nearest;
    var nearestDistance = double.infinity;
    for (final node in contentNode.traversalDescendants) {
      if (!_isUsable(node)) continue;
      final distance = (node.rect.center - origin).distanceSquared;
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearest = node;
      }
    }
    if (nearest == null) return KeyEventResult.ignored;
    nearest.requestFocus();
    return KeyEventResult.handled;
  }
}
