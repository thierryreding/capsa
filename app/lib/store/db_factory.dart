/// The sembast database factory of the platform: IndexedDB on the web, files in the
/// app's documents folder on Android and iOS.
library;

export 'db_factory_io.dart' if (dart.library.js_interop) 'db_factory_web.dart';
