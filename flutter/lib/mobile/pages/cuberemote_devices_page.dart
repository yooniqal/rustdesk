import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../../common.dart';
import '../../cuberemote_config.dart';
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

class _CubeDevicesPageState extends State<CubeDevicesPage> {
  List<dynamic> _devices = [];
  bool _loading = false;
  String? _error;
  String _query = '';
  final Set<String> _collapsed = {}; // 접힌 지역명
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(
        const Duration(seconds: 20), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() { _loading = true; _error = null; });
    try {
      final uri =
          Uri.parse('${CubeRemoteConfig.consoleUrl}/api/viewer/devices');
      final res = await http.get(uri, headers: {
        'X-Viewer-Token': CubeRemoteConfig.viewerToken,
      }).timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) throw '서버 응답 ${res.statusCode}';
      final list = jsonDecode(utf8.decode(res.bodyBytes)) as List<dynamic>;
      if (mounted) {
        setState(() { _devices = list; _loading = false; _error = null; });
      }
    } catch (e) {
      if (mounted) setState(() { _loading = false; if (!silent) _error = '$e'; });
    }
  }

  void _connect(String id) {
    connect(context, id, password: CubeRemoteConfig.fixedPassword);
  }

  Future<void> _openConsole() async {
    final uri = Uri.parse(CubeRemoteConfig.consoleUrl);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  String _regionKey(dynamic d) {
    final r = (d['region'] ?? '').toString().trim();
    return r.isEmpty ? '지역미지정' : r;
  }

  // 지역 그룹 목록을 서버 순서(sortOrder) 유지하며 구성.
  // 그룹 순서 = 각 지역이 처음 등장한 순서(= 웹 콘솔 정렬과 동일), '지역미지정'은 맨 뒤.
  List<MapEntry<String, List<dynamic>>> _grouped(List<dynamic> rows) {
    final map = <String, List<dynamic>>{};
    final order = <String>[];
    for (final d in rows) {
      final k = _regionKey(d);
      if (!map.containsKey(k)) { map[k] = []; order.add(k); }
      map[k]!.add(d);
    }
    order.sort((a, b) {
      if (a == '지역미지정') return 1;
      if (b == '지역미지정') return -1;
      return 0; // 원래 등장 순서 유지
    });
    return order.map((k) => MapEntry(k, map[k]!)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final rows = _devices.where((d) {
      if (q.isEmpty) return true;
      final name = (d['name'] ?? '').toString().toLowerCase();
      final region = (d['region'] ?? '').toString().toLowerCase();
      final id = (d['deviceId'] ?? '').toString().toLowerCase();
      return name.contains(q) || region.contains(q) || id.contains(q);
    }).toList();
    final groups = _grouped(rows);

    // 플랫한 위젯 리스트로 펼침(그룹 헤더 + 카드)
    final items = <Widget>[];
    for (final g in groups) {
      final region = g.key;
      final list = g.value;
      final collapsed = _collapsed.contains(region);
      items.add(_groupHeader(region, list.length, collapsed));
      if (!collapsed) {
        for (final d in list) items.add(_deviceCard(d));
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
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text('불러오기 오류: $_error',
                  style: const TextStyle(color: Colors.redAccent)),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _loading && _devices.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: items,
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

  Widget _deviceCard(dynamic d) {
    final online = d['online'] == true;
    final name = (d['name'] ?? '-').toString();
    final id = (d['deviceId'] ?? '').toString();
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        leading: Icon(Icons.circle,
            size: 12, color: online ? Colors.green : Colors.grey),
        title:
            Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(id),
        trailing: ElevatedButton(
          onPressed: () => _connect(id),
          child: const Text('연결'),
        ),
        // 실수 접속 방지: 카드 전체 탭이 아니라 '연결' 버튼으로만 접속한다(스크롤 중 오접속 방지).
      ),
    );
  }
}
