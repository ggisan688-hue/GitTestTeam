import 'package:flutter/material.dart';

/// Show a transient scrollbar for lists and scrollable forms on every device.
/// Each decoration uses the controller supplied by its own Scrollable, so nested
/// lists and independent dialog viewports do not share a new controller.
class RidiScrollBehavior extends MaterialScrollBehavior {
  const RidiScrollBehavior();

  @override
  Widget buildScrollbar(
      BuildContext context,
      Widget child,
      ScrollableDetails details,
      ) {
    final controller = details.controller;
    if (controller == null || details.physics?.allowUserScrolling == false) {
      return child;
    }

    // Existing screen-specific scrollbars keep their own padding and styling.
    // Match controllers rather than skipping all nested scrollable children.
    var alreadyDecorated = false;
    context.visitAncestorElements((element) {
      final widget = element.widget;
      if ((widget is Scrollbar && identical(widget.controller, controller)) ||
          (widget is RawScrollbar && identical(widget.controller, controller))) {
        alreadyDecorated = true;
        return false;
      }
      return true;
    });
    if (alreadyDecorated) return child;

    final axis = axisDirectionToAxis(details.direction);
    return Scrollbar(
      controller: controller,
      thumbVisibility: false,
      trackVisibility: false,
      // Indicators must also work when a route has several primary lists.
      // Scrolling remains handled by the list itself.
      interactive: false,
      thickness: 4,
      radius: const Radius.circular(4),
      scrollbarOrientation: axis == Axis.vertical
          ? ScrollbarOrientation.right : ScrollbarOrientation.bottom,
      notificationPredicate: (notification) =>
      notification.depth == 0 && notification.metrics.axis == axis,
      child: child,
    );
  }
}
