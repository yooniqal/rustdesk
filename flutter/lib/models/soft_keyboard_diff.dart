// 소프트키보드 입력창의 이전/현재 텍스트를 비교해 원격에 보낼 편집(백스페이스 + 새 문자열)을 계산한다.
//
// 입력창은 센티넬('1' * 1024)로 시작한다 — 백스페이스가 항상 지울 글자를 갖게 하려는 트릭.
// 원격 커서는 항상 입력한 글자의 끝에 있으므로, 편집은 "바뀐 지점부터 끝까지 지우고 다시 친다"로
// 표현한다. 조합(composing) 여부는 보지 않는다: 삼성 키보드는 영문 단어도 통째로 조합 상태로
// 두기 때문에, 조합이 끝날 때까지 전송을 미루면 스페이스를 눌러야 글자가 한꺼번에 들어간다.

class SoftKeyboardEdit {
  // 원격에 보낼 백스페이스 수(문자 단위).
  final int backspaces;
  // 백스페이스 뒤에 입력할 문자열.
  final String inserted;
  // 입력창과 기준값이 어긋났다 — 호출 측은 입력창을 기준점으로 되돌려야 한다.
  final bool resync;

  const SoftKeyboardEdit(
      {this.backspaces = 0, this.inserted = '', this.resync = false});

  bool get isEmpty => backspaces == 0 && inserted.isEmpty;
}

// 한 번의 입력으로 지울 수 있는 글자 수 상한. diff 가 어긋났을 때 원격 문서가
// 백스페이스 수백 개로 날아가는 것을 막는다.
const int kSoftKeyboardMaxBackspaces = 32;

// 한 번의 입력으로 보낼 수 있는 글자 수 상한. 센티넬이 통째로 전송되는 것을 막는다.
const int kSoftKeyboardMaxInserted = 256;

bool _isLowSurrogate(int unit) => unit >= 0xDC00 && unit <= 0xDFFF;

SoftKeyboardEdit diffSoftKeyboardText(String oldValue, String newValue) {
  if (oldValue == newValue) return const SoftKeyboardEdit();

  var prefix = 0;
  final minLength =
      oldValue.length < newValue.length ? oldValue.length : newValue.length;
  while (prefix < minLength &&
      oldValue.codeUnitAt(prefix) == newValue.codeUnitAt(prefix)) {
    ++prefix;
  }
  // 서로게이트 쌍의 가운데에서 자르지 않는다.
  if (prefix > 0 &&
      ((prefix < oldValue.length &&
              _isLowSurrogate(oldValue.codeUnitAt(prefix))) ||
          (prefix < newValue.length &&
              _isLowSurrogate(newValue.codeUnitAt(prefix))))) {
    --prefix;
  }

  final backspaces = oldValue.substring(prefix).runes.length;
  final inserted = newValue.substring(prefix);
  if (backspaces <= kSoftKeyboardMaxBackspaces &&
      inserted.length <= kSoftKeyboardMaxInserted) {
    return SoftKeyboardEdit(backspaces: backspaces, inserted: inserted);
  }

  // 끝이 아닌 곳(센티넬 앞·가운데)에 글자가 들어갔다 = 입력창 커서가 끝에 있지 않았다.
  // 예전 방식은 이때 센티넬의 '1' 을 새 글자로 계산해 무엇을 쳐도 1 이 전송됐다.
  // 순수 삽입이면 그 글자만 보내고, 호출 측이 커서를 끝으로 되돌리게 한다.
  var suffix = 0;
  while (suffix < minLength - prefix &&
      oldValue.codeUnitAt(oldValue.length - 1 - suffix) ==
          newValue.codeUnitAt(newValue.length - 1 - suffix)) {
    ++suffix;
  }
  final removed = oldValue.substring(prefix, oldValue.length - suffix);
  final middle = newValue.substring(prefix, newValue.length - suffix);
  if (removed.isEmpty &&
      middle.isNotEmpty &&
      middle.length <= kSoftKeyboardMaxInserted) {
    return SoftKeyboardEdit(inserted: middle, resync: true);
  }

  // 정상 입력에서는 나올 수 없는 수치. 원격을 망가뜨리느니 아무것도 보내지 않는다.
  return const SoftKeyboardEdit(resync: true);
}
