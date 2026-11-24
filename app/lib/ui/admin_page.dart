import 'package:material_ui/material_ui.dart';

import '../account.dart';
import '../api/client.dart';
import '../app_state.dart';
import '../i18n.dart';
import '../learning/stats.dart';
import 'common.dart';
import 'stats_view.dart';
import 'theme.dart';

/// Account management for parents (SPEC 5 admin API); needs the server.
class AdminPage extends StatefulWidget {
  const AdminPage({super.key, required this.app});

  final AppState app;

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  List<UserInfo>? _users;
  List<ProfileSummary> _profiles = [];
  String? _loadError;
  String? _message;

  AppState get app => widget.app;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([app.api.users(), app.api.profiles()]);
      if (!mounted) return;
      setState(() {
        _loadError = null;
        _users = results[0] as List<UserInfo>;
        _profiles = results[1] as List<ProfileSummary>;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _loadError = errorMessage(e));
    }
  }

  void _replace(UserInfo updated) => setState(() {
    _users = [for (final u in _users ?? <UserInfo>[]) u.id == updated.id ? updated : u];
  });

  Future<void> _create() async {
    final created = await showDialog<UserInfo>(
      context: context,
      builder: (_) => _NewUserDialog(app: app, profiles: _profiles),
    );
    if (created == null || !mounted) return;
    setState(() {
      _users = [...?_users, created]
        ..sort((a, b) => a.username.toLowerCase().compareTo(b.username.toLowerCase()));
      _message = t('admin.created', {'name': created.name});
    });
  }

  @override
  Widget build(BuildContext context) {
    final users = _users;
    return CapsaPage(
      app: app,
      title: Text(t('admin.title')),
      leading: BackButton(onPressed: app.goHome),
      children: [
        if (_loadError != null)
          CapsaCard(
            children: [
              ErrorText(_loadError!),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: _load, child: Text(t('sync.now'))),
            ],
          )
        else if (users == null)
          Hint(t('admin.loading'))
        else ...[
          CapsaCard(
            children: [
              Text(t('admin.users'), style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              for (final user in users)
                _UserTile(
                  key: ValueKey(user.id),
                  app: app,
                  user: user,
                  profiles: _profiles,
                  onChange: _replace,
                ),
              if (_message != null) Hint(_message!),
            ],
          ),
          FilledButton.icon(
            onPressed: _create,
            icon: const Icon(Icons.person_add_alt),
            label: Text(t('admin.new')),
          ),
        ],
      ],
    );
  }
}

class _ProfileChoice extends StatelessWidget {
  const _ProfileChoice({required this.profiles, required this.selected, required this.onChanged});

  final List<ProfileSummary> profiles;
  final List<String> selected;
  final void Function(List<String>) onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Text(t('admin.profiles'), style: Theme.of(context).textTheme.titleSmall),
      ),
      for (final p in profiles)
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(p.title),
          value: selected.contains(p.id),
          onChanged: (on) => onChanged(
            on == true ? [...selected, p.id] : selected.where((x) => x != p.id).toList(),
          ),
        ),
    ],
  );
}

class _NewUserDialog extends StatefulWidget {
  const _NewUserDialog({required this.app, required this.profiles});

  final AppState app;
  final List<ProfileSummary> profiles;

  @override
  State<_NewUserDialog> createState() => _NewUserDialogState();
}

class _NewUserDialogState extends State<_NewUserDialog> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  String _role = 'learner';
  List<String> _selected = [];
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final username = _username.text.trim();
    final problem = checkNewUser(username, _password.text);
    if (problem != null) return setState(() => _error = problem);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final user = await widget.app.api.createUser({
        'username': username,
        'password': _password.text,
        'role': _role,
        'display_name': _name.text.trim().isEmpty ? null : _name.text.trim(),
        'profiles': _role == 'learner' ? _selected : <String>[],
      });
      if (mounted) Navigator.pop(context, user);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(t('admin.new')),
    scrollable: true,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _username,
          autocorrect: false,
          decoration: InputDecoration(labelText: t('admin.username')),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _password,
          obscureText: true,
          autofillHints: const [AutofillHints.newPassword],
          decoration: InputDecoration(
            labelText: t('admin.password'),
            helperText: t('admin.passwordHint'),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _name,
          maxLength: displayNameMax,
          decoration: InputDecoration(
            labelText: t('admin.displayName'),
            helperText: t('admin.displayNameHint'),
          ),
        ),
        Text(t('admin.role'), style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        SegmentedButton<String>(
          segments: [
            for (final r in ['learner', 'admin'])
              ButtonSegment(value: r, label: Text(t('admin.role.$r'))),
          ],
          selected: {_role},
          onSelectionChanged: (s) => setState(() => _role = s.first),
        ),
        if (_role == 'learner')
          _ProfileChoice(
            profiles: widget.profiles,
            selected: _selected,
            onChanged: (s) => setState(() => _selected = s),
          ),
        if (_error != null) ...[const SizedBox(height: 8), ErrorText(_error!)],
      ],
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: Text(t('admin.cancel'))),
      FilledButton(onPressed: _busy ? null : _submit, child: Text(t('admin.create'))),
    ],
  );
}

class _UserTile extends StatefulWidget {
  const _UserTile({
    super.key,
    required this.app,
    required this.user,
    required this.profiles,
    required this.onChange,
  });

  final AppState app;
  final UserInfo user;
  final List<ProfileSummary> profiles;
  final void Function(UserInfo) onChange;

  @override
  State<_UserTile> createState() => _UserTileState();
}

class _UserTileState extends State<_UserTile> {
  bool _editing = false;
  bool _showProgress = false;
  final _name = TextEditingController();
  final _password = TextEditingController();
  List<String> _selected = [];
  String? _message;
  String? _error;
  bool _busy = false;

  UserInfo get user => widget.user;

  @override
  void dispose() {
    _name.dispose();
    _password.dispose();
    super.dispose();
  }

  void _open() => setState(() {
    _name.text = user.displayName ?? '';
    _selected = [...user.profiles];
    _password.clear();
    _message = _error = null;
    _editing = true;
  });

  Future<bool> _change(Json body, String done) async {
    setState(() {
      _busy = true;
      _error = _message = null;
    });
    try {
      widget.onChange(await widget.app.api.updateUser(user.id, body));
      if (mounted) setState(() => _message = done);
      return true;
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final ok = await _change({
      'display_name': _name.text.trim().isEmpty ? null : _name.text.trim(),
      if (user.role == 'learner') 'profiles': _selected,
    }, t('admin.saved'));
    if (ok && mounted) setState(() => _editing = false);
  }

  Future<void> _resetPassword() async {
    final problem = checkPassword(_password.text);
    if (problem != null) return setState(() => _error = problem);
    final ok = await _change({
      'password': _password.text,
    }, t('admin.passwordReset', {'name': user.name}));
    if (ok) _password.clear();
  }

  @override
  Widget build(BuildContext context) {
    final colors = CapsaColors.of(context);
    final self = user.id == widget.app.me?.id;
    final titles = [
      for (final id in user.profiles)
        widget.profiles.where((p) => p.id == id).firstOrNull?.title ?? id,
    ].join(', ');
    final details =
        '${t('admin.role.${user.role}')} · '
        '${user.role == 'admin' ? t('admin.allProfiles') : (titles.isEmpty ? t('admin.noProfiles') : titles)}';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            enabled: !user.disabled,
            title: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: user.name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  if (user.displayName != null) TextSpan(text: ' (${user.username})'),
                  if (self) TextSpan(text: ' – ${t('admin.you')}'),
                  if (user.disabled)
                    TextSpan(
                      text: ' – ${t('admin.disabled')}',
                      style: TextStyle(color: colors.bad),
                    ),
                ],
              ),
            ),
            subtitle: Text(details),
            trailing: Wrap(
              children: [
                IconButton(
                  tooltip: t('stats.progress'),
                  isSelected: _showProgress,
                  onPressed: () => setState(() => _showProgress = !_showProgress),
                  icon: const Icon(Icons.bar_chart),
                ),
                if (!_editing)
                  IconButton(
                    tooltip: t('admin.edit'),
                    onPressed: _open,
                    icon: const Icon(Icons.edit_outlined),
                  ),
              ],
            ),
          ),
          if (_showProgress) _AdminProgress(app: widget.app, user: user, profiles: widget.profiles),
          if (_editing) ...[
            TextField(
              controller: _name,
              maxLength: displayNameMax,
              decoration: InputDecoration(labelText: t('admin.displayName')),
            ),
            if (user.role == 'learner')
              _ProfileChoice(
                profiles: widget.profiles,
                selected: _selected,
                onChanged: (s) => setState(() => _selected = s),
              ),
            Wrap(
              spacing: 8,
              children: [
                FilledButton(onPressed: _busy ? null : _save, child: Text(t('admin.save'))),
                OutlinedButton(
                  onPressed: () => setState(() => _editing = false),
                  child: Text(t('admin.cancel')),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _password,
                    obscureText: true,
                    autofillHints: const [AutofillHints.newPassword],
                    decoration: InputDecoration(labelText: t('admin.newPassword')),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _busy ? null : _resetPassword,
                  child: Text(t('admin.resetPassword')),
                ),
              ],
            ),
            if (!self) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () => _change({'disabled': !user.disabled}, t('admin.saved')),
                  child: Text(user.disabled ? t('admin.enable') : t('admin.disable')),
                ),
              ),
            ],
            const SizedBox(height: 12),
          ],
          if (_message != null) Hint(_message!),
          if (_error != null) ErrorText(_error!),
        ],
      ),
    );
  }
}

/// An account's statistics for one book, as computed by the server.
class _AdminProgress extends StatefulWidget {
  const _AdminProgress({required this.app, required this.user, required this.profiles});

  final AppState app;
  final UserInfo user;
  final List<ProfileSummary> profiles;

  @override
  State<_AdminProgress> createState() => _AdminProgressState();
}

class _AdminProgressState extends State<_AdminProgress> {
  String? _profileId;
  LearningStats? _stats;
  String? _error;

  // Learners: their released books; admins see (and may learn) all books.
  List<ProfileSummary> get _books => widget.user.role == 'admin'
      ? widget.profiles
      : widget.profiles.where((p) => widget.user.profiles.contains(p.id)).toList();

  @override
  void initState() {
    super.initState();
    _load(_books.firstOrNull?.id);
  }

  Future<void> _load(String? id) async {
    if (id == null) return;
    setState(() {
      _profileId = id;
      _stats = null;
      _error = null;
    });
    try {
      final stats = await widget.app.api.userProgress(
        widget.user.id,
        id,
        widget.app.config.utcOffsetMinutes,
      );
      if (mounted && _profileId == id) setState(() => _stats = stats);
    } on ApiException catch (e) {
      if (mounted && _profileId == id) setState(() => _error = errorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final books = _books;
    if (books.isEmpty) return Hint(t('admin.noProfiles'));
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (books.length > 1)
            DropdownMenu<String>(
              label: Text(t('home.profile')),
              initialSelection: _profileId,
              expandedInsets: EdgeInsets.zero,
              onSelected: _load,
              dropdownMenuEntries: [
                for (final p in books) DropdownMenuEntry(value: p.id, label: p.title),
              ],
            ),
          if (_error != null)
            ErrorText(_error!)
          else if (_stats != null)
            StatsView(stats: _stats!, now: widget.app.now())
          else
            Hint(t('stats.loading')),
        ],
      ),
    );
  }
}
