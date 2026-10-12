import 'package:flutter/widgets.dart';
import '../services/appearance_store.dart';

/// Holds account persistence throughout a gesture, including pauses in a drag.
/// The store still notifies the entire app for each local presentation preview.
class SettingsEditBoundary extends StatefulWidget {
  final AppearanceStore? store;
  final Widget child;
  final bool holdFocus;
  const SettingsEditBoundary({
    super.key,
    required this.store,
    required this.child,
    this.holdFocus = false,
  });
  @override
  State<SettingsEditBoundary> createState() => _SettingsEditBoundaryState();
}

class _SettingsEditBoundaryState extends State<SettingsEditBoundary> {
  final Set<int> pointers = {};
  bool focused = false;
  Object? edit;

  void updateHold() {
    if (pointers.isNotEmpty || focused) {
      edit ??= widget.store?.beginEdit();
    } else {
      widget.store?.endEdit(edit);
      edit = null;
    }
  }

  @override
  void didUpdateWidget(SettingsEditBoundary oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      oldWidget.store?.endEdit(edit);
      edit = null;
      updateHold();
    }
  }

  @override
  void dispose() {
    widget.store?.endEdit(edit);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget result = Listener(
      onPointerDown: (event) {
        pointers.add(event.pointer);
        updateHold();
      },
      onPointerUp: (event) {
        pointers.remove(event.pointer);
        updateHold();
      },
      onPointerCancel: (event) {
        pointers.remove(event.pointer);
        updateHold();
      },
      child: widget.child,
    );
    if (widget.holdFocus) {
      result = Focus(
        canRequestFocus: false,
        onFocusChange: (value) {
          focused = value;
          updateHold();
        },
        child: result,
      );
    }
    return result;
  }
}
