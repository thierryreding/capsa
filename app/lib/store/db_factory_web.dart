import 'package:sembast_web/sembast_web.dart';

/// Opens `name` in IndexedDB.
Future<Database> openPlatformDatabase(String name) => databaseFactoryWeb.openDatabase(name);

Future<void> deletePlatformDatabase(String name) => databaseFactoryWeb.deleteDatabase(name);
