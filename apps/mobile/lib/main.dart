import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'core/api.dart';
import 'core/push.dart';
import 'core/router.dart';
import 'core/session.dart';
import 'core/theme.dart';
import 'widgets/common.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final api = await Api.create();
  final session = Session(api);
  final push = Push(api);
  runApp(CampApp(session: session, push: push));
  session.restore();
}

class CampApp extends StatefulWidget {
  const CampApp({super.key, required this.session, required this.push});
  final Session session;
  final Push push;

  @override
  State<CampApp> createState() => _CampAppState();
}

class _CampAppState extends State<CampApp> {
  late final router = buildRouter(widget.session);
  final bus = RefreshBus();

  @override
  void initState() {
    super.initState();
    widget.push.onOpenLink = (link) => router.push(link);
    widget.push.onMessage = bus.bump;
    widget.session.addListener(_onSession);
  }

  void _onSession() {
    if (widget.session.status == SessionStatus.signedIn) widget.push.resume();
  }

  @override
  void dispose() {
    widget.session.removeListener(_onSession);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: widget.session),
        ChangeNotifierProvider.value(value: bus),
        Provider.value(value: widget.push),
      ],
      child: MaterialApp.router(
        title: 'معسكر نقلة',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: ThemeMode.system,
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        routerConfig: router,
      ),
    );
  }
}
