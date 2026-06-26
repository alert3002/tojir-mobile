import 'web_tab_resume_stub.dart'
    if (dart.library.html) 'web_tab_resume_web.dart' as impl;

void bindWebTabResume(void Function() onResume) => impl.bindWebTabResume(onResume);
