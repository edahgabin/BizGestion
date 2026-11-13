import 'data_transfer_stub.dart'
    if (dart.library.html) 'data_transfer_web.dart' as platform;

Future<void> downloadBusinessBackup(String filename, String contents) =>
    platform.downloadBusinessBackup(filename, contents);

Future<String?> pickBusinessBackupJson() => platform.pickBusinessBackupJson();
