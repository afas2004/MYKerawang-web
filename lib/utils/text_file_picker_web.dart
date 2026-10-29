import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

const bool canPick = true;

/// A hidden `<input type=file>`: the browser's own picker, no plugin.
Future<String?> pickTextFile() {
  final done = Completer<String?>();
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = '.csv,.txt,text/csv,text/plain';
  input.addEventListener(
    'change',
    ((web.Event _) {
      final file = input.files?.item(0);
      if (file == null) {
        if (!done.isCompleted) done.complete(null);
        return;
      }
      file.text().toDart.then((t) {
        if (!done.isCompleted) done.complete(t.toDart);
      }, onError: (Object _) {
        if (!done.isCompleted) done.complete(null);
      });
    }).toJS,
  );
  input.addEventListener(
    'cancel',
    ((web.Event _) {
      if (!done.isCompleted) done.complete(null);
    }).toJS,
  );
  input.click();
  return done.future;
}
