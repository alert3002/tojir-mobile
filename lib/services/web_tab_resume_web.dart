// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

void bindWebTabResume(void Function() onResume) {
  html.document.onVisibilityChange.listen((_) {
    if (html.document.visibilityState == 'visible') {
      onResume();
    }
  });
}
