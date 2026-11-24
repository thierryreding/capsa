import 'package:material_ui/material_ui.dart';

import '../account.dart';
import '../app_state.dart';
import '../i18n.dart';
import '../version.dart';
import 'common.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.app});

  final AppState app;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _server = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _server.text = widget.app.serverUrl ?? defaultServer;
    // Shown once when the session expired.
    if (widget.app.notice == 'expired') _error = t('login.expired');
  }

  @override
  void dispose() {
    _server.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final app = widget.app;
    String? server;
    if (!app.sameOrigin) {
      server = normalizeServerUrl(_server.text);
      if (server == null) {
        setState(() => _error = t('server.invalid'));
        return;
      }
    }
    setState(() => _busy = true);
    final problem = await app.login(_username.text.trim(), _password.text, server: server);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (problem == null) return;
      _password.clear();
      if (problem.startsWith('rateLimited:')) {
        _error = t('login.rateLimited', {'minutes': problem.split(':')[1]});
      } else {
        _error = t(problem == 'offline' ? 'login.offline' : 'login.failed');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    return CapsaPage(
      app: app,
      title: Text(t('app.title')),
      children: [
        CapsaCard(
          children: [
            Text(t('login.title'), style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 16),
            AutofillGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!app.sameOrigin) ...[
                    TextField(
                      controller: _server,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      decoration: InputDecoration(
                        labelText: t('server.label'),
                        helperText: t('server.hint'),
                      ),
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    controller: _username,
                    autocorrect: false,
                    autofillHints: const [AutofillHints.username],
                    decoration: InputDecoration(labelText: t('login.username')),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    obscureText: true,
                    autofillHints: const [AutofillHints.password],
                    decoration: InputDecoration(labelText: t('login.password')),
                    onSubmitted: (_) => _submit(),
                  ),
                ],
              ),
            ),
            if (_error != null) ...[const SizedBox(height: 12), ErrorText(_error!)],
            const SizedBox(height: 16),
            FilledButton(onPressed: _busy ? null : _submit, child: Text(t('login.submit'))),
          ],
        ),
      ],
    );
  }
}
