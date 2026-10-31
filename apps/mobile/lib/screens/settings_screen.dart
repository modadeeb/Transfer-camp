import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/push.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../widgets/common.dart';
import '../widgets/fields.dart';
import '../widgets/form_sheet.dart';
import 'change_password_screen.dart';
import 'login_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, this.tab});
  final String? tab;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final user = session.user;
    final c = context.c;
    if (user == null) return const Scaffold();
    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Card(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: Avatar(name: user.name, color: user.color, size: 44),
              title: Text(user.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
              subtitle: Text('@${user.username} · ${user.isManager ? 'المدير' : 'عضو'}', textDirection: TextDirection.rtl),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () => _editProfile(context, user),
            ),
          ),
          const SizedBox(height: 14),
          _Group(children: [
            _Link(Icons.notifications_none_rounded, 'الإشعارات', () => _push(context, const _NotificationsSettings())),
            _Link(Icons.lock_outline_rounded, 'تغيير كلمة المرور', () => _push(context, const ChangePasswordScreen(voluntary: true))),
            _Link(Icons.restore_from_trash_outlined, 'المحذوفات', () => _push(context, const _Trash())),
          ]),
          if (user.isManager) ...[
            const SizedBox(height: 14),
            _Group(children: [
              _Link(Icons.group_outlined, 'الأعضاء', () => _push(context, const MembersScreen())),
              _Link(Icons.badge_outlined, 'اسم المعسكر', () => _editCamp(context)),
            ]),
          ],
          const SizedBox(height: 14),
          _Group(children: [
            _Link(Icons.dns_outlined, 'عنوان الخادم', () => showServerSheet(context), trailing: Text(Uri.tryParse(session.api.server)?.host ?? '', style: TextStyle(color: c.muted, fontSize: 12))),
            _Link(Icons.logout_rounded, 'تسجيل الخروج', () async {
              final ok = await confirmDialog(context, title: 'تسجيل الخروج؟', confirmLabel: 'خروج');
              if (!ok || !context.mounted) return;
              await context.read<Push>().signOut();
              if (!context.mounted) return;
              await context.read<Session>().logout();
            }, danger: true),
          ]),
          const SizedBox(height: 18),
          Center(child: Text('${session.campName} · الإصدار 1.0.0', style: TextStyle(color: c.muted, fontSize: 12))),
        ],
      ),
    );
  }

  void _push(BuildContext context, Widget page) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

  Future<void> _editProfile(BuildContext context, User user) async {
    final session = context.read<Session>();
    final saved = await showFormSheet(
      context,
      title: 'حسابي',
      fields: [
        F('name', 'الاسم', FType.text, required: true, initial: user.name, maxLength: 60),
        F('phone', 'رقم الجوال', FType.text, initial: user.phone, maxLength: 30),
      ],
      onSubmit: (v) async {
        final r = await session.api.patch('/me', {'name': v['name'], 'phone': v['phone']});
        session.setUser(r['user'] as Map<String, dynamic>);
        await session.loadMembers();
      },
    );
    if (saved && context.mounted) toast(context, 'حُفظ حسابك');
  }

  Future<void> _editCamp(BuildContext context) async {
    final session = context.read<Session>();
    final saved = await showFormSheet(
      context,
      title: 'اسم المعسكر',
      fields: [F('campName', 'الاسم', FType.text, required: true, initial: session.campName, maxLength: 60)],
      onSubmit: (v) async {
        await session.api.patch('/camp', {'campName': v['campName']});
        await session.restore();
      },
    );
    if (saved && context.mounted) toast(context, 'حُفظ الاسم');
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          for (var i = 0; i < children.length; i++) ...[if (i > 0) const Divider(height: 1, indent: 56), children[i]],
        ]),
      );
}

class _Link extends StatelessWidget {
  const _Link(this.icon, this.label, this.onTap, {this.trailing, this.danger = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Widget? trailing;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return ListTile(
      leading: Icon(icon, color: danger ? c.danger : c.forest),
      title: Text(label, style: TextStyle(color: danger ? c.danger : null, fontWeight: FontWeight.w500)),
      trailing: trailing ?? (danger ? null : const Icon(Icons.chevron_left_rounded)),
      onTap: onTap,
    );
  }
}

// ---------------------------------------------------------------- notifications

class _NotificationsSettings extends StatefulWidget {
  const _NotificationsSettings();

  @override
  State<_NotificationsSettings> createState() => _NotificationsSettingsState();
}

class _NotificationsSettingsState extends State<_NotificationsSettings> {
  PushState? _state;
  bool _busy = false;
  bool _testing = false;
  Map<String, String> _types = {};
  Set<String> _disabled = {};
  String? _quietFrom;
  String? _quietTo;

  @override
  void initState() {
    super.initState();
    final n = context.read<Session>().user?.settings['notifications'];
    if (n is Map) {
      _disabled = ((n['disabled'] as List?) ?? const []).map((e) => '$e').toSet();
      _quietFrom = n['quietFrom'] as String?;
      _quietTo = n['quietTo'] as String?;
    }
    _load();
  }

  Future<void> _load() async {
    final push = context.read<Push>();
    final api = context.read<Session>().api;
    final s = await push.state();
    Map<String, String> types = {};
    try {
      final r = await api.get('/notifications', {'limit': 1});
      types = (r['types'] as Map? ?? const {}).map((k, v) => MapEntry('$k', '$v'));
    } on ApiException {
      // types list is just for the preferences
    }
    if (mounted) {
      setState(() {
        _state = s;
        _types = types;
      });
    }
  }

  Future<void> _toggle() async {
    final push = context.read<Push>();
    setState(() => _busy = true);
    try {
      final s = _state == PushState.on ? await push.disable() : await push.enable();
      if (!mounted) return;
      setState(() => _state = s);
      if (s == PushState.on) toast(context, 'فُعّلت الإشعارات على هذا الجهاز');
    } catch (e) {
      if (mounted) {
        setState(() => _state = PushState.error);
        showError(context, e);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _test() async {
    setState(() => _testing = true);
    try {
      final r = await context.read<Session>().api.post('/push/test');
      if (!mounted) return;
      final devices = (r['devices'] as num?) ?? 0;
      final sent = (r['sent'] as num?) ?? 0;
      if (r['configured'] != true) {
        toast(context, 'وصل الإشعار إلى الجرس 🔔 — إشعارات الجوال تحتاج إكمال إعداد Firebase');
      } else if (devices == 0) {
        toast(context, 'وصل الإشعار إلى الجرس 🔔 — فعّل الإشعارات على هذا الجهاز أولاً');
      } else if (sent > 0) {
        toast(context, 'أُرسل — يفترض أن يظهر خلال ثوانٍ');
      } else {
        toast(context, '${r['error'] ?? 'تعذّر الإرسال'}', error: true);
      }
      context.read<RefreshBus>().bump();
    } on ApiException catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _savePrefs() async {
    final session = context.read<Session>();
    try {
      final r = await session.api.patch('/me', {
        'settings': {
          'notifications': {'disabled': _disabled.toList(), 'quietFrom': _quietFrom, 'quietTo': _quietTo},
        },
      });
      session.setUser(r['user'] as Map<String, dynamic>);
      if (mounted) toast(context, 'حُفظت تفضيلات الإشعارات');
    } on ApiException catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final s = _state;
    return Scaffold(
      appBar: AppBar(title: const Text('الإشعارات')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          SectionCard(
            title: 'إشعارات الجوال',
            subtitle: 'عبر Firebase',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (s == null)
                  const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator()))
                else
                  Text(Push.describe(s), style: TextStyle(color: [PushState.denied, PushState.error, PushState.notConfigured].contains(s) ? c.danger : c.muted)),
                const SizedBox(height: 12),
                if (s == PushState.on || s == PushState.off || s == PushState.error)
                  FilledButton.icon(
                    onPressed: _busy ? null : _toggle,
                    icon: const Icon(Icons.notifications_active_outlined),
                    label: Text(s == PushState.on ? 'إيقاف على هذا الجهاز' : 'تفعيل على هذا الجهاز'),
                  ),
                const SizedBox(height: 8),
                OutlinedButton(onPressed: _testing ? null : _test, child: const Text('إرسال إشعار تجريبي')),
                const SizedBox(height: 8),
                Text('كل الإشعارات تبقى محفوظة في الجرس داخل التطبيق حتى لو أوقفتها هنا.', style: TextStyle(color: c.muted, fontSize: 12.5)),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SectionCard(
            title: 'ما يصلني',
            padding: const EdgeInsets.fromLTRB(8, 16, 8, 16),
            child: Column(
              children: [
                for (final e in _types.entries)
                  SwitchListTile(
                    dense: true,
                    title: Text(e.value),
                    value: !_disabled.contains(e.key),
                    onChanged: (on) => setState(() => on ? _disabled.remove(e.key) : _disabled.add(e.key)),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const FieldLabel('أوقات الهدوء', hint: 'لا تصل إشعارات للجوال في هذه الفترة (العاجلة تصل دائماً)'),
                      Row(
                        children: [
                          Expanded(child: TimeField(label: 'من', value: _quietFrom, onChanged: (v) => setState(() => _quietFrom = v))),
                          const SizedBox(width: 10),
                          Expanded(child: TimeField(label: 'إلى', value: _quietTo, onChanged: (v) => setState(() => _quietTo = v))),
                        ],
                      ),
                      const SizedBox(height: 14),
                      FilledButton(onPressed: _savePrefs, child: const Text('حفظ التفضيلات')),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- trash

class _Trash extends StatelessWidget {
  const _Trash();

  @override
  Widget build(BuildContext context) {
    final api = context.read<Session>().api;
    final c = context.c;
    return Scaffold(
      appBar: AppBar(title: const Text('المحذوفات')),
      body: Loader(
        load: () => api.get('/trash'),
        builder: (context, data, reload) {
          final items = (data['items'] as List? ?? const []).whereType<Map<String, dynamic>>().toList();
          if (items.isEmpty) {
            return ListView(children: const [EmptyState(icon: Icons.delete_outline_rounded, title: 'سلة المحذوفات فارغة', body: 'يبقى المحذوف هنا 30 يوماً')]);
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: items.length + 1,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              if (i == 0) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Text('تُحذف نهائياً بعد 30 يوماً', style: TextStyle(color: c.muted, fontSize: 12.5)),
                );
              }
              final it = items[i - 1];
              return ListTile(
                title: Text('${it['title'] ?? ''}'),
                subtitle: Text('${it['label']} · ${timeAgo('${it['deletedAt']}')}'),
                trailing: TextButton(
                  onPressed: () async {
                    try {
                      await api.post('/trash/restore', {'entity': it['entity'], 'id': it['id']});
                      if (!context.mounted) return;
                      toast(context, 'استُعيد');
                      context.read<RefreshBus>().bump();
                    } on ApiException catch (e) {
                      if (context.mounted) showError(context, e);
                    }
                  },
                  child: const Text('استعادة'),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------- members (manager)

const _memberColors = ['#243F35', '#56856A', '#B68A47', '#4F6D8A', '#8A5A6E', '#6E7F4F', '#A0644B', '#5B6B9A'];

class MembersScreen extends StatelessWidget {
  const MembersScreen({super.key});

  Future<void> _showPassword(BuildContext context, String name, String username, String password) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('بيانات دخول $name'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('أرسلها له. سيُطلب منه تغيير كلمة المرور عند أول دخول.'),
            const SizedBox(height: 12),
            SelectableText('اسم المستخدم: $username\nكلمة المرور المؤقتة: $password', textDirection: TextDirection.rtl, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: 'اسم المستخدم: $username\nكلمة المرور المؤقتة: $password'));
              toast(ctx, 'نُسخت');
            },
            child: const Text('نسخ'),
          ),
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('تم')),
        ],
      ),
    );
  }

  Future<void> _edit(BuildContext context, [User? m]) async {
    final session = context.read<Session>();
    String? username;
    String? password;
    String? newName;
    final saved = await showFormSheet(
      context,
      title: m == null ? 'عضو جديد' : 'تعديل ${m.name}',
      fields: [
        F('name', 'الاسم', FType.text, required: true, initial: m?.name, maxLength: 60),
        if (m == null) const F('username', 'اسم المستخدم (بالإنجليزية)', FType.text, required: true, maxLength: 32, hint: 'مثال: salem'),
        F('specialty', 'التخصص', FType.select, options: specialtyLabels, initial: m?.specialty),
        F('role', 'الدور', FType.select, required: true, options: const {'member': 'عضو', 'manager': 'مدير'}, initial: m?.role ?? 'member'),
        F('phone', 'رقم الجوال', FType.text, initial: m?.phone, maxLength: 30),
      ],
      onSubmit: (v) async {
        if (m == null) {
          final r = await session.api.post('/members', {
            ...v,
            'username': '${v['username']}'.toLowerCase(),
            'color': _memberColors[session.members.length % _memberColors.length],
          });
          username = '${(r['member'] as Map)['username']}';
          newName = '${v['name']}';
          password = '${r['tempPassword']}';
        } else {
          await session.api.patch('/members/${m.id}', v);
        }
        await session.loadMembers();
      },
    );
    if (!saved || !context.mounted) return;
    context.read<RefreshBus>().bump();
    if (password != null) {
      await _showPassword(context, newName ?? '', username ?? '', password!);
    } else {
      toast(context, 'حُفظ');
    }
  }

  Future<void> _actions(BuildContext context, User m, List<User> list) async {
    final session = context.read<Session>();
    final api = session.api;
    final i = list.indexOf(m);
    final isMe = m.id == session.user?.id;
    final key = await showActions(context, title: m.name, actions: [
      const SheetAction('edit', 'تعديل', Icons.edit_outlined),
      if (!isMe) const SheetAction('reset', 'كلمة مرور مؤقتة جديدة', Icons.key_outlined),
      if (i > 0) const SheetAction('up', 'تحريك لأعلى', Icons.arrow_upward_rounded),
      if (i < list.length - 1) const SheetAction('down', 'تحريك لأسفل', Icons.arrow_downward_rounded),
      if (!isMe) m.archived ? const SheetAction('unarchive', 'إعادة تفعيل', Icons.unarchive_outlined) : const SheetAction('archive', 'أرشفة (غادر المعسكر)', Icons.archive_outlined),
      if (!isMe) const SheetAction('delete', 'حذف', Icons.delete_outline_rounded, danger: true),
    ]);
    if (key == null || !context.mounted) return;
    try {
      switch (key) {
        case 'edit':
          await _edit(context, m);
        case 'reset':
          final confirmed = await confirmDialog(context, title: 'كلمة مرور جديدة لـ${m.name}؟', body: 'ستُلغى جلساته الحالية ويُطلب منه تغييرها عند الدخول.', confirmLabel: 'إنشاء');
          if (!confirmed) return;
          final r = await api.post('/members/${m.id}/reset-password');
          if (context.mounted) await _showPassword(context, m.name, m.username, '${r['tempPassword']}');
        case 'up':
        case 'down':
          final ids = list.map((x) => x.id).toList();
          final j = key == 'up' ? i - 1 : i + 1;
          ids[i] = list[j].id;
          ids[j] = m.id;
          await api.post('/reorder', {'entity': 'members', 'ids': ids});
          await session.loadMembers();
        case 'archive':
        case 'unarchive':
          await api.post('/members/${m.id}/$key');
          await session.loadMembers();
          if (context.mounted) toast(context, key == 'archive' ? 'أُرشف العضو' : 'أُعيد تفعيل العضو');
        case 'delete':
          final ok = await confirmDialog(context, title: 'حذف ${m.name}؟', body: 'يُفضّل الأرشفة إن كان له سجل مهام أو مال.', confirmLabel: 'حذف', danger: true);
          if (!ok) return;
          await api.delete('/members/${m.id}');
          await session.loadMembers();
          if (context.mounted) toast(context, 'حُذف العضو');
      }
      if (context.mounted) context.read<RefreshBus>().bump();
    } on ApiException catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final c = context.c;
    final list = session.members;
    return Scaffold(
      appBar: AppBar(title: const Text('الأعضاء')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'member-fab',
        onPressed: () => _edit(context),
        icon: const Icon(Icons.person_add_alt_1_outlined),
        label: const Text('عضو'),
      ),
      body: RefreshIndicator(
        onRefresh: session.loadMembers,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (var i = 0; i < list.length; i++) ...[
                    if (i > 0) const Divider(height: 1, indent: 64),
                    ListTile(
                      leading: Avatar(name: list[i].name, color: list[i].color, size: 38),
                      title: Text(list[i].name, style: TextStyle(fontWeight: FontWeight.w600, color: list[i].archived ? c.muted : null)),
                      subtitle: Text([
                        '@${list[i].username}',
                        if (list[i].isManager) 'مدير',
                        if (list[i].specialty != null) specialtyLabels[list[i].specialty] ?? '',
                        if (list[i].archived) 'مؤرشف',
                      ].join(' · ')),
                      trailing: const Icon(Icons.more_vert_rounded),
                      onTap: () => _actions(context, list[i], list),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
