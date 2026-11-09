import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:staff_attendance_mobile/models/field_expense_model.dart';
import 'package:staff_attendance_mobile/screens/expense_capture_screen.dart';
import 'package:staff_attendance_mobile/screens/field_mode_screen.dart';
import 'package:staff_attendance_mobile/screens/my_expenses_screen.dart';
import 'package:staff_attendance_mobile/services/api_service.dart';
import 'package:staff_attendance_mobile/services/field_service.dart';
import 'package:staff_attendance_mobile/services/field_expense_repository.dart';
import 'package:staff_attendance_mobile/services/field_expense_service.dart';
import 'package:staff_attendance_mobile/services/offline_db.dart';
import 'package:staff_attendance_mobile/services/sync_service.dart';

Directory? _supportDirectory;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory supportDirectory;
  late Directory sourceDirectory;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'auth_user_id': 7,
      'auth_token': 'test-token',
    });
    await OfflineDb.instance.resetForTesting();
    supportDirectory = await Directory.systemTemp.createTemp('expense-support');
    _supportDirectory = supportDirectory;
    sourceDirectory = await Directory.systemTemp.createTemp('expense-source');
  });

  tearDown(() async {
    await OfflineDb.instance.resetForTesting();
    if (await supportDirectory.exists()) {
      await supportDirectory.delete(recursive: true);
    }
    if (await sourceDirectory.exists()) {
      await sourceDirectory.delete(recursive: true);
    }
  });

  test('expense categories and amount validation match backend values', () {
    expect(FieldExpenseModel.categories.keys, [
      'transport_fuel',
      'meals_refreshments',
      'client_entertainment',
      'other_emergency',
    ]);
    expect(FieldExpenseModel.validateAmount('1250.50'), isNull);
    expect(FieldExpenseModel.validateAmount('0'), isNotNull);
    expect(FieldExpenseModel.validateAmount('-1'), isNotNull);
    expect(FieldExpenseModel.validateAmount('1.234'), isNotNull);
    expect(FieldExpenseModel.validateAmount('100000000'), isNotNull);
  });

  test(
    'server approval status and rejection notes map into the expense model',
    () {
      final expense = FieldExpenseModel.fromApi({
        'category': 'transport_fuel',
        'amount': '2500.00',
        'currency': 'TZS',
        'submitted_at': '2026-11-09T00:00:00Z',
        'status': 'rejected',
        'admin_notes': 'Receipt was not legible.',
        'field_assignment_id': 9,
      });

      expect(expense.status, 'rejected');
      expect(expense.adminNotes, 'Receipt was not legible.');
      expect(expense.fieldAssignmentId, 9);
    },
  );

  test(
    'expenses persist across repository recreation and support multiples',
    () async {
      final repository = _repository();
      final assignmentUuid = 'offline-assignment-uuid';
      await repository.save(
        assignmentClientUuid: assignmentUuid,
        category: 'transport_fuel',
        amount: '3000.00',
        currency: 'TZS',
        isOffline: true,
      );
      await repository.save(
        assignmentClientUuid: assignmentUuid,
        category: 'meals_refreshments',
        amount: '7500.00',
        currency: 'TZS',
        isOffline: true,
      );

      await OfflineDb.instance.closeForTesting();
      final restored = await FieldExpenseRepository().forAssignment(
        assignmentUuid,
      );

      expect(restored, hasLength(2));
      expect(
        restored.map((row) => row['field_assignment_id']),
        everyElement(isNull),
      );
      expect(restored.map((row) => row['is_offline']), everyElement(1));
    },
  );

  test(
    'upgrading the local database preserves queued attendance events',
    () async {
      final databasePath = path.join(
        await getDatabasesPath(),
        'field_operations.db',
      );
      final legacyDatabase = await openDatabase(
        databasePath,
        version: 1,
        onCreate: (database, _) async {
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
            purpose_description TEXT
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
        },
      );
      await legacyDatabase.insert('outbox', {
        'owner_user_id': '7',
        'client_uuid': 'existing-attendance-event',
        'type': 'field_clock_in',
        'payload': '{}',
        'recorded_at': DateTime.utc(2026, 11, 9).toIso8601String(),
        'device_time': DateTime.utc(2026, 11, 9).toIso8601String(),
        'time_source': 'device',
      });
      await legacyDatabase.close();

      final upgraded = await OfflineDb.instance.database;

      expect(
        (await upgraded.query('outbox')).single['client_uuid'],
        'existing-attendance-event',
      );
      expect(await upgraded.query('field_expenses'), isEmpty);
      expect(
        (await upgraded.rawQuery('PRAGMA table_info(local_session)'))
            .map((column) => column['name']),
        contains('field_assignment_id'),
      );
    },
  );

  test(
    'captured receipt is copied to persistent app-private storage',
    () async {
      final source = File('${sourceDirectory.path}/temporary.png');
      await source.writeAsBytes([1, 2, 3, 4]);
      final repo = _repository();

      await repo.save(
        assignmentClientUuid: 'receipt-assignment',
        category: 'transport_fuel',
        amount: '500.00',
        currency: 'TZS',
        isOffline: true,
        receiptSourcePath: source.path,
      );

      final row = (await repo.forAssignment('receipt-assignment')).single;
      final persistentPath = row['local_receipt_path']! as String;
      expect(persistentPath, isNot(source.path));
      expect(await File(persistentPath).exists(), isTrue);
    },
  );

  test('expense submission uses multipart and removes local data only after confirmation', () async {
    final source = File('${sourceDirectory.path}/receipt.webp');
    await source.writeAsBytes([5, 6, 7, 8]);
    final repository = _repository();
    await repository.save(
      assignmentClientUuid: 'server-assignment',
      fieldAssignmentId: 42,
      category: 'transport_fuel',
      amount: '1234.50',
      currency: 'TZS',
      description: 'Fuel',
      isOffline: true,
      receiptSourcePath: source.path,
    );
    final local = (await repository.forAssignment('server-assignment')).single;
    final receiptPath = local['local_receipt_path']! as String;
    var requestCount = 0;
    final api = ApiService(
      client: MockClient((request) async {
        requestCount++;
        expect(request, isA<http.Request>());
        expect(
          request.headers['content-type'],
          startsWith('multipart/form-data; boundary='),
        );
        final multipartBody = utf8.decode(
          request.bodyBytes,
          allowMalformed: true,
        );
        expect(multipartBody, contains('name="field_assignment_id"'));
        expect(multipartBody, contains('\r\n\r\n42\r\n'));
        expect(multipartBody, contains('name="category"'));
        expect(multipartBody, contains('transport_fuel'));
        expect(multipartBody, contains('1234.50'));
        expect(multipartBody, contains('name="currency"'));
        expect(multipartBody, contains('TZS'));
        expect(multipartBody, contains(local['client_uuid']));
        expect(multipartBody, contains('name="is_offline"'));
        expect(multipartBody, contains('name="receipt"; filename='));
        expect(multipartBody, contains('filename="'));
        return http.Response(
          jsonEncode({
            'expense': {'id': 42},
            'duplicate': false,
          }),
          201,
        );
      }),
    );
    final service = FieldExpenseService(
      apiService: api,
      repository: repository,
    );

    await service.synchronizePending(
      online: true,
      resolveAssignmentId: (_) async => 42,
    );

    expect(requestCount, 1);
    expect(await repository.forAssignment('server-assignment'), isEmpty);
    expect(await File(receiptPath).exists(), isFalse);
  });

  test(
    'temporary upload failure retains expense and receipt for retry',
    () async {
      final source = File('${sourceDirectory.path}/receipt.jpg');
      await source.writeAsBytes([5, 6, 7, 8]);
      final repository = _repository();
      await repository.save(
        assignmentClientUuid: 'retry-assignment',
        fieldAssignmentId: 10,
        category: 'meals_refreshments',
        amount: '800.00',
        currency: 'TZS',
        isOffline: true,
        receiptSourcePath: source.path,
      );
      final local = (await repository.forAssignment('retry-assignment')).single;
      final receiptPath = local['local_receipt_path']! as String;
      final clientUuid = local['client_uuid'];
      final service = FieldExpenseService(
        apiService: ApiService(
          client: MockClient(
            (_) async => http.Response('{"message":"Try again"}', 503),
          ),
        ),
        repository: repository,
      );

      await service.synchronizePending(
        online: true,
        resolveAssignmentId: (_) async => 10,
      );

      final retained = (await repository.forAssignment('retry-assignment'))
          .single;
      expect(retained['sync_status'], 'pending');
      expect(retained['retryable'], 1);
      expect(retained['client_uuid'], clientUuid);
      expect(await File(receiptPath).exists(), isTrue);
    },
  );

  test('offline expenses remain queued until connectivity returns', () async {
    final repository = _repository();
    await repository.save(
      assignmentClientUuid: 'offline-queue-assignment',
      fieldAssignmentId: 10,
      category: 'meals_refreshments',
      amount: '800.00',
      currency: 'TZS',
      isOffline: true,
    );
    var requestCount = 0;
    final service = FieldExpenseService(
      apiService: ApiService(
        client: MockClient((_) async {
          requestCount++;
          return http.Response('{"expense":{"id":1}}', 201);
        }),
      ),
      repository: repository,
    );

    await service.synchronizePending(
      online: false,
      resolveAssignmentId: (_) async => 10,
    );

    expect(requestCount, 0);
    expect(
      (await repository.forAssignment('offline-queue-assignment'))
          .single['sync_status'],
      'pending',
    );
  });

  test(
    'simultaneous synchronization attempts upload each expense once',
    () async {
      final repository = _repository();
      await repository.save(
        assignmentClientUuid: 'concurrent-assignment',
        fieldAssignmentId: 3,
        category: 'other_emergency',
        amount: '250.00',
        currency: 'TZS',
        isOffline: false,
      );
      final requestStarted = Completer<void>();
      final finishRequest = Completer<void>();
      var requestCount = 0;
      final service = FieldExpenseService(
        repository: repository,
        apiService: ApiService(
          client: MockClient((_) async {
            requestCount++;
            requestStarted.complete();
            await finishRequest.future;
            return http.Response('{"expense":{"id":1}}', 201);
          }),
        ),
      );

      final first = service.synchronizePending(
        online: true,
        resolveAssignmentId: (_) async => 3,
      );
      await requestStarted.future;
      await service.synchronizePending(
        online: true,
        resolveAssignmentId: (_) async => 3,
      );
      finishRequest.complete();
      await first;

      expect(requestCount, 1);
    },
  );

  test(
    'expense sync failure does not block field event synchronization',
    () async {
      final db = await OfflineDb.instance.database;
      const eventUuid = 'field-event-to-sync';
      await db.insert('outbox', {
        'owner_user_id': '7',
        'client_uuid': eventUuid,
        'type': 'field_clock_in',
        'payload': '{}',
        'recorded_at': DateTime.utc(2026, 11, 9).toIso8601String(),
        'device_time': DateTime.utc(2026, 11, 9).toIso8601String(),
        'time_source': 'device',
        'status': 'pending',
        'attempts': 0,
      });
      final apiService = _FakeSyncApiService();
      final syncService = SyncService.forTesting(
        apiService: apiService,
        expenseService: _FailingExpenseService(),
      );

      await syncService.flushForTesting();

      expect(apiService.syncedEvents, hasLength(1));
      expect(apiService.syncedEvents.single.single['client_uuid'], eventUuid);
      expect(await db.query('outbox'), isEmpty);
      syncService.dispose();
    },
  );

  testWidgets('camera receipt capture shows a preview and retake action', (
    tester,
  ) async {
    final image = File('${sourceDirectory.path}/camera.png');
    await tester.runAsync(
      () => image.writeAsBytes(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/Jx8AAAAASUVORK5CYII=',
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ExpenseCaptureScreen(
          assignmentClientUuid: 'test-assignment',
          expenseService: _FakeExpenseService(),
          captureFromCamera: () async => XFile(image.path),
          receiptLength: (_) async => 4,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.text('Take receipt photo (optional)'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(Image), findsOneWidget);
    expect(find.text('Retake'), findsOneWidget);
  });

  testWidgets('category dropdown shows readable expense categories', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ExpenseCaptureScreen(
          assignmentClientUuid: 'test-assignment',
          expenseService: _FakeExpenseService(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.text('Transport / Fuel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Meals / Refreshments').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Meals / Refreshments'), findsOneWidget);
  });

  testWidgets('employee expense history displays decisions and sync failures', (
    tester,
  ) async {
    final service = _FakeExpenseService(
      historyRecords: [
        _historyRecord(status: 'pending', amount: '100.00'),
        _historyRecord(status: 'approved', amount: '200.00'),
        _historyRecord(
          status: 'rejected',
          amount: '300.00',
          adminNotes: 'Missing assignment evidence.',
        ),
        _historyRecord(
          status: 'pending',
          amount: '400.00',
          syncStatus: 'pending',
        ),
        _historyRecord(
          status: 'pending',
          amount: '500.00',
          syncStatus: 'failed',
          localId: 5,
          syncError: 'The service is temporarily unavailable.',
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(home: MyExpensesScreen(expenseService: service)),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    final scrollable = find.byType(Scrollable).last;
    for (final status in [
      'Pending',
      'Approved',
      'Rejected',
      'Pending Synchronization',
      'Synchronization Failed',
      'Admin note: Missing assignment evidence.',
    ]) {
      await tester.scrollUntilVisible(
        find.text(status),
        300,
        scrollable: scrollable,
      );
      expect(find.text(status), findsOneWidget);
    }
  });

  testWidgets('clock-out No path continues the existing clock-out once', (
    tester,
  ) async {
    final service = _FakeFieldService();
    await tester.pumpWidget(
      MaterialApp(
        home: FieldModeScreen(
          fieldService: service,
          expenseService: _FakeExpenseService(),
          initializeSync: () async {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.text('Clock Out of Field'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      find.text('Did you incur any expenses during this field assignment?'),
      findsOneWidget,
    );
    await tester.tap(find.text('No, Continue'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(service.clockOutCalls, 1);
    expect(service.clockOutCalls, 1);
  });

  testWidgets('clock-out Yes path finishes expenses then clocks out once', (
    tester,
  ) async {
    final service = _FakeFieldService();
    await tester.pumpWidget(
      MaterialApp(
        home: FieldModeScreen(
          fieldService: service,
          expenseService: _FakeExpenseService(),
          initializeSync: () async {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.text('Clock Out of Field'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Yes, Add Expenses'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(ExpenseCaptureScreen), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Finish and Continue Clock-Out'),
      400,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Finish and Continue Clock-Out'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(service.clockOutCalls, 1);
  });
}

FieldExpenseRepository _repository() {
  return FieldExpenseRepository(
    supportDirectoryProvider: () async => _supportDirectory!,
  );
}

class _FakeExpenseService extends FieldExpenseService {
  _FakeExpenseService({this.historyRecords = const []});

  final List<FieldExpenseModel> historyRecords;

  @override
  Future<List<FieldExpenseModel>> combinedHistory({
    required bool online,
  }) async => historyRecords;

  @override
  Future<List<FieldExpenseModel>> expensesForAssignment({
    required String assignmentUuid,
    required int? fieldAssignmentId,
    required bool online,
  }) async => const [];

  @override
  Future<String> saveExpense({
    required String assignmentClientUuid,
    required String category,
    required String amount,
    required bool isOffline,
    int? fieldAssignmentId,
    String? description,
    String? receiptPath,
  }) async => 'test-client-uuid';
}

FieldExpenseModel _historyRecord({
  required String status,
  required String amount,
  String? adminNotes,
  String? syncStatus,
  int? localId,
  String? syncError,
}) {
  return FieldExpenseModel(
    category: 'transport_fuel',
    amount: amount,
    currency: 'TZS',
    submittedAt: DateTime.utc(2026, 11, 9),
    status: status,
    fieldAssignmentId: 25,
    adminNotes: adminNotes,
    syncStatus: syncStatus,
    localId: localId,
    syncError: syncError,
  );
}

class _FakeFieldService extends FieldService {
  Map<String, Object?>? session = {
    'client_uuid': 'active-assignment-uuid',
    'field_assignment_id': 9,
    'task_type': 'marketing',
    'clock_in_at': DateTime.utc(2026, 11, 9).toIso8601String(),
  };
  int clockOutCalls = 0;

  @override
  Future<Map<String, Object?>?> currentSession() async => session;

  @override
  Future<List<Map<String, Object?>>> todaysVisits() async => const [];

  @override
  Future<bool> restoreActiveFromServer() async => true;

  @override
  Future<void> clockOut() async {
    clockOutCalls++;
    session = null;
  }
}

class _FakeSyncApiService extends ApiService {
  final syncedEvents = <List<Map<String, dynamic>>>[];

  @override
  Future<Map<String, dynamic>> syncBatch(
    List<Map<String, dynamic>> events,
  ) async {
    syncedEvents.add(events);
    return {
      'results': [
        for (final event in events)
          {'client_uuid': event['client_uuid'], 'status': 'applied'},
      ],
    };
  }
}

class _FailingExpenseService extends FieldExpenseService {
  @override
  Future<Set<String>> synchronizePending({
    required bool online,
    required AssignmentIdResolver resolveAssignmentId,
  }) async {
    throw StateError('Simulated expense sync failure.');
  }
}
