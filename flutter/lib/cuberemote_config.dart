// CubeRemote 커스텀 설정 (뷰어 앱 내장 값). 개인용 포크.
//
// 2026-10-24: 뷰어 토큰·가맹점 공통 비밀번호 상수를 제거했다. 운영자가 접속코드로 로그인하면
// 콘솔이 토큰을 발급하고 접속 비밀번호는 접속 직전에 기기별로 받아간다(cuberemote_api.dart).
// 이 파일에는 더 이상 비밀이 없다 — 공개 저장소 릴리스에 올라가도 전 가맹점 접속 수단이 되지 않는다.
class CubeRemoteConfig {
  // 콘솔(가맹점 목록/접속수단) 주소
  static const String consoleUrl = 'https://console.ceomate.co.kr';
}
