import 'dart:async';
import 'package:flutter/material.dart';
import 'widgets.dart';

class _ClientDetail {
  final String title, identity;
  final WidgetBuilder builder;
  final Completer<void> result = Completer<void>();
  _ClientDetail(this.title, this.identity, this.builder);
}

class ClientWorkspaceController extends ChangeNotifier {
  final navigatorKey = GlobalKey<NavigatorState>();
  final List<_ClientDetail> _details = [];
  bool get canGoBack => _details.isNotEmpty;
  String? get title => _details.lastOrNull?.title;
  int _serial = 0;
  Future<void> open({
    required String title,
    required WidgetBuilder builder,
    String? identity,
  }) {
    final detail = _ClientDetail(
      title,
      '${identity ?? title}:${_serial++}',
      builder,
    );
    _details.add(detail);
    notifyListeners();
    return detail.result.future;
  }

  bool back() {
    if (_details.isEmpty) return false;
    final detail = _details.removeLast();
    if (!detail.result.isCompleted) detail.result.complete();
    notifyListeners();
    return true;
  }

  void clear() {
    if (_details.isEmpty) return;
    for (final detail in _details) {
      if (!detail.result.isCompleted) detail.result.complete();
    }
    _details.clear();
    notifyListeners();
  }

  void _removed(Page<Object?> page) {
    final index = _details.indexWhere(
      (detail) => ValueKey(detail.identity) == page.key,
    );
    if (index < 0) return;
    final detail = _details.removeAt(index);
    if (!detail.result.isCompleted) detail.result.complete();
    notifyListeners();
  }

  @override
  void dispose() {
    clear();
    super.dispose();
  }
}

class ClientWorkspaceScope extends InheritedWidget {
  final ClientWorkspaceController controller;
  const ClientWorkspaceScope({
    super.key,
    required this.controller,
    required super.child,
  });
  static ClientWorkspaceController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<ClientWorkspaceScope>()
      ?.controller;
  @override
  bool updateShouldNotify(ClientWorkspaceScope oldWidget) =>
      controller != oldWidget.controller;
}

/// Body builders own a bounded viewport. Music details stay inside the shell's
/// Navigator on every platform, retaining its one real playback transport.
Future<void> openClientDetail(
  BuildContext context, {
  required String title,
  required WidgetBuilder builder,
  String? identity,
}) async {
  final host = ClientWorkspaceScope.maybeOf(context);
  if (host != null) {
    return host.open(title: title, builder: builder, identity: identity);
  }
  await Navigator.of(context, rootNavigator: true).push<void>(
    MaterialPageRoute(
      builder: (context) => ClientDetailPage(
        title: title,
        child: Builder(builder: builder),
      ),
    ),
  );
}

class ClientWorkspace extends StatelessWidget {
  final ClientWorkspaceController controller;
  final Widget child;
  const ClientWorkspace({
    super.key,
    required this.controller,
    required this.child,
  });
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => Navigator(
      key: controller.navigatorKey,
      pages: [
        MaterialPage<void>(
          key: const ValueKey('client-workspace-root'),
          child: child,
        ),
        for (final detail in controller._details)
          MaterialPage<void>(
            key: ValueKey(detail.identity),
            child: ClientDetailPage(
              title: detail.title,
              child: Builder(builder: detail.builder),
            ),
          ),
      ],
      onDidRemovePage: controller._removed,
    ),
  );
}

class ClientDetailPage extends StatelessWidget {
  final String title;
  final Widget child;
  final List<Widget>? actions;
  const ClientDetailPage({
    super.key,
    required this.title,
    required this.child,
    this.actions,
  });
  @override
  Widget build(BuildContext context) {
    final v = waveVisuals(context);
    return Scaffold(
      key: const Key('client-detail-page'),
      backgroundColor: v.background,
      appBar: AppBar(
        toolbarHeight: 58,
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: actions,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: v.line),
        ),
      ),
      body: child,
    );
  }
}
