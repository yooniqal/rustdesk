import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../../common.dart';
import '../../cuberemote_config.dart';
import '../../models/cube_device_directory.dart';
import 'home_page.dart';

// CubeRemote 가맹점 목록 탭. 콘솔의 읽기전용 뷰어 API에서 목록을 받아
// 웹 콘솔과 동일한 순서(sortOrder)·지역 그룹으로 표시하고, 탭하면 공통 비번으로 접속한다.
// 편집/그룹/순서 변경은 웹 콘솔에서 하며, 상단 버튼으로 바로 열 수 있다.
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
  http.Client? _client;
  bool _foreground = true;
  String _filter = 'all';
  String _query = '';
  final Set<String> _collapsed = {}; // 접힌 지역명
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _directory.addListener(_changed);
    _load();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_foreground && ModalRoute.of(context)?.isCurrent != false) _load();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _directory.dispose();
    _client?.close();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground && ModalRoute.of(context)?.isCurrent != false) _load();
  }

  Future<void> _load() => _directory.refresh();

  Future<List<CubeDevice>> _fetch() async {
    final client = http.Client();
    _client = client;
    try {
      final uri =
          Uri.parse('${CubeRemoteConfig.consoleUrl}/api/viewer/devices');
      final res = await client.get(uri, headers: {
        'X-Viewer-Token': CubeRemoteConfig.viewerToken,
      }).timeout(const Duration(seconds: 12));
      if (res.statusCode == 401 || res.statusCode == 403) {
        throw const CubeDirectoryError('가맹점 목록 접근 설정을 확인해 주세요.');
      }
      if (res.statusCode == 429) {
        throw const CubeDirectoryError('조회 요청이 많습니다. 잠시 후 다시 갱신합니다.');
      }
      if (res.statusCode != 200) {
        throw CubeDirectoryError('서버 응답 오류 (${res.statusCode}). 다시 시도해 주세요.');
      }
      return decodeCubeDevices(utf8.decode(res.bodyBytes));
    } finally {
      client.close();
      if (identical(_client, client)) _client = null;
    }
  }

  void _connect(String id) {
    connect(context, id, password: CubeRemoteConfig.fixedPassword);
  }

  // 파일 전송 모드로 접속(원격 PC와 파일/이미지 주고받기).
  void _connectFile(String id) {
    connect(context, id,
        password: CubeRemoteConfig.fixedPassword, isFileTransfer: true);
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

    return Scaffold(
      body: Column(
        children: [
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
                onPressed: () => _connectFile(id)),
            const SizedBox(width: 8),
            ElevatedButton(
                onPressed: () => _connect(id), child: const Text('연결')),
          ]),
        ]),
      ),
    );
  }
}
