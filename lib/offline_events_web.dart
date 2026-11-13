import 'dart:html' as html;

class BrowserOnlineEvents {
  html.EventListener? _listener;

  void listen(void Function() callback) {
    _listener = (_) => callback();
    html.window.addEventListener('online', _listener);
  }

  void dispose() {
    final listener = _listener;
    if (listener != null) {
      html.window.removeEventListener('online', listener);
      _listener = null;
    }
  }
}
