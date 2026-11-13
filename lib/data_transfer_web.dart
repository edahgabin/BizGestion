import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;

Future<void> downloadBusinessBackup(String filename, String contents) async {
  final blob = html.Blob([utf8.encode(contents)], 'application/json');
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..download = filename
    ..style.display = 'none';
  html.document.body?.children.add(anchor);
  anchor.click();
  anchor.remove();
  Timer(const Duration(seconds: 1), () => html.Url.revokeObjectUrl(url));
}

Future<String?> pickBusinessBackupJson() async {
  final input = html.FileUploadInputElement()
    ..accept = '.json,application/json'
    ..multiple = false;
  html.document.body?.children.add(input);
  final changed = input.onChange.first;
  input.click();
  await changed;
  input.remove();
  final files = input.files;
  if (files == null || files.isEmpty) return null;
  final reader = html.FileReader();
  final loaded = Completer<String?>();
  reader.onLoad.listen((_) => loaded.complete(reader.result?.toString()));
  reader.onError.listen((_) => loaded.completeError(StateError('Lecture de fichier impossible.')));
  reader.readAsText(files.first);
  return loaded.future;
}
