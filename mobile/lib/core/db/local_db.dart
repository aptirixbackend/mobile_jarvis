import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'local_db.g.dart';

// --- Tables ---

class CachedMessages extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get sessionId => text()();
  TextColumn get role => text()();
  TextColumn get content => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

class LocalMemories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get key => text().unique()();
  TextColumn get value => text()();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

// --- Database ---

@DriftDatabase(tables: [CachedMessages, LocalMemories])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'nova_local'));

  @override
  int get schemaVersion => 1;

  Future<List<CachedMessage>> getMessages(String sessionId) =>
      (select(cachedMessages)
            ..where((t) => t.sessionId.equals(sessionId))
            ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
          .get();

  Future<void> insertMessage(CachedMessagesCompanion msg) =>
      into(cachedMessages).insert(msg);

  Future<void> clearSession(String sessionId) =>
      (delete(cachedMessages)..where((t) => t.sessionId.equals(sessionId))).go();

  Future<List<LocalMemory>> getAllMemories() => select(localMemories).get();

  Future<void> upsertMemory(String key, String value) =>
      into(localMemories).insertOnConflictUpdate(
        LocalMemoriesCompanion.insert(key: key, value: value),
      );
}

// Singleton
class LocalDatabase {
  LocalDatabase._();
  static final LocalDatabase instance = LocalDatabase._();

  late final AppDatabase db;

  Future<void> init() async {
    db = AppDatabase();
  }
}
