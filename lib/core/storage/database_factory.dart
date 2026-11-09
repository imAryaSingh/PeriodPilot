import 'database_factory_stub.dart'
    if (dart.library.io) 'database_factory_io.dart'
    as platform;

Future<void> initializeDatabaseFactory() =>
    platform.initializeDatabaseFactory();
