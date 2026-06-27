import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:local_auth/local_auth.dart';
import 'package:google_fonts/google_fonts.dart';

// ----------------- Кольори / тема -----------------
const gold = Color(0xFFD8A657);
const pos = Color(0xFF3FBF8F);
const neg = Color(0xFFE0796B);
const blue = Color(0xFF7AA2E8);

// кольори, що адаптуються під світлу тему (для читабельності)
bool _dk(BuildContext c) => Theme.of(c).brightness == Brightness.dark;
Color cPos(BuildContext c) => _dk(c) ? const Color(0xFF3FBF8F) : const Color(0xFF1E9E6A);
Color cNeg(BuildContext c) => _dk(c) ? const Color(0xFFE0796B) : const Color(0xFFCF5340);
Color cBlue(BuildContext c) => _dk(c) ? const Color(0xFF7AA2E8) : const Color(0xFF3A66C8);
Color cPnl(BuildContext c, num v) => v > 0 ? cPos(c) : (v < 0 ? cNeg(c) : Colors.grey);

ThemeData buildTheme(bool dark) {
  final bg = dark ? const Color(0xFF0E141B) : const Color(0xFFF3F5F8);
  final surface = dark ? const Color(0xFF161E29) : Colors.white;
  final txt = dark ? const Color(0xFFE6EDF3) : const Color(0xFF1A2433);
  final base = ThemeData(
    brightness: dark ? Brightness.dark : Brightness.light,
    scaffoldBackgroundColor: bg,
    cardColor: surface,
    colorScheme: (dark ? const ColorScheme.dark() : const ColorScheme.light())
        .copyWith(primary: gold, surface: surface),
    useMaterial3: true,
  );
  return base.copyWith(
    textTheme: GoogleFonts.interTextTheme(base.textTheme).apply(bodyColor: txt, displayColor: txt),
    appBarTheme: AppBarTheme(
      backgroundColor: surface, foregroundColor: txt, elevation: 0,
      titleTextStyle: GoogleFonts.spaceGrotesk(fontSize: 22, fontWeight: FontWeight.w700, color: txt),
    ),
  );
}

// заголовок (Space Grotesk) та моноширинний стиль для чисел (JetBrains Mono)
TextStyle headFont({double size = 16, FontWeight w = FontWeight.w700, Color? c}) =>
    GoogleFonts.spaceGrotesk(fontSize: size, fontWeight: w, color: c);
TextStyle monoFont({double size = 14, FontWeight w = FontWeight.w600, Color? c}) =>
    GoogleFonts.jetBrainsMono(fontSize: size, fontWeight: w, color: c);

// ----------------- Налаштування (URL + токен + тема) -----------------
class Settings extends ChangeNotifier {
  String baseUrl = '';
  String token = '';
  bool dark = true;
  bool biometric = false;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    baseUrl = p.getString('baseUrl') ?? '';
    token = p.getString('token') ?? '';
    dark = p.getBool('dark') ?? true;
    biometric = p.getBool('biometric') ?? false;
    notifyListeners();
  }

  Future<void> save(String url, String tok) async {
    final p = await SharedPreferences.getInstance();
    baseUrl = url.trim();
    token = tok.trim();
    await p.setString('baseUrl', baseUrl);
    await p.setString('token', token);
    notifyListeners();
  }

  Future<void> toggleTheme() async {
    final p = await SharedPreferences.getInstance();
    dark = !dark;
    await p.setBool('dark', dark);
    notifyListeners();
  }

  Future<void> setBiometric(bool v) async {
    final p = await SharedPreferences.getInstance();
    biometric = v;
    await p.setBool('biometric', v);
    notifyListeners();
  }

  bool get configured => baseUrl.isNotEmpty && token.isNotEmpty;
}

final settings = Settings();

// ----------------- API-клієнт -----------------
class Api {
  static Uri _u(String action, Map<String, String> q) {
    var base = settings.baseUrl;
    if (!base.startsWith('http')) base = 'https://$base';
    base = base.replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$base/api.php')
        .replace(queryParameters: {'action': action, ...q});
  }

  static Map<String, String> get _headers => {'X-Api-Token': settings.token};

  static Future<dynamic> get(String action, [Map<String, String> q = const {}]) async {
    final r = await http.get(_u(action, q), headers: _headers)
        .timeout(const Duration(seconds: 20));
    if (r.statusCode != 200) {
      throw 'HTTP ${r.statusCode}: ${r.body}';
    }
    return jsonDecode(r.body);
  }

  static Future<void> deleteTrade(int id) async {
    final base = settings.baseUrl.startsWith('http')
        ? settings.baseUrl
        : 'https://${settings.baseUrl}';
    final uri = Uri.parse('${base.replaceAll(RegExp(r'/+$'), '')}/api.php?action=delete');
    final r = await http.post(uri, headers: _headers, body: {'id': '$id'});
    if (r.statusCode != 200) throw 'HTTP ${r.statusCode}';
  }
}

// ----------------- Хелпери -----------------
double asD(dynamic v) =>
    v == null ? 0 : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0);
String money(num v) {
  final s = v.abs().toStringAsFixed(2);
  final parts = s.split('.');
  final intp = parts[0].replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');
  return '${v < 0 ? '-' : ''}\$$intp.${parts[1]}';
}
Color pnlColor(num v) => v > 0 ? pos : (v < 0 ? neg : Colors.grey);

// ----------------- main -----------------
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await settings.load();
  runApp(const WheelApp());
}

class WheelApp extends StatelessWidget {
  const WheelApp({super.key});
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: settings,
      builder: (_, __) => MaterialApp(
        title: 'Wheel Analytics',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(settings.dark),
        home: !settings.configured
            ? const SettingsPage(first: true)
            : (settings.biometric ? const LockScreen() : const HomePage()),
      ),
    );
  }
}

// ----------------- Екран блокування (відбиток) -----------------
class LockScreen extends StatefulWidget {
  const LockScreen({super.key});
  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  String? _err;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _auth());
  }

  Future<void> _auth() async {
    if (_busy) return;
    setState(() { _busy = true; _err = null; });
    try {
      final auth = LocalAuthentication();
      final can = await auth.isDeviceSupported();
      if (!can) { _go(); return; } // пристрій без біометрії — пропускаємо
      final ok = await auth.authenticate(
        localizedReason: 'Вхід у Wheel Analytics',
        options: const AuthenticationOptions(stickyAuth: true, biometricOnly: false),
      );
      if (ok) { _go(); return; }
      setState(() { _busy = false; _err = 'Не підтверджено'; });
    } catch (e) {
      setState(() { _busy = false; _err = '$e'; });
    }
  }

  void _go() {
    if (!mounted) return;
    Navigator.pushReplacement(context,
        MaterialPageRoute(builder: (_) => const HomePage()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.fingerprint, size: 72, color: gold),
        const SizedBox(height: 16),
        const Text('Wheel Analytics', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(_err ?? 'Підтвердіть особу для входу',
            style: const TextStyle(color: Colors.grey)),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _busy ? null : _auth,
          icon: const Icon(Icons.fingerprint),
          label: const Text('Розблокувати'),
        ),
      ])),
    );
  }
}

// ----------------- Головна з нижньою навігацією -----------------
class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _i = 0;
  final _pc = PageController();
  final _pages = const [OverviewPage(), DashboardPage(), CalendarPage(), MonthlyPage()];
  final _titles = ['Огляд', 'Тиждень', 'Календар', 'Місяці'];

  @override
  void dispose() { _pc.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_i]),
        actions: [
          IconButton(
            icon: Icon(settings.dark ? Icons.light_mode : Icons.dark_mode),
            onPressed: () => settings.toggleTheme(),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const SettingsPage())),
          ),
        ],
      ),
      body: PageView(
        controller: _pc,
        onPageChanged: (v) => setState(() => _i = v),
        children: _pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _i,
        onDestinationSelected: (v) {
          setState(() => _i = v);
          _pc.animateToPage(v,
              duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard), label: 'Огляд'),
          NavigationDestination(icon: Icon(Icons.calendar_view_week), label: 'Тиждень'),
          NavigationDestination(icon: Icon(Icons.calendar_month), label: 'Календар'),
          NavigationDestination(icon: Icon(Icons.bar_chart), label: 'Місяці'),
        ],
      ),
    );
  }
}

// ----------------- Екран «Огляд» -----------------
class OverviewPage extends StatefulWidget {
  const OverviewPage({super.key});
  @override
  State<OverviewPage> createState() => _OverviewPageState();
}

class _OverviewPageState extends State<OverviewPage> {
  Map<String, dynamic>? _dash;
  Map<String, dynamic>? _pos;
  Map<String, dynamic>? _pace;
  List _years = [];
  bool _loading = true;
  String? _err;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final dash = await Api.get('dashboard');
      final pos = await Api.get('positions');
      final yr = await Api.get('yearly');
      final pace = await Api.get('pace');
      setState(() {
        _dash = dash as Map<String, dynamic>;
        _pos = pos as Map<String, dynamic>;
        _years = yr as List;
        _pace = pace as Map<String, dynamic>;
        _loading = false; _err = null;
      });
    } catch (e) { setState(() { _err = '$e'; _loading = false; }); }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_err != null) return _ErrorView(_err!, _load);
    final series = (_dash!['series'] as List);
    final cumR = series.isNotEmpty ? asD(series.last['cum_realized']) : 0.0;
    final cumT = series.isNotEmpty ? asD(series.last['cum_target']) : 0.0;
    final prog = cumT != 0 ? (cumR / cumT).clamp(0.0, 1.0) : 0.0;
    final atRisk = _pos!['at_risk'] as Map<String, dynamic>;
    final positions = _pos!['positions'] as List;

    // найкращий / найгірший тиждень
    Map<String, dynamic>? best, worst;
    for (final w in series) {
      if (asD(w['realized']) == 0) continue;
      if (best == null || asD(w['realized']) > asD(best['realized'])) best = w;
      if (worst == null || asD(w['realized']) < asD(worst['realized'])) worst = w;
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
        // Капітал під ризиком
        Card(child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.lock_outline, size: 18, color: gold),
              const SizedBox(width: 6),
              const Text('Капітал під ризиком', style: TextStyle(color: Colors.grey)),
            ]),
            const SizedBox(height: 6),
            Row(crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic, children: [
              Text(money(asD(atRisk['risk'])),
                  style: headFont(size: 32, w: FontWeight.w700, c: gold)),
              const SizedBox(width: 10),
              if (asD(atRisk['pct']) > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: gold.withOpacity(.16),
                      borderRadius: BorderRadius.circular(8)),
                  child: Text('${asD(atRisk['pct']).toStringAsFixed(1)}%',
                      style: monoFont(size: 14, w: FontWeight.w700, c: gold)),
                ),
            ]),
            const SizedBox(height: 2),
            Text('${atRisk['count']} проданих путів · ${asD(atRisk['pct']).toStringAsFixed(1)}% від капіталу ${money(asD(atRisk['capital']))}',
                style: const TextStyle(color: Colors.grey, fontSize: 12)),
          ]),
        )),
        // Кнопки: Колесо / Експірації
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            Expanded(child: OutlinedButton.icon(
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const WheelPage())),
              icon: const Icon(Icons.donut_large, size: 18),
              label: const Text('Колесо'))),
            const SizedBox(width: 10),
            Expanded(child: OutlinedButton.icon(
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const ExpirationsPage())),
              icon: const Icon(Icons.event, size: 18),
              label: const Text('Експірації'))),
          ]),
        ),
        // Темп до річної цілі
        if (_pace != null) _paceCard(),
        // Накопичено vs ціль
        Card(child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Накопичено vs ціль', style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 6),
            Text(money(cumR), style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: pnlColor(cumR))),
            const SizedBox(height: 10),
            LinearProgressIndicator(value: prog, minHeight: 10,
                backgroundColor: Colors.grey.withOpacity(.2), color: pos,
                borderRadius: BorderRadius.circular(6)),
            const SizedBox(height: 8),
            Text('Ціль накопичена: ${money(cumT)} · ${(prog * 100).toStringAsFixed(0)}%',
                style: const TextStyle(color: Colors.grey, fontSize: 12)),
          ]),
        )),
        // Графік накопичення: факт vs ціль
        if (series.length > 1)
          _ChartCard(title: 'Накопичення: факт vs ціль', child: _cumChart(series)),
        // Найкращий / найгірший тиждень
        if (best != null && worst != null)
          Card(child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(children: [
              Expanded(child: _miniStat('Найкращий тиждень',
                  '${best['label']}', asD(best['realized']))),
              Container(width: 1, height: 40, color: Colors.grey.withOpacity(.2)),
              Expanded(child: _miniStat('Найгірший тиждень',
                  '${worst['label']}', asD(worst['realized']))),
            ]),
          )),
        // По роках
        if (_years.isNotEmpty)
          Card(child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Підсумок по роках', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              ..._years.map((y) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('${y['yr']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(money(asD(y['realized_total'])),
                      style: TextStyle(color: pnlColor(asD(y['realized_total'])),
                          fontWeight: FontWeight.w700, fontFamily: 'monospace')),
                ]),
              )),
            ]),
          )),
        // Відкриті позиції (короткий список)
        Card(child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Відкриті позиції (${positions.length})', style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            if (positions.isEmpty)
              const Text('Немає або не додано секцію Open Positions у Flex',
                  style: TextStyle(color: Colors.grey, fontSize: 12))
            else
              ...positions.take(8).map((p) {
                final isOpt = p['asset_category'] == 'OPT';
                final type = isOpt ? (p['put_call'] == 'P' ? 'PUT' : 'CALL') : '${p['asset_category']}';
                final short = asD(p['quantity']) < 0;
                final roc = p['roc_annual'];
                return Padding(padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(children: [
                    Expanded(child: Text('${p['underlying']}  $type'
                        '${p['strike'] != null ? ' ${asD(p['strike']).toStringAsFixed(0)}' : ''}'
                        '${p['expiry'] != null ? '  ${p['expiry']}' : ''}',
                        style: const TextStyle(fontSize: 13))),
                    if (roc != null) Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(color: cPos(context).withOpacity(.14),
                          borderRadius: BorderRadius.circular(6)),
                      child: Text('${asD(roc).toStringAsFixed(0)}%/р',
                          style: monoFont(size: 11, w: FontWeight.w700, c: cPos(context))),
                    ),
                    Text('${short ? '' : '+'}${asD(p['quantity']).toStringAsFixed(0)}',
                        style: monoFont(size: 13, c: short ? cNeg(context) : cPos(context))),
                  ]),
                );
              }),
          ]),
        )),
      ]),
    );
  }

  Widget _paceCard() {
    final p = _pace!;
    final projPct = asD(p['pct_projected']);
    final realized = asD(p['realized']);
    final annual = asD(p['annual_target']);
    final proj = asD(p['projected_annual']);
    final curPct = asD(p['pct_current']);
    return Card(child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.speed, size: 18, color: gold),
          const SizedBox(width: 6),
          const Text('Темп до річної цілі', style: TextStyle(color: Colors.grey)),
        ]),
        const SizedBox(height: 8),
        Text('${projPct.toStringAsFixed(0)}%',
            style: headFont(size: 32, w: FontWeight.w700,
                c: projPct >= 100 ? cPos(context) : gold)),
        Text('річної цілі за поточним темпом', style: const TextStyle(color: Colors.grey, fontSize: 12)),
        const SizedBox(height: 6),
        Text(_motivation(projPct),
            style: TextStyle(fontSize: 13, color: cPos(context), fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        LinearProgressIndicator(value: (curPct / 100).clamp(0.0, 1.0), minHeight: 8,
            backgroundColor: Colors.grey.withOpacity(.2), color: cPos(context),
            borderRadius: BorderRadius.circular(6)),
        const SizedBox(height: 10),
        _paceRow('Зароблено (з ${p['days']} дн.)', money(realized)),
        _paceRow('Прогноз на рік', money(proj)),
        _paceRow('Річна ціль', money(annual)),
        _paceRow('Виконано від цілі', '${curPct.toStringAsFixed(1)}%'),
      ]),
    ));
  }

  Widget _paceRow(String l, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(l, style: const TextStyle(color: Colors.grey, fontSize: 13)),
      Text(v, style: monoFont(size: 13, w: FontWeight.w600,
          c: Theme.of(context).textTheme.bodyMedium?.color)),
    ]),
  );

  String _motivation(double projPct) {
    if (projPct >= 110) return '🚀 Ви випереджаєте річну ціль — чудова робота!';
    if (projPct >= 90)  return '💪 Майже точно в цілі, тримайте темп!';
    if (projPct >= 70)  return '📈 Гарний темп, ціль реальна — не зупиняйтесь.';
    if (projPct >= 40)  return '🌱 Стабільно рухаєтесь, що далі — то краще.';
    return '🎯 Початок покладено. Кожен тиждень наближає до цілі.';
  }

  Widget _cumChart(List series) {
    final cumR = <FlSpot>[];
    final cumT = <FlSpot>[];
    for (int i = 0; i < series.length; i++) {
      cumR.add(FlSpot(i.toDouble(), asD(series[i]['cum_realized'])));
      cumT.add(FlSpot(i.toDouble(), asD(series[i]['cum_target'])));
    }
    return LineChart(LineChartData(
      gridData: FlGridData(show: true, drawVerticalLine: false,
          getDrawingHorizontalLine: (v) => FlLine(color: Colors.grey.withOpacity(.15), strokeWidth: 1)),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      lineTouchData: LineTouchData(
        enabled: true,
        handleBuiltInTouches: true,
        getTouchedSpotIndicator: (bar, indexes) => indexes.map((i) => TouchedSpotIndicatorData(
          FlLine(color: Colors.grey.withOpacity(.4), strokeWidth: 1),
          FlDotData(show: true, getDotPainter: (s, p, b, idx) =>
              FlDotCirclePainter(radius: 4, color: bar.color ?? cPos(context),
                  strokeWidth: 2, strokeColor: Theme.of(context).cardColor)),
        )).toList(),
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (_) => _dk(context) ? const Color(0xFF243042) : const Color(0xFF2A3343),
          tooltipRoundedRadius: 8,
          getTooltipItems: (spots) => spots.map((s) {
            final i = s.x.toInt();
            final wk = i >= 0 && i < series.length ? '${series[i]['label']}' : '';
            final target = s.barIndex == 1;
            return LineTooltipItem(
              target ? 'Ціль ${money(s.y)}' : '$wk\nФакт ${money(s.y)}',
              TextStyle(color: target ? const Color(0xFFE9C46A) : const Color(0xFF6FE0B0),
                  fontSize: 11, fontWeight: FontWeight.w700),
            );
          }).toList(),
        ),
      ),
      lineBarsData: [
        LineChartBarData(spots: cumR, color: cPos(context), barWidth: 2.5,
            isCurved: true, dotData: FlDotData(show: false),
            belowBarData: BarAreaData(show: true, color: cPos(context).withOpacity(.10))),
        LineChartBarData(spots: cumT, color: gold, barWidth: 2, isCurved: true,
            dashArray: [5, 4], dotData: FlDotData(show: false)),
      ],
    ));
  }

  Widget _miniStat(String label, String wk, double val) => Column(children: [
    Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
    const SizedBox(height: 4),
    Text(money(val), style: TextStyle(color: pnlColor(val), fontWeight: FontWeight.bold, fontFamily: 'monospace')),
    Text(wk, style: const TextStyle(color: Colors.grey, fontSize: 11)),
  ]);
}

// ----------------- Екран «Колесо по тікерах» -----------------
class WheelPage extends StatefulWidget {
  const WheelPage({super.key});
  @override
  State<WheelPage> createState() => _WheelPageState();
}

class _WheelPageState extends State<WheelPage> {
  List _data = [];
  Map<String, dynamic> _periods = {'years': [], 'months': []};
  String _period = '';
  bool _loading = true;
  String? _err;
  final Set<String> _open = {};

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final d = await Api.get('wheel', _period.isEmpty ? {} : {'period': _period});
      setState(() {
        _data = (d['items'] as List?) ?? [];
        _periods = Map<String, dynamic>.from(d['periods'] ?? {'years': [], 'months': []});
        _loading = false; _err = null;
      });
    } catch (e) { setState(() { _err = '$e'; _loading = false; }); }
  }

  String _eventLabel(dynamic e) {
    final opt = e['asset_category'] == 'OPT';
    final pc = e['put_call'];
    final open = e['open_close'] == 'O';
    final realized = asD(e['realized_pnl']);
    if (opt && pc == 'P' && open) return 'Продано PUT ${asD(e['strike']).toStringAsFixed(0)}';
    if (opt && pc == 'C' && open) return 'Продано CALL ${asD(e['strike']).toStringAsFixed(0)}';
    if (opt && !open && realized != 0) return 'Закрито ${pc == 'P' ? 'PUT' : 'CALL'} ${asD(e['strike']).toStringAsFixed(0)}';
    if (!opt) return realized != 0 ? 'Акції (закрито)' : 'Акції';
    return 'Подія';
  }

  @override
  Widget build(BuildContext context) {
    final years = (_periods['years'] as List?) ?? [];
    final months = (_periods['months'] as List?) ?? [];
    return Scaffold(
      appBar: AppBar(title: const Text('Колесо по тікерах')),
      body: Column(children: [
        // фільтр періоду
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Row(children: [
            const Text('Період: ', style: TextStyle(color: Colors.grey)),
            const SizedBox(width: 6),
            Expanded(child: DropdownButton<String>(
              isExpanded: true,
              value: _period,
              items: [
                const DropdownMenuItem(value: '', child: Text('Весь час')),
                ...years.map((y) => DropdownMenuItem(value: '$y', child: Text('Рік $y'))),
                ...months.map((m) => DropdownMenuItem(value: '$m', child: Text('$m'))),
              ],
              onChanged: (v) { setState(() => _period = v ?? ''); _load(); },
            )),
          ]),
        ),
        Expanded(child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _err != null
                ? _ErrorView(_err!, _load)
                : _data.isEmpty
                    ? const Center(child: Text('За цей період даних немає'))
                    : ListView(padding: const EdgeInsets.all(12), children: [
                        for (final w in _data) _tickerCard(w),
                      ])),
      ]),
    );
  }

  Widget _tickerCard(dynamic w) {
    final u = '${w['underlying']}';
    final realized = asD(w['realized']);
    final premium = asD(w['premium_collected']);
    final shares = asD(w['shares']);
    final events = (w['events'] as List?) ?? [];
    final open = _open.contains(u);
    String status;
    if (shares > 0) status = 'Тримає ${shares.toStringAsFixed(0)} акцій';
    else if ((w['short_puts'] ?? 0) > 0) status = 'Відкриті путани';
    else if ((w['short_calls'] ?? 0) > 0) status = 'Відкриті коли';
    else status = 'Немає відкритих';
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: open ? gold.withOpacity(.55) : Colors.grey.withOpacity(_dk(context) ? .22 : .14),
          width: open ? 1.5 : 1,
        ),
      ),
      child: Column(children: [
      Material(
        color: open ? gold.withOpacity(_dk(context) ? .10 : .08) : Colors.transparent,
        borderRadius: BorderRadius.vertical(
          top: const Radius.circular(11),
          bottom: Radius.circular(open ? 0 : 11)),
        child: ListTile(
          onTap: () => setState(() => open ? _open.remove(u) : _open.add(u)),
          title: Text(u, style: headFont(size: 17, w: FontWeight.w700)),
          subtitle: Text('Премія ${money(premium)} · $status', style: const TextStyle(fontSize: 12)),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(money(realized), style: monoFont(size: 15, w: FontWeight.w700, c: cPnl(context, realized))),
            Icon(open ? Icons.expand_less : Icons.expand_more, color: open ? gold : Colors.grey),
          ]),
        ),
      ),
      if (open)
        Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Column(children: [
            const Divider(height: 1),
            const SizedBox(height: 6),
            for (final e in events)
              Padding(padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  SizedBox(width: 78, child: Text('${e['trade_date']}'.substring(5),
                      style: const TextStyle(fontSize: 12, color: Colors.grey))),
                  Expanded(child: Text(_eventLabel(e), style: const TextStyle(fontSize: 13))),
                  Text(asD(e['proceeds']) > 0
                      ? '+${money(asD(e['proceeds']))}'
                      : (asD(e['realized_pnl']) != 0 ? money(asD(e['realized_pnl'])) : ''),
                      style: monoFont(size: 12, w: FontWeight.w600,
                          c: asD(e['proceeds']) > 0 ? cBlue(context) : cPnl(context, asD(e['realized_pnl'])))),
                ]),
              ),
          ]),
        ),
    ]));
  }
}

// ----------------- Екран «Календар експірацій» -----------------
class ExpirationsPage extends StatefulWidget {
  const ExpirationsPage({super.key});
  @override
  State<ExpirationsPage> createState() => _ExpirationsPageState();
}

class _ExpirationsPageState extends State<ExpirationsPage> {
  List _data = [];
  bool _loading = true;
  String? _err;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final d = await Api.get('expirations');
      setState(() { _data = d as List; _loading = false; });
    } catch (e) { setState(() { _err = '$e'; _loading = false; }); }
  }

  @override
  Widget build(BuildContext context) {
    // групуємо за датою
    final byDate = <String, List>{};
    for (final e in _data) {
      (byDate['${e['expiry']}'] ??= []).add(e);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Календар експірацій')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _err != null
              ? _ErrorView(_err!, _load)
              : _data.isEmpty
                  ? const Center(child: Text('Немає відкритих опціонів'))
                  : ListView(padding: const EdgeInsets.all(12),
                      children: byDate.entries.map((en) => _dateGroup(en.key, en.value)).toList()),
    );
  }

  Widget _dateGroup(String date, List items) {
    final days = asD(items.first['days']).toInt();
    final soon = days <= 3;
    final fmt = () { final p = date.split('-'); return p.length == 3 ? '${p[2]}.${p[1]}.${p[0]}' : date; }();
    return Card(child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.event, size: 18, color: soon ? neg : gold),
          const SizedBox(width: 8),
          Text(fmt, style: headFont(size: 16, w: FontWeight.w700)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
                color: (soon ? neg : Colors.grey).withOpacity(.15),
                borderRadius: BorderRadius.circular(10)),
            child: Text(days <= 0 ? 'сьогодні' : 'за $days дн.',
                style: TextStyle(fontSize: 12, color: soon ? neg : Colors.grey, fontWeight: FontWeight.w600)),
          ),
        ]),
        const SizedBox(height: 8),
        for (final e in items)
          Padding(padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              Expanded(child: Text(
                  '${e['underlying']}  ${e['put_call'] == 'P' ? 'PUT' : 'CALL'} ${asD(e['strike']).toStringAsFixed(0)}',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500))),
              Text('${asD(e['quantity']).toStringAsFixed(0)} конт.',
                  style: monoFont(size: 12, c: Colors.grey)),
            ]),
          ),
      ]),
    ));
  }
}

// ----------------- Екран «Тиждень» -----------------
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  List<dynamic> _weeks = [];
  Map<String, dynamic>? _data;
  int? _y, _w;
  bool _loading = true;
  String? _err;
  bool _showStk = false;
  final Set<String> _expanded = {};

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      _weeks = await Api.get('weeks') as List;
      if (_weeks.isNotEmpty) {
        _y = _weeks.first['iso_year'];
        _w = _weeks.first['iso_week'];
      }
      await _loadWeek();
    } catch (e) {
      setState(() { _err = '$e'; _loading = false; });
    }
  }

  Future<void> _loadWeek() async {
    setState(() => _loading = true);
    try {
      final d = await Api.get('dashboard', {'y': '$_y', 'w': '$_w'});
      setState(() { _data = d as Map<String, dynamic>; _loading = false; _err = null; });
    } catch (e) {
      setState(() { _err = '$e'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_err != null) return _ErrorView(_err!, _init);
    final d = _data!;
    final s = d['summary'] as Map<String, dynamic>;
    final trades = (d['trades'] as List)
        .where((t) => _showStk ? t['asset_category'] != 'OPT' : t['asset_category'] == 'OPT')
        .toList();
    final optN = (d['trades'] as List).where((t) => t['asset_category'] == 'OPT').length;
    final stkN = (d['trades'] as List).where((t) => t['asset_category'] != 'OPT').length;
    final realized = asD(s['realized_total']);
    final target = asD(s['target']);
    final diff = realized - target;
    final progress = target != 0 ? (realized / target).clamp(0.0, 1.5) : 0.0;

    return RefreshIndicator(
      onRefresh: _loadWeek,
      child: ListView(
        children: [
          // вибір тижня
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: DropdownButtonFormField<String>(
              value: '$_y-$_w',
              decoration: const InputDecoration(labelText: 'Тиждень', border: OutlineInputBorder()),
              items: _weeks.map((wk) {
                final v = '${wk['iso_year']}-${wk['iso_week']}';
                final dates = '${_d(wk['start'])}–${_d(wk['end'])}';
                return DropdownMenuItem(value: v, child: Text('${wk['label']} · $dates'));
              }).toList(),
              onChanged: (v) {
                if (v == null) return;
                final p = v.split('-');
                _y = int.parse(p[0]); _w = int.parse(p[1]);
                _loadWeek();
              },
            ),
          ),
          // KPI
          Card(child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Премія по закритих опціонах', style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 4),
              Text(money(asD(s['premium_opt'])),
                  style: TextStyle(fontSize: 38, fontWeight: FontWeight.bold,
                      color: pnlColor(asD(s['premium_opt'])))),
              const SizedBox(height: 14),
              LinearProgressIndicator(
                value: progress.clamp(0.0, 1.0),
                minHeight: 10, backgroundColor: Colors.grey.withOpacity(.2),
                color: s['hit'] == true ? pos : gold,
                borderRadius: BorderRadius.circular(6),
              ),
              const SizedBox(height: 10),
              _row('Ціль тижня', money(target)),
              _row('Реалізовано всього', money(realized), c: pnlColor(realized)),
              _row(diff >= 0 ? 'Понад ціль' : 'Залишок до цілі', money(diff.abs()),
                  c: diff >= 0 ? pos : neg),
              _row('Прогрес', '${(progress * 100).toStringAsFixed(0)}%'),
            ]),
          )),
          // графік тижнів
          _ChartCard(title: 'Тижні: факт vs ціль',
              child: _weeklyChart(d['series'] as List)),
          // вкладки опц/акції
          Card(child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(children: [
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(value: false, label: Text('Опціони ($optN)')),
                  ButtonSegment(value: true, label: Text('Акції ($stkN)')),
                ],
                selected: {_showStk},
                onSelectionChanged: (v) => setState(() => _showStk = v.first),
              ),
              const SizedBox(height: 8),
              if (trades.isEmpty)
                const Padding(padding: EdgeInsets.all(16),
                    child: Text('Немає закритих угод', style: TextStyle(color: Colors.grey)))
              else
                ..._buildGroups(trades),
            ]),
          )),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // групування по тікеру+типу (PUT/CALL окремо), з розкриттям
  List<Widget> _buildGroups(List trades) {
    final map = <String, Map<String, dynamic>>{};
    for (final t in trades) {
      final isOpt = t['asset_category'] == 'OPT';
      final key = isOpt ? '${t['underlying']}|${t['put_call']}' : '${t['underlying']}|STK';
      map.putIfAbsent(key, () => {
        'key': key, 'underlying': t['underlying'], 'put_call': t['put_call'],
        'asset': t['asset_category'], 'pnl': 0.0, 'prem': 0.0, 'comm': 0.0,
        'items': <dynamic>[],
      });
      final g = map[key]!;
      g['pnl'] += asD(t['realized_pnl']);
      g['prem'] += asD(t['proceeds']);
      g['comm'] += asD(t['commission']);
      (g['items'] as List).add(t);
    }
    final out = <Widget>[];
    for (final g in map.values) {
      final items = g['items'] as List;
      if (items.length == 1) { out.add(_tradeTile(items[0])); continue; }
      final type = g['asset'] == 'OPT' ? (g['put_call'] == 'P' ? 'PUT' : 'CALL') : '${g['asset']}';
      final pnl = g['pnl'] as double;
      final open = _expanded.contains(g['key']);
      out.add(Column(children: [
        ListTile(
          dense: true,
          onTap: () => setState(() => open ? _expanded.remove(g['key']) : _expanded.add(g['key'])),
          title: Row(children: [
            Text('${g['underlying']}  $type', style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
              decoration: BoxDecoration(color: gold.withOpacity(.18), borderRadius: BorderRadius.circular(10)),
              child: Text('×${items.length}', style: const TextStyle(fontSize: 12, color: gold, fontWeight: FontWeight.w600)),
            ),
          ]),
          subtitle: Text('Премія ${money(g['prem'])} · Комісія ${money(g['comm'])}',
              style: const TextStyle(fontSize: 12)),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(money(pnl), style: TextStyle(color: pnlColor(pnl),
                fontWeight: FontWeight.w700, fontFamily: 'monospace')),
            Icon(open ? Icons.expand_less : Icons.expand_more, color: Colors.grey),
          ]),
        ),
        if (open) ...items.map((t) => _detailTile(t)),
        const Divider(height: 1),
      ]));
    }
    return out;
  }

  Widget _detailTile(dynamic t) {
    final pnl = asD(t['realized_pnl']);
    return Container(
      color: Colors.grey.withOpacity(.06),
      padding: const EdgeInsets.only(left: 24, right: 4),
      child: ListTile(
        dense: true,
        visualDensity: const VisualDensity(vertical: -3),
        title: Text('${t['trade_date']}'
            '${t['strike'] != null ? '  •  strike ${asD(t['strike']).toStringAsFixed(2)}' : ''}',
            style: const TextStyle(fontSize: 13)),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(money(pnl), style: TextStyle(color: pnlColor(pnl), fontFamily: 'monospace', fontSize: 13)),
          IconButton(icon: const Icon(Icons.close, size: 17),
              onPressed: () => _confirmDelete(t['id'])),
        ]),
      ),
    );
  }

  Widget _tradeTile(dynamic t) {
    final pnl = asD(t['realized_pnl']);
    final type = t['asset_category'] == 'OPT'
        ? (t['put_call'] == 'P' ? 'PUT' : 'CALL') : '${t['asset_category']}';
    return ListTile(
      dense: true,
      title: Text('${t['underlying']}  $type',
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text('${t['trade_date']}'
          '${t['strike'] != null ? '  •  strike ${asD(t['strike']).toStringAsFixed(2)}' : ''}'),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(money(pnl), style: TextStyle(color: pnlColor(pnl),
            fontWeight: FontWeight.w600, fontFamily: 'monospace')),
        IconButton(
          icon: const Icon(Icons.close, size: 18),
          onPressed: () => _confirmDelete(t['id']),
        ),
      ]),
    );
  }

  Future<void> _confirmDelete(dynamic id) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      title: const Text('Видалити угоду?'),
      content: const Text('Угода буде виключена з аналітики. Результати перерахуються.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Скасувати')),
        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Видалити')),
      ],
    ));
    if (ok == true) {
      await Api.deleteTrade(id is int ? id : int.parse('$id'));
      _loadWeek();
    }
  }

  Widget _weeklyChart(List series) {
    final reals = series.map((e) => asD(e['realized'])).toList();
    return BarChart(BarChartData(
      gridData: FlGridData(show: true, drawVerticalLine: false),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      barGroups: [
        for (int i = 0; i < reals.length; i++)
          BarChartGroupData(x: i, barRods: [
            BarChartRodData(toY: reals[i], color: reals[i] >= 0 ? pos : neg, width: 7,
                borderRadius: BorderRadius.circular(2)),
          ]),
      ],
    ));
  }

  Widget _row(String l, String v, {Color? c}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(l, style: const TextStyle(color: Colors.grey)),
      Text(v, style: TextStyle(fontWeight: FontWeight.w600, color: c, fontFamily: 'monospace')),
    ]),
  );

  String _d(dynamic iso) {
    final p = '$iso'.split('-');
    return p.length == 3 ? '${p[2]}.${p[1]}' : '$iso';
  }
}

// ----------------- Екран «Календар» -----------------
class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});
  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  Map<String, dynamic> _days = {};
  bool _loading = true;
  String? _err;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final ym = '${_month.year}-${_month.month.toString().padLeft(2, '0')}';
      final d = await Api.get('calendar', {'ym': ym});
      final raw = d['days'];
      setState(() {
        _days = raw is Map ? Map<String, dynamic>.from(raw) : {};
        _loading = false; _err = null;
      });
    } catch (e) {
      setState(() { _err = '$e'; _loading = false; });
    }
  }

  void _shift(int m) {
    _month = DateTime(_month.year, _month.month + m);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_err != null) return _ErrorView(_err!, _load);
    const names = ['Січень','Лютий','Березень','Квітень','Травень','Червень',
      'Липень','Серпень','Вересень','Жовтень','Листопад','Грудень'];
    final first = DateTime(_month.year, _month.month, 1);
    final daysIn = DateTime(_month.year, _month.month + 1, 0).day;
    double sumPrem = 0, sumReal = 0;
    _days.forEach((k, v) { sumPrem += asD(v['premium_sold']); sumReal += asD(v['realized']); });
    final dark = Theme.of(context).brightness == Brightness.dark;

    // комірки днів (без днів тижня — вони в окремому рядку)
    final cells = <Widget>[];
    // лише Пн–Пт: відступ до колонки першого буднього дня місяця
    final leadCol = (first.weekday >= 1 && first.weekday <= 5) ? first.weekday - 1 : 0;
    for (int i = 0; i < leadCol; i++) cells.add(const SizedBox());
    for (int day = 1; day <= daysIn; day++) {
      final wd = DateTime(_month.year, _month.month, day).weekday;
      if (wd == 6 || wd == 7) continue; // субота/неділя — без них (торгів немає)
      final key = '${_month.year}-${_month.month.toString().padLeft(2,'0')}-${day.toString().padLeft(2,'0')}';
      final v = _days[key];
      final prem = v != null ? asD(v['premium_sold']) : 0.0;
      final real = v != null ? asD(v['realized']) : 0.0;
      final hasData = prem > 0 || real != 0;
      cells.add(InkWell(
        onTap: hasData
            ? () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => DayDetailPage(date: key)))
            : null,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          decoration: BoxDecoration(
            color: prem > 0
                ? cBlue(context).withOpacity(dark ? .16 : .12)
                : (dark ? Colors.white.withOpacity(.03) : Colors.black.withOpacity(.02)),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: prem > 0 ? cBlue(context).withOpacity(.40) : Colors.grey.withOpacity(.18),
              width: prem > 0 ? 1 : .5,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Text('$day', textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 18,
                      color: hasData ? Theme.of(context).textTheme.bodyMedium?.color : Colors.grey,
                      fontWeight: hasData ? FontWeight.w700 : FontWeight.w400)),
              if (prem > 0)
                FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
                  child: Text(money(prem), maxLines: 1,
                      style: monoFont(size: 16, w: FontWeight.w700, c: cBlue(context)))),
              if (real != 0)
                FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
                  child: Text('${real > 0 ? '+' : ''}${money(real)}', maxLines: 1,
                      style: monoFont(size: 15, w: FontWeight.w600, c: cPnl(context, real)))),
            ],
          ),
        ),
      ));
    }

    return Column(children: [
      // навігація по місяцях
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 10, 8, 4),
        child: Row(children: [
          IconButton(onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left)),
          Expanded(child: Text('${names[_month.month - 1]} ${_month.year}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold))),
          IconButton(onPressed: () => _shift(1), icon: const Icon(Icons.chevron_right)),
        ]),
      ),
      Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
        _badge('Премія ${money(sumPrem)}', blue),
        _badge('Реаліз. ${sumReal >= 0 ? '+' : ''}${money(sumReal)}', pos),
      ]),
      const SizedBox(height: 14),
      // рядок днів тижня
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(children: [
          for (final d in ['Пн','Вт','Ср','Чт','Пт'])
            Expanded(child: Center(child: Text(d,
                style: const TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.w600)))),
        ]),
      ),
      const SizedBox(height: 6),
      // сітка днів — заповнює весь доступний простір
      Expanded(child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        child: LayoutBuilder(builder: (ctx, c) {
          final rows = (cells.length / 5).ceil().clamp(1, 6);
          const sp = 6.0;
          final cw = (c.maxWidth - sp * 4) / 5;
          final ch = (c.maxHeight - sp * (rows - 1)) / rows;
          final ratio = (ch > 0 && cw > 0) ? cw / ch : 0.8;
          return GridView.count(
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 5, crossAxisSpacing: sp, mainAxisSpacing: sp,
            childAspectRatio: ratio,
            children: cells,
          );
        }),
      )),
    ]);
  }

  Widget _badge(String t, Color c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
    decoration: BoxDecoration(color: c.withOpacity(.15), borderRadius: BorderRadius.circular(20)),
    child: Text(t, style: TextStyle(color: c, fontWeight: FontWeight.w600)),
  );
}

// ----------------- Екран деталей дня -----------------
class DayDetailPage extends StatefulWidget {
  final String date;
  const DayDetailPage({super.key, required this.date});
  @override
  State<DayDetailPage> createState() => _DayDetailPageState();
}

class _DayDetailPageState extends State<DayDetailPage> {
  Map<String, dynamic>? _d;
  bool _loading = true;
  String? _err;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final d = await Api.get('day', {'date': widget.date});
      setState(() { _d = d as Map<String, dynamic>; _loading = false; });
    } catch (e) { setState(() { _err = '$e'; _loading = false; }); }
  }

  String _fmtDate(String iso) {
    final p = iso.split('-');
    return p.length == 3 ? '${p[2]}.${p[1]}.${p[0]}' : iso;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('День ${_fmtDate(widget.date)}')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _err != null
              ? _ErrorView(_err!, _load)
              : _body(),
    );
  }

  Widget _body() {
    final opened = _d!['opened'] as List;
    final closed = _d!['closed'] as List;
    final premium = asD(_d!['premium']);
    final realized = asD(_d!['realized']);
    if (opened.isEmpty && closed.isEmpty) {
      return const Center(child: Text('За цей день немає угод', style: TextStyle(color: Colors.grey)));
    }
    return ListView(padding: const EdgeInsets.all(12), children: [
      Row(children: [
        Expanded(child: _sumCard('Продана премія', premium, cBlue(context))),
        const SizedBox(width: 10),
        Expanded(child: _sumCard('Реалізований P/L', realized, cPnl(context, realized))),
      ]),
      if (opened.isNotEmpty) ...[
        _sectionTitle('Продані опціони (премія)'),
        ...opened.map((t) => _row(t, isOpen: true)),
      ],
      if (closed.isNotEmpty) ...[
        _sectionTitle('Закриті угоди (P/L)'),
        ...closed.map((t) => _row(t, isOpen: false)),
      ],
    ]);
  }

  Widget _sumCard(String label, double val, Color c) => Card(child: Padding(
    padding: const EdgeInsets.all(14),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
      const SizedBox(height: 4),
      Text('${val > 0 && !label.contains('премія') ? '+' : ''}${money(val)}',
          style: monoFont(size: 20, w: FontWeight.w700, c: c)),
    ]),
  ));

  Widget _sectionTitle(String t) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
    child: Text(t, style: headFont(size: 15, w: FontWeight.w600, c: Colors.grey)),
  );

  Widget _row(dynamic t, {required bool isOpen}) {
    final isOpt = t['asset_category'] == 'OPT';
    final type = isOpt ? (t['put_call'] == 'P' ? 'PUT' : 'CALL') : '${t['asset_category']}';
    final val = isOpen ? asD(t['proceeds']) : asD(t['realized_pnl']);
    final c = isOpen ? cBlue(context) : cPnl(context, val);
    return Card(child: ListTile(
      dense: true,
      title: Text('${t['underlying']}  $type', style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        '${t['strike'] != null ? 'strike ${asD(t['strike']).toStringAsFixed(2)}' : ''}'
        '${t['expiry'] != null ? '  •  ${t['expiry']}' : ''}'
        '  •  к-сть ${asD(t['quantity']).toStringAsFixed(0)}',
        style: const TextStyle(fontSize: 12)),
      trailing: Text('${val > 0 && !isOpen ? '+' : ''}${money(val)}',
          style: monoFont(size: 14, w: FontWeight.w700, c: c)),
    ));
  }
}

// ----------------- Екран «Місяці» -----------------
class MonthlyPage extends StatefulWidget {
  const MonthlyPage({super.key});
  @override
  State<MonthlyPage> createState() => _MonthlyPageState();
}

class _MonthlyPageState extends State<MonthlyPage> {
  List _months = [];
  List _years = [];
  bool _yearly = false;
  bool _loading = true;
  String? _err;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final m = await Api.get('monthly');
      final y = await Api.get('yearly');
      setState(() { _months = m as List; _years = y as List; _loading = false; _err = null; });
    } catch (e) { setState(() { _err = '$e'; _loading = false; }); }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_err != null) return _ErrorView(_err!, _load);
    final data = _yearly ? _years : _months;
    if (data.isEmpty) return const Center(child: Text('Даних поки немає'));
    final labelKey = _yearly ? 'yr' : 'ym';
    final totals = data.map((m) => asD(m['realized_total'])).toList();
    final maxAbs = totals.fold<double>(1, (p, e) => e.abs() > p ? e.abs() : p);

    return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
      // перемикач Місяць/Рік
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        child: Center(
          child: SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Місяць')),
              ButtonSegment(value: true, label: Text('Рік')),
            ],
            selected: {_yearly},
            onSelectionChanged: (v) => setState(() => _yearly = v.first),
          ),
        ),
      ),
      _ChartCard(
        title: _yearly ? 'Премія по роках' : 'Премія по місяцях',
        child: BarChart(BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxAbs * 1.25,
          minY: totals.any((e) => e < 0) ? -maxAbs * 1.25 : 0,
          gridData: FlGridData(show: true, drawVerticalLine: false,
              getDrawingHorizontalLine: (v) => FlLine(
                  color: Colors.grey.withOpacity(.15), strokeWidth: 1)),
          borderData: FlBorderData(show: false),
          barTouchData: BarTouchData(
            enabled: false,
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => Colors.transparent,
              tooltipPadding: EdgeInsets.zero,
              tooltipMargin: 2,
              getTooltipItem: (group, gi, rod, ri) => BarTooltipItem(
                _short(rod.toY),
                TextStyle(fontSize: 10, color: pnlColor(rod.toY), fontWeight: FontWeight.w700),
              ),
            ),
          ),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 24,
              getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i < 0 || i >= data.length) return const SizedBox();
                final lab = '${data[i][labelKey]}';
                return Padding(padding: const EdgeInsets.only(top: 6),
                    child: Text(_yearly ? lab : lab.substring(5),
                        style: const TextStyle(fontSize: 10, color: Colors.grey)));
              }))),
          barGroups: [
            for (int i = 0; i < totals.length; i++)
              BarChartGroupData(x: i, showingTooltipIndicators: const [0], barRods: [
                BarChartRodData(toY: totals[i], color: totals[i] >= 0 ? pos : neg,
                    width: _yearly ? 38 : 18,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(5))),
              ]),
          ],
        )),
      ),
      ...data.map((m) => Card(child: ListTile(
        title: Text('${m[labelKey]}', style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('Опціони ${money(asD(m['premium_opt']))} · Акції ${money(asD(m['realized_stk']))}'),
        trailing: Text(money(asD(m['realized_total'])),
            style: TextStyle(color: pnlColor(asD(m['realized_total'])),
                fontWeight: FontWeight.bold, fontFamily: 'monospace')),
      ))),
    ]);
  }

  // короткий підпис суми над стовпцем: $1.2k / $530
  String _short(double v) {
    final a = v.abs();
    final s = a >= 1000 ? '\$${(a / 1000).toStringAsFixed(1)}k' : '\$${a.toStringAsFixed(0)}';
    return '${v < 0 ? '-' : ''}$s';
  }
}

// ----------------- Спільні віджети -----------------
class _ChartCard extends StatelessWidget {
  final String title;
  final Widget child;
  const _ChartCard({required this.title, required this.child});
  @override
  Widget build(BuildContext context) => Card(child: Padding(
    padding: const EdgeInsets.all(16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 16),
      SizedBox(height: 160, child: child),
    ]),
  ));
}

class _ErrorView extends StatelessWidget {
  final String err;
  final Future<void> Function() retry;
  const _ErrorView(this.err, this.retry);
  @override
  Widget build(BuildContext context) => Center(child: Padding(
    padding: const EdgeInsets.all(24),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.cloud_off, size: 40, color: Colors.grey),
      const SizedBox(height: 12),
      Text('Помилка зʼєднання', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 6),
      Text(err, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey, fontSize: 12)),
      const SizedBox(height: 16),
      FilledButton(onPressed: () => retry(), child: const Text('Повторити')),
    ]),
  ));
}

// ----------------- Налаштування -----------------
class SettingsPage extends StatefulWidget {
  final bool first;
  const SettingsPage({super.key, this.first = false});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final _url = TextEditingController(text: settings.baseUrl);
  late final _tok = TextEditingController(text: settings.token);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Налаштування')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (widget.first)
          const Padding(padding: EdgeInsets.only(bottom: 16),
              child: Text('Вкажіть адресу сайту й API-токен, щоб застосунок підтягнув ваші дані.')),
        TextField(controller: _url, decoration: const InputDecoration(
          labelText: 'Адреса сайту',
          hintText: 'analitika.zakazat-kursovik.com',
          border: OutlineInputBorder())),
        const SizedBox(height: 14),
        TextField(controller: _tok, decoration: const InputDecoration(
          labelText: 'API-токен',
          border: OutlineInputBorder())),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () async {
            await settings.save(_url.text, _tok.text);
            if (!mounted) return;
            Navigator.pushAndRemoveUntil(context,
                MaterialPageRoute(builder: (_) => const HomePage()), (_) => false);
          },
          child: const Text('Зберегти'),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Вхід за відбитком пальця'),
          subtitle: const Text('Запитувати біометрію при відкритті'),
          value: settings.biometric,
          onChanged: (v) async {
            if (v) {
              try {
                final auth = LocalAuthentication();
                final ok = await auth.authenticate(
                  localizedReason: 'Підтвердіть, щоб увімкнути вхід за відбитком',
                  options: const AuthenticationOptions(stickyAuth: true, biometricOnly: false),
                );
                if (!ok) return;
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Біометрія недоступна: $e')));
                }
                return;
              }
            }
            await settings.setBiometric(v);
            setState(() {});
          },
        ),
        TextButton.icon(
          onPressed: () => settings.toggleTheme(),
          icon: Icon(settings.dark ? Icons.light_mode : Icons.dark_mode),
          label: Text(settings.dark ? 'Світла тема' : 'Темна тема'),
        ),
      ]),
    );
  }
}
