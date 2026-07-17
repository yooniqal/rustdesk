import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../common.dart';
import '../../cuberemote_config.dart';
import 'home_page.dart';

// CubeRemote 가맹점 목록 탭. 콘솔의 읽기전용 뷰어 API에서 목록을 받아 표시하고,
// 카드를 누르면 공통 비밀번호로 바로 원격 접속한다.
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
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    // 온라인 상태 주기 갱신
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() { _loading = true; _error = null; });
    try {
      final uri = Uri.parse('${CubeRemoteConfig.consoleUrl}/api/viewer/devices');
      final res = await http.get(uri, headers: {
        'X-Viewer-Token': CubeRemoteConfig.viewerToken,
      }).timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) {
        throw '서버 응답 ${res.statusCode}';
      }
      final list = jsonDecode(utf8.decode(res.bodyBytes)) as List<dynamic>;
      if (mounted) setState(() { _devices = list; _loading = false; _error = null; });
    } catch (e) {
      if (mounted) setState(() { _loading = false; if (!silent) _error = '$e'; });
    }
  }

  void _connect(String id) {
    connect(context, id, password: CubeRemoteConfig.fixedPassword);
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

    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
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
                  : ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount: rows.length,
                      itemBuilder: (ctx, i) {
                        final d = rows[i];
                        final online = d['online'] == true;
                        final name = (d['name'] ?? '-').toString();
                        final region = (d['region'] ?? '').toString();
                        final id = (d['deviceId'] ?? '').toString();
                        return Card(
                          margin: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 5),
                          child: ListTile(
                            leading: Icon(Icons.circle,
                                size: 12,
                                color: online
                                    ? Colors.green
                                    : Colors.grey),
                            title: Text(name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            subtitle: Text(
                                '${region.isEmpty ? '지역미지정' : region} · $id'),
                            trailing: ElevatedButton(
                              onPressed: () => _connect(id),
                              child: const Text('연결'),
                            ),
                            onTap: () => _connect(id),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
