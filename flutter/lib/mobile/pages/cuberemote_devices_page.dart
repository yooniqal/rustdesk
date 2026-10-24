import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../common.dart';
import '../../cuberemote_api.dart';
import '../../cuberemote_config.dart';
import '../../models/cube_device_directory.dart';
import 'home_page.dart';

// CubeRemote 가맹점 목록 탭. 운영자가 접속코드로 로그인하면 콘솔 뷰어 API에서 목록을 받아
// 웹 콘솔과 동일한 순서(sortOrder)·지역 그룹으로 표시하고, [연결]을 누르면 그 기기의
// 접속 비밀번호를 콘솔에서 받아 접속한다(앱에 비밀번호 내장 없음 — cuberemote_api.dart).
// 편집/그룹/순서 변경은 웹 콘솔에서 하며, 상단 버튼으로 바로 열 수 있다.
// 시작할 때 콘솔의 배포본 versionCode 와 비교해 새 버전 배너를 띄운다.
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
  Timer? _timer;

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
  }

  @override
  void dispose() {
    _timer?.cancel();
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

  Future<void> _load() => _directory.refresh();

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

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final rows = _devices
        .where((d) =>
            d.matches(q) &&
            (_filter == 'all' ||
                (_filter == 'online' ? d.online : d.state == 'attention')))
        .toList();
    final groups = groupCubeDevices(rows);

    // 플랫한 위젯 리스트로 펼침(그룹 헤더 + 카드)
    final items = <Object>[];
    for (final g in groups) {
      final region = g.key;
      final list = g.value;
      final collapsed = _collapsed.contains(region);
      items.add(g);
      if (!collapsed) {
        items.addAll(list);
      }
    }

    if (!_loggedIn) return Scaffold(body: _loginView());

    return Scaffold(
      body: Column(
        children: [
          if (_newVersionLabel != null && !_dismissedUpdate) _updateBanner(),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
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
                const SizedBox(width: 8),
                IconButton(
                  tooltip: '콘솔 열기(편집/순서/그룹)',
                  icon: const Icon(Icons.open_in_new),
                  onPressed: _openConsole,
                ),
                IconButton(
                  tooltip: '${CubeViewerApi.operator} 로그아웃',
                  icon: const Icon(Icons.logout),
                  onPressed: _logout,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Wrap(spacing: 8, children: [
              for (final entry in {
                'all': '전체',
                'online': '온라인',
                'attention': '점검 필요'
              }.entries)
                ChoiceChip(
                    label: Text(entry.value),
                    selected: _filter == entry.key,
                    onSelected: (_) => setState(() => _filter = entry.key)),
              IconButton(
                  tooltip: '새로고침',
                  icon: const Icon(Icons.refresh),
                  onPressed: _loading ? null : _load),
            ]),
          ),
          if (_directory.updatedAt != null)
            Text(
                '마지막 갱신 ${TimeOfDay.fromDateTime(_directory.updatedAt!).format(context)} · ${rows.length}대',
                style: Theme.of(context).textTheme.bodySmall),
          if (_loading && _devices.isNotEmpty) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
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
                      itemCount: items.isEmpty ? 1 : items.length,
                      itemBuilder: (context, index) {
                        if (items.isEmpty)
                          return const Padding(
                              padding: EdgeInsets.all(32),
                              child: Center(child: Text('표시할 가맹점이 없습니다.')));
                        final item = items[index];
                        if (item is CubeDevice) return _deviceCard(item);
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

  Widget _groupHeader(String region, int count, bool collapsed) {
    return InkWell(
      onTap: () => setState(() {
        if (collapsed) {
          _collapsed.remove(region);
        } else {
          _collapsed.add(region);
        }
      }),
      child: Container(
        color: Colors.black.withOpacity(0.06),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Icon(collapsed ? Icons.chevron_right : Icons.expand_more, size: 20),
            const SizedBox(width: 4),
            Text('$region ($count)',
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _deviceCard(CubeDevice d) {
    final name = d.name;
    final id = d.id;
    final color = _error != null
        ? Colors.orange
        : switch (d.state) {
            'ready' => Colors.green,
            'attention' => Colors.orange,
            'offline' => Colors.grey,
            _ => Colors.blueGrey,
          };
    return Card(
      key: ValueKey(id),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.circle, size: 12, color: color),
            const SizedBox(width: 8),
            Expanded(
                child: Text(name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold))),
            const SizedBox(width: 8),
            Text(d.statusLabel, style: TextStyle(color: color)),
          ]),
          const SizedBox(height: 4),
          Text('$id${d.platform.isEmpty ? '' : ' · ${d.platform}'}',
              style: Theme.of(context).textTheme.bodySmall),
          Text(d.statusDescription,
              style: Theme.of(context).textTheme.bodySmall),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            IconButton(
                tooltip: '파일 전송',
                icon: const Icon(Icons.folder_open),
                onPressed: () => _connect(id, name, isFileTransfer: true)),
            const SizedBox(width: 8),
            ElevatedButton(
                onPressed: () => _connect(id, name),
                child: _connecting == id
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('연결')),
          ]),
        ]),
      ),
    );
  }
}
