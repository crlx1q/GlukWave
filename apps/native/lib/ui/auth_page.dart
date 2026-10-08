import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../core/controller.dart';
import '../core/models.dart';
import '../l10n/wave_localizations.dart';
import 'appearance_panel.dart';
import 'auth_visuals.dart';
import 'lofi.dart';
import 'widgets.dart';

class AuthPage extends StatefulWidget {
  final WaveController controller;
  final Future<void> Function()? onServerDebug;
  final Future<void> Function(BuildContext, WaveController)? onQrLogin;
  const AuthPage({
    super.key,
    required this.controller,
    this.onServerDebug,
    this.onQrLogin,
  });
  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  WaveController get c => widget.controller;
  final email = TextEditingController(),
      password = TextEditingController(),
      username = TextEditingController(),
      name = TextEditingController();
  final form = GlobalKey<FormState>();
  bool register = false, busy = false, obscure = true;
  String? error;
  @override
  void dispose() {
    c.cancelAuth = true;
    for (final field in [email, password, username, name]) {
      field.dispose();
    }
    super.dispose();
  }

  Future<void> submit(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void authenticate() {
    if (form.currentState?.validate() != true) return;
    submit(
      () => c.authenticate(
        email.text,
        password.text,
        username: register ? username.text : null,
        displayName: register ? name.text : null,
      ),
    );
  }

  Future<void> forgot() async {
    final field = TextEditingController(text: email.text);
    final result = await showWaveDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(wt('native.8166d3a910', context: dialog)),
        content: TextField(
          controller: field,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            labelText: wt('native.108aa2199f', context: dialog),
          ),
          onSubmitted: (value) => Navigator.pop(dialog, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: Text(wt('native.0ec753be8d', context: dialog)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, field.text.trim()),
            child: Text(wt('native.398c7d4f7b', context: dialog)),
          ),
        ],
      ),
    );
    field.dispose();
    if (result == null || result.isEmpty) return;
    await c.requestPasswordReset(result);
    c.tell(wt('native.b58e16258e'));
  }

  InputDecoration field(String key, IconData icon) => InputDecoration(
    labelText: wt(key, context: context),
    prefixIcon: Icon(icon, size: 19),
    filled: true,
    fillColor: waveVisuals(context).surface,
  );

  Widget mode(bool value, String key) => Expanded(
    child: TextButton(
      key: Key(value ? 'auth-mode-register' : 'auth-mode-login'),
      onPressed: busy
          ? null
          : () => setState(() {
              register = value;
              error = null;
            }),
      style: TextButton.styleFrom(
        backgroundColor: register == value
            ? waveVisuals(context).surface
            : Colors.transparent,
        foregroundColor: register == value
            ? waveVisuals(context).ink
            : waveVisuals(context).muted,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      ),
      child: Text(
        wt(key, context: context),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
    ),
  );

  Widget formContent(bool desktop) {
    final v = waveVisuals(context),
        legacyCaptcha = c.captchaEnabled && !c.supportsNativeCaptcha;
    return AutofillGroup(
      child: Form(
        key: form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!desktop) ...[
              const Brand(size: 38, animated: true),
              const SizedBox(height: 32),
            ],
            Text(
              register
                  ? wt('native.4541ac0a47', context: context)
                  : wt('native.6532324a05', context: context),
              style: const TextStyle(
                fontSize: 31,
                letterSpacing: -1.2,
                height: 1.15,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 11),
            Text(
              register
                  ? wt('native.8ad78c0f86', context: context)
                  : wt('native.691934d883', context: context),
              style: TextStyle(color: v.muted, fontSize: 12, height: 1.6),
            ),
            const SizedBox(height: 25),
            DecoratedBox(
              decoration: BoxDecoration(
                color: v.accentSoft.withValues(alpha: .6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: Row(
                  children: [
                    mode(false, 'auth.signin'),
                    const SizedBox(width: 3),
                    mode(true, 'auth.signup'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 22),
            if (legacyCaptcha) ...[
              Text(
                wt('auth.captchaBrowser', context: context),
                style: TextStyle(color: v.muted, fontSize: 12, height: 1.6),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: busy || !c.online
                      ? null
                      : () => submit(() => c.browserLogin(method: 'email')),
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: Text(wt('native.d8e062885a', context: context)),
                ),
              ),
            ] else ...[
              TextFormField(
                key: const Key('auth-email'),
                controller: email,
                keyboardType: register
                    ? TextInputType.emailAddress
                    : TextInputType.text,
                textInputAction: TextInputAction.next,
                autofillHints: [
                  register ? AutofillHints.email : AutofillHints.username,
                ],
                decoration: field(
                  register ? 'native.108aa2199f' : 'auth.identity',
                  Icons.alternate_email_rounded,
                ),
                validator: (value) =>
                    value != null &&
                        (register
                            ? RegExp(
                                r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                              ).hasMatch(value.trim())
                            : value.trim().isNotEmpty &&
                                  value.trim().length <= 254)
                    ? null
                    : wt('native.eba037f95d', context: context),
              ),
              const SizedBox(height: 14),
              TextFormField(
                key: const Key('auth-password'),
                controller: password,
                obscureText: obscure,
                textInputAction: register
                    ? TextInputAction.next
                    : TextInputAction.done,
                autofillHints: [
                  register ? AutofillHints.newPassword : AutofillHints.password,
                ],
                decoration:
                    field(
                      'native.14f7c63cc1',
                      Icons.lock_outline_rounded,
                    ).copyWith(
                      suffixIcon: IconButton(
                        tooltip: wt(
                          obscure ? 'native.07fefc08da' : 'native.8992c9df0b',
                          context: context,
                        ),
                        onPressed: () => setState(() => obscure = !obscure),
                        icon: Icon(
                          obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          size: 19,
                        ),
                      ),
                    ),
                validator: (value) =>
                    value == null || value.length < (register ? 10 : 1)
                    ? wt(
                        register ? 'native.817314e802' : 'native.3e56a59a30',
                        context: context,
                      )
                    : value.length > 128
                    ? wt('auth.passwordlimit', context: context)
                    : null,
                onFieldSubmitted: (_) {
                  if (!register) authenticate();
                },
              ),
              AuthRegisterReveal(
                child: register
                    ? Column(
                        children: [
                          const SizedBox(height: 14),
                          TextFormField(
                            key: const Key('auth-username'),
                            controller: username,
                            maxLength: 24,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.newUsername],
                            decoration:
                                field(
                                  'native.db0d5a3cc6',
                                  Icons.person_outline_rounded,
                                ).copyWith(
                                  hintText: wt(
                                    'native.6bc8d80189',
                                    context: context,
                                  ),
                                ),
                            validator: (value) =>
                                value != null &&
                                    RegExp(
                                      r'^[a-zA-Z0-9_]{3,24}$',
                                    ).hasMatch(value.trim())
                                ? null
                                : wt('auth.usernamelimit', context: context),
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            key: const Key('auth-name'),
                            controller: name,
                            maxLength: 60,
                            textInputAction: TextInputAction.done,
                            autofillHints: const [AutofillHints.name],
                            decoration: field(
                              'native.f11858d578',
                              Icons.badge_outlined,
                            ),
                            onFieldSubmitted: (_) => authenticate(),
                          ),
                        ],
                      )
                    : const SizedBox(width: double.infinity),
              ),
              if (c.captchaEnabled)
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.verified_user_outlined,
                        size: 16,
                        color: v.muted,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          wt('auth.captcha', context: context),
                          style: TextStyle(
                            color: v.muted,
                            fontSize: 11,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  key: const Key('auth-submit'),
                  onPressed: busy || !c.online ? null : authenticate,
                  child: busy
                      ? SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: v.background,
                          ),
                        )
                      : Text(
                          wt(
                            register
                                ? 'native.8d29ff5c84'
                                : 'native.939e95a11d',
                            context: context,
                          ),
                        ),
                ),
              ),
            ],
            if (!register && !legacyCaptcha)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: busy || !c.online ? null : () => submit(forgot),
                  child: Text(
                    wt('native.24ee8363c4', context: context),
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: Divider(color: v.line)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Text(
                    wt('native.30bb0333ca', context: context),
                    style: TextStyle(color: v.muted, fontSize: 11),
                  ),
                ),
                Expanded(child: Divider(color: v.line)),
              ],
            ),
            const SizedBox(height: 17),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                key: const Key('auth-google'),
                onPressed: busy || object(c.config['auth'])['google'] != true
                    ? null
                    : () => submit(c.browserLogin),
                icon: const GoogleIdentityMark(),
                label: Text(
                  wt('auth.google', context: context),
                  style: const TextStyle(fontSize: 12),
                ),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 48),
                  backgroundColor:
                      Theme.of(context).brightness == Brightness.light
                      ? Colors.white
                      : const Color(0xff131314),
                ),
              ),
            ),
            if (defaultTargetPlatform == TargetPlatform.windows &&
                widget.onQrLogin != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    key: const Key('auth-qr'),
                    onPressed: busy || !c.online
                        ? null
                        : () => widget.onQrLogin!(context, c),
                    icon: const Icon(Icons.qr_code_rounded, size: 19),
                    label: Text(wt('native.304d2e9c36', context: context)),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 46),
                    ),
                  ),
                ),
              ),
            if (busy)
              Align(
                alignment: Alignment.center,
                child: TextButton(
                  onPressed: () {
                    c.cancelAuth = true;
                  },
                  child: Text(wt('native.7a18c5e61a', context: context)),
                ),
              ),
            if (error != null || c.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    error ?? c.error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12,
                      height: 1.6,
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 24),
            Center(
              child: TextButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => LofiPage(controller: c),
                  ),
                ),
                icon: const Icon(Icons.nightlight_outlined, size: 16),
                label: Text(wt('native.847e19da38', context: context)),
              ),
            ),
            Center(
              child: GestureDetector(
                onLongPress: widget.onServerDebug,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'GlukWave · 1.0.0',
                    style: TextStyle(color: v.muted, fontSize: 10),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final v = waveVisuals(context);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: v.background,
        toolbarHeight: 48,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          if (c.appearanceStore != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: TextButton.icon(
                key: const Key('open-appearance'),
                onPressed: () => showAppearance(context, c.appearanceStore!),
                icon: const Icon(Icons.palette_outlined, size: 17),
                label: Text(wt('native.d206f1bed0', context: context)),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final desktop = constraints.maxWidth >= 900;
            return Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  desktop ? 48 : 24,
                  desktop ? 38 : 12,
                  desktop ? 48 : 24,
                  20,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1040),
                  child: Row(
                    children: [
                      if (desktop)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(right: 80),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Brand(size: 43, animated: true),
                                const SizedBox(height: 43),
                                Text(
                                  wt('native.fc7b54ff4d', context: context),
                                  style: const TextStyle(
                                    fontSize: 49,
                                    letterSpacing: -2,
                                    height: 1.1,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 23),
                                Text(
                                  wt('native.a889d29336', context: context),
                                  style: TextStyle(
                                    color: v.muted,
                                    fontSize: 15,
                                    height: 1.85,
                                  ),
                                ),
                                const SizedBox(height: 24),
                                const AuthAmbientWave(),
                              ],
                            ),
                          ),
                        ),
                      Expanded(
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 390),
                            child: formContent(desktop),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
