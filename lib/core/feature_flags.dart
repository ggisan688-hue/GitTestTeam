/// 기능 스위치. 팀 합의가 안 된 기능을 코드 한 줄로 끄고 켠다.
///
/// 끄려면 `true` 를 `false` 로 바꾸고 앱을 다시 빌드해서 올린다.
/// (서버는 그대로 두어도 된다. 앱이 새 기능을 호출하지 않을 뿐이다.)
class FeatureFlags {
  const FeatureFlags._();

  /// 메모 창에서 [저장]을 안 눌러도, 닫기/바깥 터치/뒤로가기 때 자동 저장
  /// false 면 예전처럼 [저장]을 눌러야만 저장된다.
  static const bool memoAutoSave = true;

  /// "독서중인 사람 보기": 방 멤버 옆 '독서중' 표시, 책 화면 오른쪽 위 화살표,
  /// 메모 쓰는 중 '...' 표시, 보기 설정의 스위치까지 전부.
  /// false 면 서버로 위치를 보내지도 않고 화면에도 아무것도 안 나온다.
  static const bool readingFriends = true;
}
