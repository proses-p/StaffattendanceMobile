import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

class OfflineDb {
  OfflineDb._();

  static final OfflineDb instance = OfflineDb._();
  Database? _database;
  static const _databaseName = 'field_operations.db';

  Future<Database> get database async {
    final existing = _database;
    if (existing != null) return existing;

    final root = await getDatabasesPath();
    final db = await openDatabase(
      path.join(root, _databaseName),
      version: 2,
      onCreate: (database, version) async {
        await database.execute('''
          CREATE TABLE outbox (
            seq INTEGER PRIMARY KEY AUTOINCREMENT,
            owner_user_id TEXT NOT NULL,
            client_uuid TEXT NOT NULL UNIQUE,
            type TEXT NOT NULL,
            payload TEXT NOT NULL,
            recorded_at TEXT NOT NULL,
            device_time TEXT NOT NULL,
            time_source TEXT NOT NULL,
            status TEXT NOT NULL DEFAULT 'pending',
            attempts INTEGER NOT NULL DEFAULT 0,
            last_error TEXT
          )
        ''');
        await database.execute('''
          CREATE TABLE local_session (
            owner_user_id TEXT PRIMARY KEY,
            client_uuid TEXT NOT NULL,
            task_type TEXT NOT NULL,
            clock_in_at TEXT NOT NULL,
            purpose_description TEXT,
            field_assignment_id INTEGER
          )
        ''');
        await database.execute('''
          CREATE TABLE local_visits (
            client_uuid TEXT PRIMARY KEY,
            owner_user_id TEXT NOT NULL,
            assignment_client_uuid TEXT NOT NULL,
            client_name TEXT NOT NULL,
            arrived_at TEXT NOT NULL,
            departed_at TEXT
          )
        ''');
        await _createFieldExpensesTable(database);
      },
      onUpgrade: (database, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await database.execute(
            'ALTER TABLE local_session ADD COLUMN field_assignment_id INTEGER',
          );
          await _createFieldExpensesTable(database);
        }
      },
      onOpen: (database) async {
        await database.update('field_expenses', {
          'sync_status': 'pending',
        }, where: "sync_status = 'syncing'");
      },
    );
    _database = db;
    return db;
  }

  @visibleForTesting
  Future<void> resetForTesting() async {
    await closeForTesting();
    final root = await getDatabasesPath();
    await databaseFactory.deleteDatabase(path.join(root, _databaseName));
  }

  @visibleForTesting
  Future<void> closeForTesting() async {
    final existing = _database;
    _database = null;
    await existing?.close();
  }

  static Future<void> _createFieldExpensesTable(DatabaseExecutor database) {
    return database.execute('''
      CREATE TABLE field_expenses (
        local_id INTEGER PRIMARY KEY AUTOINCREMENT,
        owner_user_id TEXT NOT NULL,
        client_uuid TEXT NOT NULL UNIQUE,
        field_assignment_id INTEGER,
        assignment_client_uuid TEXT NOT NULL,
        category TEXT NOT NULL,
        amount TEXT NOT NULL,
        currency TEXT NOT NULL DEFAULT 'TZS',
        description TEXT,
        local_receipt_path TEXT,
        is_offline INTEGER NOT NULL DEFAULT 0,
        sync_status TEXT NOT NULL DEFAULT 'pending',
        retryable INTEGER NOT NULL DEFAULT 1,
        last_error TEXT,
        created_at TEXT NOT NULL
      )
    ''');
  }
}
