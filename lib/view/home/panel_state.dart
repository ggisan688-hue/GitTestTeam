import 'package:flutter/foundation.dart';

/// 사이드 패널의 열림/닫힘과 현재 페이지. 읽기 화면 안에서만 쓰는 UI 상태
enum PanelTab { memo, ai, share }

class PanelState extends ChangeNotifier {
  bool isOpen = false;
  PanelTab tab = PanelTab.memo;

  void open(PanelTab t) {
    tab = t;
    isOpen = true;
    notifyListeners();
  }

  void toggle(PanelTab t) {
    if (isOpen && tab == t) {
      isOpen = false;
    } else {
      tab = t;
      isOpen = true;
    }
    notifyListeners();
  }

  void close() {
    if (!isOpen) return;
    isOpen = false;
    notifyListeners();
  }

  void select(PanelTab t) {
    tab = t;
    notifyListeners();
  }
}
