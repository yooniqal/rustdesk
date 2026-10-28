import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../common.dart';
import '../../cuberemote_api.dart';
import '../../cuberemote_config.dart';
import '../../models/cube_device_directory.dart';
import '../../models/platform_model.dart';
import 'home_page.dart';

// CubeRemote 가맹점 목록 탭. 운영자가 접속코드로 로그인하면 콘솔 뷰어 API에서 목록을 받아
// 웹 콘솔과 동일한 순서(sortOrder)·지역 그룹으로 표시하고, [연결]을 누르면 그 기기의
// 접속 비밀번호를 콘솔에서 받아 접속한다(앱에 비밀번호 내장 없음 — cuberemote_api.dart).
// 편집/그룹/순서 변경은 웹 콘솔에서 하며, 상단 버튼으로 바로 열 수 있다.
// 시작할 때 콘솔의 배포본 versionCode 와 비교해 새 버전 배너를 띄운다.
//
// 2026-10-29: 상단 상태 요약(전체/온라인/점검/오프라인 = 필터), 정렬(콘솔 순서·이름·상태·최근 응답),
// 한 줄 카드(탭 = 연결, 길게 누르기 = 파일 전송·ID 복사·상세). 맨 위 "지원 요청" 칸은 콘솔 /s 의
// 일회성 지원 프로그램이 켜져 있는 PC — 탭하면 그 PC 가 보고한 일회용 비밀번호로 바로 접속한다.
class CubeDevicesPage extends StatefulWidget implements PageShape {
  CubeDevicesPage({Key? key}) : super(key: key);

  @override
  final title = '가맹점';

  @override
  final icon = const Icon(Icons.store_mall_directory);

  @override
  final appBarActions = <Widget>[];

  @override
  State<CubeDevicesPage> createState() => _CubeDevicesPageState();
}

class _CubeDevicesPageState extends State<CubeDevicesPage>
    with WidgetsBindingObserver {
  late final _directory = CubeDeviceDirectory(_fetch);
  List<CubeDevice> get _devices => _directory.devices;
  bool get _loading => _directory.loading;
  String? get _error => _directory.error;
  bool _foreground = true;

  // 로그인 폼
  bool _loggedIn = CubeViewerApi.loggedIn;
  final _codeController = TextEditingController();
  bool _loggingIn = false;
  String? _loginError;

  // 새 버전 배너: 콘솔 배포본이 내 versionCode 보다 높을 때만
  String? _newVersionLabel;
  bool _dismissedUpdate = false;

  // 비밀번호를 받는 동안 같은 카드를 두 번 누르지 않게
  String? _connecting;
  String _filter = 'all';
  String _query = '';
  final Set<String> _collapsed = {}; // 접힌 지역명
  static const _kSort = 'cube-device-sort';
  String _sort = bind.mainGetLocalOption(key: _kSort).isEmpty
      ? 'console'
      : bind.mainGetLocalOption(key: _kSort);
  List<CubeSupportRequest> _support = [];
  Timer? _timer;
  Timer? _supportTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _directory.addListener(_changed);
    if (_loggedIn) {
      _load();
      _checkVersion();
    }
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_loggedIn && _foreground && ModalRoute.of(context)?.isCurrent != false) _load();
    });
    // 지원 요청은 고객이 전화로 기다리는 중이라 더 자주 본다
    _supportTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (_loggedIn && _foreground && ModalRoute.of(context)?.isCurrent != false) _loadSupport();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _supportTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _directory.dispose();
    _codeController.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_loggedIn && _foreground && ModalRoute.of(context)?.isCurrent != false) _load();
  }

  Future<void> _load() async {
    unawaited(_loadSupport());
    await _directory.refresh();
  }

  // 부가 기능이라 실패해도 목록 오류로 띄우지 않고 이전 값을 둔다(토큰 만료는 목록 쪽이 처리).
  Future<void> _loadSupport() async {
    try {
      final rows = await CubeViewerApi.supportRequests();
      final list = rows
          .whereType<Map>()
          .map((r) => CubeSupportRequest(Map<String, dynamic>.from(r)))
          .where((r) => r.id.isNotEmpty)
          .toList();
      if (mounted) setState(() => _support = list);
    } catch (e) {
      debugPrint('support list: $e');
    }
  }

  void _setSort(String v) {
    setState(() => _sort = v);
    bind.mainSetLocalOption(key: _kSort, value: v);
  }

  Future<List<CubeDevice>> _fetch() async {
    try {
      final list = await CubeViewerApi.devices();
      return list.map((row) {
        if (row is! Map || (row['deviceId'] ?? '').toString().trim().isEmpty) {
          throw const FormatException('기기 정보 형식이 올바르지 않습니다');
        }
        return CubeDevice(Map<String, dynamic>.from(row));
      }).toList(growable: false);
    } on CubeAuthException catch (e) {
      // 콘솔에서 토큰을 끊었거나 만료 → 로그인 폼으로
      unawaited(_authLost(e.message));
      throw CubeDirectoryError(e.message);
    }
  }

  Future<void> _authLost(String message) async {
    await CubeViewerApi.logout();
    if (mounted) {
      setState(() {
        _loggedIn = false;
        _loginError = message;
      });
    }
  }

  Future<void> _checkVersion() async {
    final info = await CubeViewerApi.appVersion();
    final mine = await CubeViewerApi.ownVersionCode();
    if (!mounted || info == null || mine == null) return;
    final remote = info['versionCode'];
    final code = remote is int ? remote : int.tryParse('$remote');
    if (code != null && code > mine && info['androidAvailable'] == true) {
      setState(() => _newVersionLabel = (info['version'] ?? '$code').toString());
    }
  }

  Future<void> _login() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) return;
    setState(() { _loggingIn = true; _loginError = null; });
    try {
      await CubeViewerApi.login(code);
      _codeController.clear();
      if (mounted) setState(() { _loggedIn = true; _loggingIn = false; });
      _load();
      _checkVersion();
    } catch (e) {
      if (mounted) setState(() { _loggingIn = false; _loginError = '$e'; });
    }
  }

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('로그아웃'),
        content: const Text('이 기기에서 로그아웃할까요? 다시 쓰려면 접속코드를 입력해야 합니다.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('로그아웃')),
        ],
      ),
    );
    if (ok != true) return;
    await CubeViewerApi.logout();
    if (mounted) setState(() { _loggedIn = false; _loginError = null; });
  }

  // 접속 직전에 콘솔에서 비밀번호를 받아 접속한다. 가맹점 이름은 원격 화면 하단바·알림에 쓴다.
  Future<void> _connect(String id, String name, {bool isFileTransfer = false}) async {
    if (_connecting != null) return;
    setState(() => _connecting = id);
    try {
      final pw = await CubeViewerApi.credential(id);
      CubeViewerApi.peerNames[id] = name;
      if (!mounted) return;
      connect(context, id, password: pw, isFileTransfer: isFileTransfer);
    } on CubeAuthException catch (e) {
      await _authLost(e.message);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('접속 정보를 받지 못했습니다: $e')));
      }
    } finally {
      if (mounted) setState(() => _connecting = null);
    }
  }

  Future<void> _connectSupport(CubeSupportRequest r) async {
    if (_connecting != null) return;
    setState(() => _connecting = r.id);
    try {
      final pw = await CubeViewerApi.supportCredential(r.id);
      CubeViewerApi.peerNames[r.id] = '지원 · ${r.title}';
      if (!mounted) return;
      connect(context, r.id, password: pw);
    } on CubeAuthException catch (e) {
      await _authLost(e.message);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
      unawaited(_loadSupport());
    } finally {
      if (mounted) setState(() => _connecting = null);
    }
  }

  Future<void> _openUpdate() async {
    try {
      await launchUrl(CubeViewerApi.androidDownloadUri(),
          mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  Widget _loginView() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.store_mall_directory, size: 48),
              const SizedBox(height: 12),
              const Text('가맹점 원격 접속',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              const Text('관리자에게 받은 접속코드를 입력하세요.',
                  textAlign: TextAlign.center),
              const SizedBox(height: 18),
              TextField(
                controller: _codeController,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _login(),
                decoration: const InputDecoration(
                  labelText: '접속코드',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_loginError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(_loginError!,
                      style: const TextStyle(color: Colors.redAccent)),
                ),
              const SizedBox(height: 14),
              ElevatedButton(
                onPressed: _loggingIn ? null : _login,
                child: _loggingIn
                    ? const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('로그인'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _updateBanner() {
    return MaterialBanner(
      backgroundColor: Colors.amber.shade100,
      leading: const Icon(Icons.system_update),
      content: Text('새 버전 $_newVersionLabel 이(가) 있습니다. 설치하면 기존 앱 위에 덮어써집니다.'),
      actions: [
        TextButton(
            onPressed: () => setState(() => _dismissedUpdate = true),
            child: const Text('나중에')),
        ElevatedButton(onPressed: _openUpdate, child: const Text('설치')),
      ],
    );
  }

  Future<void> _openConsole() async {
    final uri = Uri.parse(CubeRemoteConfig.consoleUrl);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }


  static const _sorts = {
    'console': '콘솔 순서(지역별)',
    'name': '이름순',
    'state': '상태순',
    'recent': '최근 응답순',
  };

  static int _stateRank(CubeDevice d) => switch (d.state) {
        'ready' => 0,
        'attention' => 1,
        'unreported' => 2,
        _ => 3,
      };

  bool _passesFilter(CubeDevice d) => switch (_filter) {
        'online' => d.online,
        'attention' => d.state == 'attention',
        'offline' => !d.online,
        _ => true,
      };

  Color _stateColor(CubeDevice d) => _error != null
      ? Colors.orange
      : switch (d.state) {
          'ready' => Colors.green,
          'attention' => Colors.orange,
          'offline' => Colors.grey,
          _ => Colors.blueGrey,
        };

  static String _ago(DateTime? t) {
    if (t == null) return '기록 없음';
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return '방금';
    if (d.inHours < 1) return '${d.inMinutes}분 전';
    if (d.inDays < 1) return '${d.inHours}시간 전';
    return '${d.inDays}일 전';
  }

  @override
  Widget build(BuildContext context) {
    if (!_loggedIn) return Scaffold(body: _loginView());

    final q = _query.trim().toLowerCase();
    final rows = _devices.where((d) => d.matches(q) && _passesFilter(d)).toList();

    // 플랫한 위젯 리스트로 펼침(지원 요청 + 그룹 헤더 + 카드)
    final items = <Object>[];
    if (_support.isNotEmpty) {
      items.add(const _SupportHeader());
      items.addAll(_support);
    }
    if (_sort == 'console') {
      for (final g in groupCubeDevices(rows)) {
        items.add(g);
        if (!_collapsed.contains(g.key)) items.addAll(g.value);
      }
    } else {
      rows.sort((a, b) => switch (_sort) {
            'state' => _stateRank(a) != _stateRank(b)
                ? _stateRank(a) - _stateRank(b)
                : a.name.compareTo(b.name),
            'recent' => (b.lastSeen?.millisecondsSinceEpoch ?? 0)
                .compareTo(a.lastSeen?.millisecondsSinceEpoch ?? 0),
            _ => a.name.compareTo(b.name),
          });
      items.addAll(rows);
    }
    final hasDevices = items.any((i) => i is CubeDevice);

    return Scaffold(
      body: Column(
        children: [
          if (_newVersionLabel != null && !_dismissedUpdate) _updateBanner(),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 4, 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: '가맹점 이름/지역/ID 검색',
                      isDense: true,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: '정렬',
                  icon: const Icon(Icons.sort),
                  initialValue: _sort,
                  onSelected: _setSort,
                  itemBuilder: (_) => [
                    for (final e in _sorts.entries)
                      CheckedPopupMenuItem(
                          value: e.key,
                          checked: _sort == e.key,
                          child: Text(e.value)),
                  ],
                ),
                PopupMenuButton<String>(
                  tooltip: '더보기',
                  onSelected: (v) {
                    if (v == 'console') _openConsole();
                    if (v == 'logout') _logout();
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                        value: 'console',
                        child: ListTile(
                            leading: Icon(Icons.open_in_new),
                            title: Text('콘솔 열기(편집/순서/그룹)'))),
                    PopupMenuItem(
                        value: 'logout',
                        child: ListTile(
                            leading: const Icon(Icons.logout),
                            title: Text('${CubeViewerApi.operator} 로그아웃'))),
                  ],
                ),
              ],
            ),
          ),
          _summary(),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 2, 14, 2),
            child: Row(children: [
              Expanded(
                child: Text(
                    [
                      if (_directory.updatedAt != null)
                        '갱신 ${TimeOfDay.fromDateTime(_directory.updatedAt!).format(context)}',
                      '${rows.length}대 표시',
                      if (_sort != 'console') _sorts[_sort]!,
                    ].join(' · '),
                    style: Theme.of(context).textTheme.bodySmall),
              ),
              if (_loading)
                const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2)),
            ]),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Text(
                  '${_devices.isNotEmpty ? '이전 목록 표시 중 · ' : ''}$_error',
                  style: const TextStyle(color: Colors.redAccent)),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _loading && _devices.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.only(bottom: 24),
                      itemCount: items.length + (hasDevices ? 0 : 1),
                      itemBuilder: (context, index) {
                        if (index >= items.length) {
                          return const Padding(
                              padding: EdgeInsets.all(32),
                              child: Center(child: Text('표시할 가맹점이 없습니다.')));
                        }
                        final item = items[index];
                        if (item is CubeDevice) return _deviceTile(item);
                        if (item is CubeSupportRequest) return _supportTile(item);
                        if (item is _SupportHeader) return _supportHeader();
                        final group =
                            item as MapEntry<String, List<CubeDevice>>;
                        return _groupHeader(group.key, group.value.length,
                            _collapsed.contains(group.key));
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // 상태 요약 겸 필터. 숫자는 검색어와 상관없이 전체 기준.
  Widget _summary() {
    final online = _devices.where((d) => d.online).length;
    final attention = _devices.where((d) => d.state == 'attention').length;
    final tiles = [
      ('all', '전체', _devices.length, Theme.of(context).colorScheme.primary),
      ('online', '온라인', online, Colors.green),
      ('attention', '점검 필요', attention, Colors.orange),
      ('offline', '오프라인', _devices.length - online, Colors.grey),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 2),
      child: Row(children: [
        for (final (key, label, count, color) in tiles)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Material(
                color: _filter == key
                    ? color.withOpacity(0.16)
                    : Theme.of(context).cardColor,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(
                        color: _filter == key
                            ? color
                            : Colors.grey.withOpacity(0.3))),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => setState(() => _filter = key),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(children: [
                      Text('$count',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: count == 0 && key != 'all'
                                  ? Colors.grey
                                  : color)),
                      Text(label,
                          style: Theme.of(context).textTheme.bodySmall),
                    ]),
                  ),
                ),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _groupHeader(String region, int count, bool collapsed) {
    return InkWell(
      onTap: () => setState(() {
        if (collapsed) {
          _collapsed.remove(region);
        } else {
          _collapsed.add(region);
        }
      }),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
        child: Row(
          children: [
            Icon(collapsed ? Icons.chevron_right : Icons.expand_more, size: 20),
            const SizedBox(width: 4),
            Text(region, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(width: 6),
            Text('$count', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  Widget _deviceTile(CubeDevice d) {
    final color = _stateColor(d);
    final subtitle = [
      if (_sort != 'console') d.regionLabel,
      d.state == 'ready' ? '연결 가능' : d.statusDescription,
    ].join(' · ');
    return Card(
      key: ValueKey(d.id),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _connect(d.id, d.name),
        onLongPress: () => _deviceMenu(d),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
          child: Row(children: [
            Icon(Icons.circle, size: 10, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(d.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: d.state == 'ready' ? null : color)),
                  ]),
            ),
            if (_connecting == d.id)
              const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else
              IconButton(
                  tooltip: '메뉴',
                  icon: const Icon(Icons.more_vert),
                  onPressed: () => _deviceMenu(d)),
          ]),
        ),
      ),
    );
  }

  Future<void> _deviceMenu(CubeDevice d) async {
    final color = _stateColor(d);
    Widget info(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
                width: 72,
                child: Text(label,
                    style: Theme.of(context).textTheme.bodySmall)),
            Expanded(child: Text(value)),
          ]),
        );
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(d.name,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Row(children: [
                Icon(Icons.circle, size: 10, color: color),
                const SizedBox(width: 6),
                Text(d.statusLabel, style: TextStyle(color: color)),
              ]),
              const SizedBox(height: 10),
              info('ID', d.id),
              info('지역', d.regionLabel),
              if (d.platform.isNotEmpty) info('플랫폼', d.platform),
              info('상태', d.statusDescription),
              info('마지막 응답', _ago(d.lastSeen)),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                      icon: const Icon(Icons.copy, size: 18),
                      label: const Text('ID 복사'),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: d.id));
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('ID 를 복사했습니다')));
                      }),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                      icon: const Icon(Icons.folder_open, size: 18),
                      label: const Text('파일 전송'),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _connect(d.id, d.name, isFileTransfer: true);
                      }),
                ),
              ]),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                  icon: const Icon(Icons.desktop_windows, size: 18),
                  label: const Text('연결'),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _connect(d.id, d.name);
                  }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _supportHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
      child: Row(children: [
        const Icon(Icons.support_agent, size: 20, color: Colors.deepOrange),
        const SizedBox(width: 6),
        Text('지원 요청 ${_support.length}',
            style: const TextStyle(
                fontWeight: FontWeight.bold, color: Colors.deepOrange)),
        const SizedBox(width: 8),
        Expanded(
          child: Text('지원 프로그램을 켠 PC · 탭하면 바로 접속',
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall),
        ),
      ]),
    );
  }

  Widget _supportTile(CubeSupportRequest r) {
    return Card(
      key: ValueKey('support-${r.id}'),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      color: Colors.orange.withOpacity(0.10),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.orange.withOpacity(0.5))),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _connectSupport(r),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
          child: Row(children: [
            const Icon(Icons.computer, color: Colors.deepOrange),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                        [
                          '${_ago(r.since)} 시작',
                          'ID ${r.id}',
                          if (r.ip.isNotEmpty) r.ip,
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall),
                  ]),
            ),
            _connecting == r.id
                ? const Padding(
                    padding: EdgeInsets.all(8),
                    child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : ElevatedButton(
                    onPressed: () => _connectSupport(r),
                    child: const Text('접속')),
          ]),
        ),
      ),
    );
  }
}

class _SupportHeader {
  const _SupportHeader();
}

/// 콘솔 /api/viewer/support 한 줄 — 일회성 지원 프로그램이 켜져 있는 PC.
class CubeSupportRequest {
  CubeSupportRequest(Map<String, dynamic> d)
      : id = (d['id'] ?? '').toString(),
        hostname = (d['hostname'] ?? '').toString(),
        username = (d['username'] ?? '').toString(),
        ip = (d['ip'] ?? '').toString(),
        since = d['since'] is num
            ? DateTime.fromMillisecondsSinceEpoch((d['since'] as num).toInt())
            : null;

  final String id, hostname, username, ip;
  final DateTime? since;

  String get title => hostname.isEmpty
      ? '알 수 없는 PC'
      : username.isEmpty
          ? hostname
          : '$hostname ($username)';
}
