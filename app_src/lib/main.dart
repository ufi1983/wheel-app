import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:local_auth/local_auth.dart';

// ----------------- Кольори / тема -----------------
const gold = Color(0xFFD8A657);
const pos = Color(0xFF3FBF8F);
const neg = Color(0xFFE0796B);
const blue = Color(0xFF7AA2E8);

ThemeData buildTheme(bool dark) {
  final bg = dark ? const Color(0xFF0E141B) : const Color(0xFFF3F5F8);
  final surface = dark ? const Color(0xFF161E29) : Colors.white;
  final txt = dark ? const Color(0xFFE6EDF3) : const Color(0xFF1A2433);
  return ThemeData(
    brightness: dark ? Brightness.dark : Brightness.light,
    scaffoldBackgroundColor: bg,
    cardColor: surface,
    colorScheme: (dark ? const ColorScheme.dark() : const ColorScheme.light())
        .copyWith(primary: gold, surface: surface),
    textTheme: Typography.material2021().black.apply(
        bodyColor: txt, displayColor: txt),
    useMaterial3: true,
  );
}

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
  final _pages = const [DashboardPage(), CalendarPage(), MonthlyPage()];
  final _titles = ['Тиждень', 'Календар', 'Місяці'];

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
      body: _pages[_i],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _i,
        onDestinationSelected: (v) => setState(() => _i = v),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.calendar_view_week), label: 'Тиждень'),
          NavigationDestination(icon: Icon(Icons.calendar_month), label: 'Календар'),
          NavigationDestination(icon: Icon(Icons.bar_chart), label: 'Місяці'),
        ],
      ),
    );
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
                ...trades.map((t) => _tradeTile(t)),
            ]),
          )),
          const SizedBox(height: 20),
        ],
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
      setState(() { _days = Map<String, dynamic>.from(d['days'] ?? {}); _loading = false; _err = null; });
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
    final firstDow = first.weekday % 7; // 0=Нд
    final daysIn = DateTime(_month.year, _month.month + 1, 0).day;
    double sumPrem = 0, sumReal = 0;
    _days.forEach((k, v) { sumPrem += asD(v['premium_sold']); sumReal += asD(v['realized']); });

    final cells = <Widget>[];
    for (var d in ['Нд','Пн','Вт','Ср','Чт','Пт','Сб']) {
      cells.add(Center(child: Text(d, style: const TextStyle(fontSize: 11, color: Colors.grey))));
    }
    for (int i = 0; i < firstDow; i++) cells.add(const SizedBox());
    for (int day = 1; day <= daysIn; day++) {
      final key = '${_month.year}-${_month.month.toString().padLeft(2,'0')}-${day.toString().padLeft(2,'0')}';
      final v = _days[key];
      final prem = v != null ? asD(v['premium_sold']) : 0.0;
      final real = v != null ? asD(v['realized']) : 0.0;
      cells.add(Container(
        decoration: BoxDecoration(
          color: prem > 0 ? blue.withOpacity(.12) : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: prem > 0 ? blue.withOpacity(.4) : Colors.grey.withOpacity(.2)),
        ),
        padding: const EdgeInsets.all(4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$day', style: const TextStyle(fontSize: 11, color: Colors.grey)),
          if (prem > 0)
            Text(money(prem), style: const TextStyle(fontSize: 11, color: blue, fontWeight: FontWeight.w600)),
          const Spacer(),
          Text(real != 0 ? '${real > 0 ? '+' : ''}${money(real)}' : '\$0',
              style: TextStyle(fontSize: 10, color: real != 0 ? pnlColor(real) : Colors.grey)),
        ]),
      ));
    }

    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          IconButton(onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left)),
          Expanded(child: Text('${names[_month.month - 1]} ${_month.year}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
          IconButton(onPressed: () => _shift(1), icon: const Icon(Icons.chevron_right)),
        ]),
      ),
      Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
        _badge('Премія ${money(sumPrem)}', blue),
        _badge('Реаліз. ${sumReal >= 0 ? '+' : ''}${money(sumReal)}', pos),
      ]),
      const SizedBox(height: 10),
      Expanded(child: Padding(
        padding: const EdgeInsets.all(10),
        child: GridView.count(
          crossAxisCount: 7, crossAxisSpacing: 5, mainAxisSpacing: 5, childAspectRatio: .72,
          children: cells,
        ),
      )),
    ]);
  }

  Widget _badge(String t, Color c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
    decoration: BoxDecoration(color: c.withOpacity(.15), borderRadius: BorderRadius.circular(20)),
    child: Text(t, style: TextStyle(color: c, fontWeight: FontWeight.w600)),
  );
}

// ----------------- Екран «Місяці» -----------------
class MonthlyPage extends StatefulWidget {
  const MonthlyPage({super.key});
  @override
  State<MonthlyPage> createState() => _MonthlyPageState();
}

class _MonthlyPageState extends State<MonthlyPage> {
  List _months = [];
  bool _loading = true;
  String? _err;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final d = await Api.get('monthly');
      setState(() { _months = d as List; _loading = false; });
    } catch (e) { setState(() { _err = '$e'; _loading = false; }); }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_err != null) return _ErrorView(_err!, _load);
    if (_months.isEmpty) return const Center(child: Text('Даних поки немає'));
    final totals = _months.map((m) => asD(m['realized_total'])).toList();
    return ListView(children: [
      _ChartCard(title: 'Премія по місяцях', child: BarChart(BarChartData(
        gridData: FlGridData(show: true, drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 26,
            getTitlesWidget: (v, _) {
              final i = v.toInt();
              if (i < 0 || i >= _months.length) return const SizedBox();
              return Text('${_months[i]['ym']}'.substring(5), style: const TextStyle(fontSize: 9));
            }))),
        barGroups: [
          for (int i = 0; i < totals.length; i++)
            BarChartGroupData(x: i, barRods: [
              BarChartRodData(toY: totals[i], color: totals[i] >= 0 ? pos : neg, width: 14,
                  borderRadius: BorderRadius.circular(3)),
            ]),
        ],
      ))),
      ..._months.map((m) => Card(child: ListTile(
        title: Text('${m['ym']}'),
        subtitle: Text('Опціони ${money(asD(m['premium_opt']))} · Акції ${money(asD(m['realized_stk']))}'),
        trailing: Text(money(asD(m['realized_total'])),
            style: TextStyle(color: pnlColor(asD(m['realized_total'])),
                fontWeight: FontWeight.bold, fontFamily: 'monospace')),
      ))),
      const SizedBox(height: 20),
    ]);
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
