import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:staff_attendance_mobile/services/api_service.dart';
import 'package:staff_attendance_mobile/services/device_security_service.dart';
import 'package:staff_attendance_mobile/services/field_expense_service.dart';
import 'package:staff_attendance_mobile/services/offline_db.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

class SyncService extends ChangeNotifier with WidgetsBindingObserver {
  SyncService._({ApiService? apiService, FieldExpenseService? expenseService})
    : _api = apiService ?? ApiService(),
      _expenses = expenseService ?? FieldExpenseService();

  @visibleForTesting
  SyncService.forTesting({
    required ApiService apiService,
    required FieldExpenseService expenseService,
  }) : this._(apiService: apiService, expenseService: expenseService);

  static final SyncService instance = SyncService._();
  final ApiService _api;
  final FieldExpenseService _expenses;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _timer;
  bool _initialized = false;
  bool _flushing = false;
  bool _online = false;
  bool _syncing = false;
  bool _keyRecoveryRequired = false;
  bool _recoveringKey = false;
  String? _lastError;
  int _pending = 0;
  int _failed = 0;

  bool get online => _online;
  bool get syncing => _syncing;
  bool get keyRecoveryRequired => _keyRecoveryRequired;
  int get pendingCount => _pending;
  int get failedCount => _failed;
  String? get lastError => _lastError;

  static bool shouldKeepPendingAfterRequestFailure(int statusCode) =>
      statusCode == 401 ||
      statusCode == 403 ||
      statusCode == 429 ||
      statusCode >= 500;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    WidgetsBinding.instance.addObserver(this);
    await refreshCounts();
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      results,
    ) {
      _setOnline(results.any((result) => result != ConnectivityResult.none));
    });
    _timer = Timer.periodic(const Duration(minutes: 2), (_) => flush());
    try {
      _setOnline(
        (await Connectivity().checkConnectivity()).any(
          (result) => result != ConnectivityResult.none,
        ),
      );
      await _api.fetchTrustedTime();
    } catch (error) {
      debugPrint('Trusted clock synchronization failed: $error');
      await refreshCounts();
    }
  }

  Future<void> _setOnline(bool value) async {
    final changed = _online != value;
    _online = value;
    await refreshCounts();
    if (changed) notifyListeners();
    if (_online) unawaited(flush());
  }

  Future<void> refreshCounts() async {
    final db = await OfflineDb.instance.database;
    final preferences = await SharedPreferences.getInstance();
    final owner = preferences.getInt('auth_user_id')?.toString();
    if (owner == null) {
      _pending = 0;
      _failed = 0;
      notifyListeners();
      return;
    }
    final pending =
        Sqflite.firstIntValue(
          await db.rawQuery(
            "SELECT COUNT(*) FROM outbox WHERE status = 'pending' AND owner_user_id = ?",
            [owner],
          ),
        ) ??
        0;
    final failed =
        Sqflite.firstIntValue(
          await db.rawQuery(
            "SELECT COUNT(*) FROM outbox WHERE status = 'failed' AND owner_user_id = ?",
            [owner],
          ),
        ) ??
        0;
    _pending = pending;
    _failed = failed;
    notifyListeners();
  }

  Future<List<Map<String, Object?>>> failedEvents() async {
    final db = await OfflineDb.instance.database;
    final preferences = await SharedPreferences.getInstance();
    final owner = preferences.getInt('auth_user_id')?.toString();
    if (owner == null) return const [];
    return db.query(
      'outbox',
      where: "status = 'failed' AND owner_user_id = ?",
      whereArgs: [owner],
      orderBy: 'seq',
    );
  }

  Future<void> flush() async {
    if (!_initialized || !_online || _flushing || _recoveringKey) return;
    _flushing = true;
    _syncing = true;
    _lastError = null;
    notifyListeners();
    try {
      final db = await OfflineDb.instance.database;
      final preferences = await SharedPreferences.getInstance();
      final owner = preferences.getInt('auth_user_id')?.toString();
      if (owner == null) return;
      var expenseSyncAttempted = false;
      while (_online) {
        final rows = await db.query(
          'outbox',
          where: "status = 'pending' AND owner_user_id = ?",
          whereArgs: [owner],
          orderBy: 'seq',
          limit: 50,
        );
        if (rows.isEmpty) {
          if (!expenseSyncAttempted) await _synchronizeExpensesSafely();
          break;
        }
        final unresolvedExpenseAssignments = await _synchronizeExpensesSafely();
        expenseSyncAttempted = true;
        final eligibleRows = rows
            .where(
              (row) => !_mustWaitForExpenseAssignment(
                row,
                unresolvedExpenseAssignments,
              ),
            )
            .toList(growable: false);
        if (eligibleRows.isEmpty) break;
        final events = eligibleRows
            .map((row) {
              final payload = jsonDecode(row['payload']! as String);
              return {
                'client_uuid': row['client_uuid'],
                'type': row['type'],
                'recorded_at': row['recorded_at'],
                'device_time': row['device_time'],
                'time_source': row['time_source'],
                'payload': payload,
              };
            })
            .toList(growable: false);

        final Map<String, dynamic> response;
        try {
          response = await _api.syncBatch(events);
        } on DeviceSecurityException catch (error) {
          if (error.code == 'DEVICE_NOT_ENROLLED') {
            _keyRecoveryRequired = true;
          }
          _lastError = error.message;
          break;
        } on ApiRequestException catch (error) {
          if (shouldKeepPendingAfterRequestFailure(error.statusCode)) {
            _lastError = error.message;
            break;
          }
          await _markFailed(db, eligibleRows, error.message);
          break;
        } catch (error) {
          _lastError = error.toString();
          break;
        }
        _keyRecoveryRequired = false;

        final results = response['results'];
        if (results is! List) {
          _lastError = 'The server response did not include sync results; records remain queued.';
          break;
        }
        final resultByUuid = <String, Map<String, dynamic>>{};
        for (final value in results) {
          if (value is Map) {
            final item = Map<String, dynamic>.from(value);
            final uuid = item['client_uuid']?.toString();
            if (uuid != null) resultByUuid[uuid] = item;
          }
        }
        var incompleteResults = false;
        for (final row in eligibleRows) {
          final uuid = row['client_uuid']! as String;
          final result = resultByUuid[uuid];
          if (result == null) {
            incompleteResults = true;
            continue;
          }
          final status = result['status'];
          if (status == 'applied' || status == 'duplicate') {
            await db.delete(
              'outbox',
              where: 'client_uuid = ?',
              whereArgs: [uuid],
            );
          } else if (status == 'rejected') {
            await db.update(
              'outbox',
              {
                'status': 'failed',
                'attempts': (row['attempts'] as int? ?? 0) + 1,
                'last_error':
                    result['message']?.toString() ?? 'The event was rejected.',
              },
              where: 'client_uuid = ?',
              whereArgs: [uuid],
            );
          } else {
            incompleteResults = true;
          }
        }
        if (incompleteResults || resultByUuid.length < eligibleRows.length) {
          _lastError ??= 'The server returned incomplete sync results; remaining records are queued.';
          break;
        }
      }
    } finally {
      _flushing = false;
      _syncing = false;
      await refreshCounts();
    }
  }

  Future<void> recoverSigningKeyAndFlush(String currentPassword) async {
    if (!_keyRecoveryRequired || !_online || _flushing || _recoveringKey) {
      return;
    }

    _recoveringKey = true;
    _syncing = true;
    notifyListeners();
    var recovered = false;
    try {
      await _api.recoverSyncSigningKey(currentPassword);
      _keyRecoveryRequired = false;
      _lastError = null;
      recovered = true;
    } catch (error) {
      _lastError = error.toString();
    } finally {
      _recoveringKey = false;
      _syncing = false;
      notifyListeners();
    }

    if (recovered) await flush();
  }

  @visibleForTesting
  Future<void> flushForTesting() async {
    _initialized = true;
    _online = true;
    await flush();
  }

  Future<int?> _resolveExpenseAssignmentId(String assignmentUuid) async {
    final assignment = await _api.fetchActiveField();
    if (assignment == null ||
        assignment['client_uuid']?.toString() != assignmentUuid) {
      return null;
    }

    final id = assignment['id'];
    return id is int ? id : int.tryParse(id?.toString() ?? '');
  }

  Future<Set<String>> _synchronizeExpensesSafely() async {
    try {
      return await _expenses.synchronizePending(
        online: _online,
        resolveAssignmentId: _resolveExpenseAssignmentId,
      );
    } catch (error, stackTrace) {
      debugPrint(
        'Expense synchronization failed without stopping field event sync: '
        '$error\n$stackTrace',
      );
      return <String>{};
    }
  }

  bool _mustWaitForExpenseAssignment(
    Map<String, Object?> row,
    Set<String> unresolvedAssignments,
  ) {
    if (row['type'] != 'field_clock_out') return false;
    final rawPayload = row['payload'];
    if (rawPayload is! String) return false;
    final payload = jsonDecode(rawPayload);
    if (payload is! Map) return false;
    final assignmentUuid = payload['assignment_client_uuid']?.toString();
    return assignmentUuid != null &&
        unresolvedAssignments.contains(assignmentUuid);
  }

  Future<void> _markFailed(
    Database database,
    List<Map<String, Object?>> rows,
    String message,
  ) async {
    for (final row in rows) {
      await database.update(
        'outbox',
        {
          'status': 'failed',
          'attempts': (row['attempts'] as int? ?? 0) + 1,
          'last_error': message,
        },
        where: 'client_uuid = ?',
        whereArgs: [row['client_uuid']],
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshOnResume());
    }
  }

  Future<void> _refreshOnResume() async {
    try {
      await _api.fetchTrustedTime();
      await flush();
    } catch (error) {
      _lastError = 'Unable to refresh trusted time: $error';
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _connectivitySubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
