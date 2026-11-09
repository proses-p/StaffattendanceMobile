import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:staff_attendance_mobile/services/api_service.dart';
import 'package:staff_attendance_mobile/services/field_expense_repository.dart';
import 'package:staff_attendance_mobile/services/location_service.dart';
import 'package:staff_attendance_mobile/services/offline_db.dart';
import 'package:staff_attendance_mobile/services/sync_service.dart';
import 'package:staff_attendance_mobile/services/trusted_clock.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

class FieldService {
  FieldService({LocationService? locationService})
    : _locationService = locationService ?? LocationService();

  static const _uuid = Uuid();
  final LocationService _locationService;

  static bool supportsTaskType(String taskType) => const {
    'marketing',
    'research',
    'client_meeting',
    'innovation_week',
  }.contains(taskType);

  Future<Map<String, Object?>?> currentSession() async {
    final db = await OfflineDb.instance.database;
    final owner = await _ownerId();
    final rows = await db.query(
      'local_session',
      where: 'owner_user_id = ?',
      whereArgs: [owner],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<List<Map<String, Object?>>> todaysVisits() async {
    final db = await OfflineDb.instance.database;
    final owner = await _ownerId();
    final now = DateTime.now();
    final start = DateTime(
      now.year,
      now.month,
      now.day,
    ).toUtc().toIso8601String();
    final end = DateTime(
      now.year,
      now.month,
      now.day + 1,
    ).toUtc().toIso8601String();
    return db.query(
      'local_visits',
      where: 'owner_user_id = ? AND arrived_at >= ? AND arrived_at < ?',
      whereArgs: [owner, start, end],
      orderBy: 'arrived_at',
    );
  }

  Future<bool> restoreActiveFromServer() async {
    final local = await currentSession();
    final assignment = await ApiService().fetchActiveField();
    if (assignment == null) return local != null;
    final owner = await _ownerId();
    final db = await OfflineDb.instance.database;
    final remoteUuid = assignment['client_uuid']?.toString();
    final remoteId = _intValue(assignment['id']);
    if (local != null) {
      if (remoteUuid == local['client_uuid']?.toString() && remoteId != null) {
        await db.update(
          'local_session',
          {'field_assignment_id': remoteId},
          where: 'owner_user_id = ? AND client_uuid = ?',
          whereArgs: [owner, remoteUuid],
        );
        await FieldExpenseRepository().attachAssignmentId(
          remoteUuid!,
          remoteId,
        );
      }
      return true;
    }

    final visits = assignment['visits'] is List
        ? (assignment['visits'] as List).whereType<Map>().toList()
        : const <Map>[];

    await db.transaction((transaction) async {
      final existing = await transaction.query(
        'local_session',
        where: 'owner_user_id = ?',
        whereArgs: [owner],
        limit: 1,
      );
      if (existing.isNotEmpty) return;
      await transaction.insert('local_session', {
        'owner_user_id': owner,
        'client_uuid': assignment['client_uuid'],
        'task_type': assignment['task_type'],
        'clock_in_at': assignment['clock_in_at'],
        'purpose_description': assignment['purpose_description'],
        'field_assignment_id': remoteId,
      });
      for (final visit in visits) {
        final clientUuid = visit['client_uuid']?.toString();
        final arrivedAt = visit['arrived_at']?.toString();
        if (clientUuid == null || arrivedAt == null) continue;
        await transaction.insert('local_visits', {
          'client_uuid': clientUuid,
          'owner_user_id': owner,
          'assignment_client_uuid': assignment['client_uuid'],
          'client_name': visit['client_name']?.toString() ?? 'Client',
          'arrived_at': arrivedAt,
          'departed_at': visit['departed_at'],
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    });
    return true;
  }

  Future<void> clockIn(String taskType, {String? purpose}) async {
    if (!supportsTaskType(taskType)) {
      throw ArgumentError.value(taskType, 'taskType');
    }
    final db = await OfflineDb.instance.database;
    final owner = await _ownerId();
    if (await currentSession() != null) {
      throw StateError('A field session is already active.');
    }
    final event = await _event('field_clock_in');
    event['payload'] = {
      ...event['payload'] as Map<String, dynamic>,
      'task_type': taskType,
      if (purpose?.trim().isNotEmpty == true)
        'purpose_description': purpose!.trim(),
    };

    await db.transaction((transaction) async {
      final existing = await transaction.query(
        'local_session',
        where: 'owner_user_id = ?',
        whereArgs: [owner],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        throw StateError('A field session is already active.');
      }
      await _insertEvent(transaction, event, owner);
      await transaction.insert('local_session', {
        'owner_user_id': owner,
        'client_uuid': event['client_uuid'],
        'task_type': taskType,
        'clock_in_at': event['recorded_at'],
        'purpose_description': purpose?.trim(),
        'field_assignment_id': null,
      });
    });
    unawaited(SyncService.instance.flush());
  }

  Future<void> arrive(String clientName) async {
    final name = clientName.trim();
    if (name.isEmpty) throw ArgumentError.value(clientName, 'clientName');
    final session = await currentSession();
    if (session == null) {
      throw StateError('Clock in to field before recording a visit.');
    }
    final db = await OfflineDb.instance.database;
    final owner = await _ownerId();
    final event = await _event('visit_arrive');
    event['payload'] = {
      ...event['payload'] as Map<String, dynamic>,
      'assignment_client_uuid': session['client_uuid'],
      'client_name': name,
    };
    await db.transaction((transaction) async {
      final activeSession = await transaction.query(
        'local_session',
        where: 'owner_user_id = ? AND client_uuid = ?',
        whereArgs: [owner, session['client_uuid']],
        limit: 1,
      );
      final openVisits = await transaction.query(
        'local_visits',
        where: 'owner_user_id = ? AND departed_at IS NULL',
        whereArgs: [owner],
        limit: 1,
      );
      if (activeSession.isEmpty) {
        throw StateError('There is no active field session.');
      }
      if (openVisits.isNotEmpty) {
        throw StateError(
          'Depart from the current client before arriving at another.',
        );
      }
      await _insertEvent(transaction, event, owner);
      await transaction.insert('local_visits', {
        'client_uuid': event['client_uuid'],
        'owner_user_id': owner,
        'assignment_client_uuid': session['client_uuid'],
        'client_name': name,
        'arrived_at': event['recorded_at'],
        'departed_at': null,
      });
    });
    unawaited(SyncService.instance.flush());
  }

  Future<void> depart(String visitUuid) async {
    final session = await currentSession();
    if (session == null) throw StateError('There is no active field session.');
    final db = await OfflineDb.instance.database;
    final owner = await _ownerId();
    final event = await _event('visit_depart');
    event['payload'] = {
      ...event['payload'] as Map<String, dynamic>,
      'visit_client_uuid': visitUuid,
    };
    await db.transaction((transaction) async {
      final currentVisit = await transaction.query(
        'local_visits',
        where: 'owner_user_id = ? AND client_uuid = ? AND departed_at IS NULL',
        whereArgs: [owner, visitUuid],
        limit: 1,
      );
      if (currentVisit.isEmpty) {
        throw StateError('The client visit is not open.');
      }
      await _insertEvent(transaction, event, owner);
      await transaction.update(
        'local_visits',
        {'departed_at': event['recorded_at']},
        where: 'owner_user_id = ? AND client_uuid = ?',
        whereArgs: [owner, visitUuid],
      );
    });
    unawaited(SyncService.instance.flush());
  }

  Future<void> clockOut() async {
    final session = await currentSession();
    if (session == null) throw StateError('There is no active field session.');
    final db = await OfflineDb.instance.database;
    final owner = await _ownerId();
    final event = await _event('field_clock_out');
    event['payload'] = {
      ...event['payload'] as Map<String, dynamic>,
      'assignment_client_uuid': session['client_uuid'],
    };
    await db.transaction((transaction) async {
      final activeSession = await transaction.query(
        'local_session',
        where: 'owner_user_id = ? AND client_uuid = ?',
        whereArgs: [owner, session['client_uuid']],
        limit: 1,
      );
      if (activeSession.isEmpty) {
        throw StateError('There is no active field session.');
      }
      await _insertEvent(transaction, event, owner);
      await transaction.update(
        'local_visits',
        {'departed_at': event['recorded_at']},
        where: 'owner_user_id = ? AND assignment_client_uuid = ? AND departed_at IS NULL',
        whereArgs: [owner, session['client_uuid']],
      );
      await transaction.delete(
        'local_session',
        where: 'owner_user_id = ?',
        whereArgs: [owner],
      );
    });
    unawaited(SyncService.instance.flush());
  }

  Future<int?> resolveAssignmentId(String assignmentClientUuid) async {
    final session = await currentSession();
    if (session != null &&
        session['client_uuid']?.toString() == assignmentClientUuid) {
      final cachedId = _intValue(session['field_assignment_id']);
      if (cachedId != null) return cachedId;
    }

    final assignment = await ApiService().fetchActiveField();
    if (assignment == null ||
        assignment['client_uuid']?.toString() != assignmentClientUuid) {
      return null;
    }
    final assignmentId = _intValue(assignment['id']);
    if (assignmentId == null) return null;
    await FieldExpenseRepository().attachAssignmentId(
      assignmentClientUuid,
      assignmentId,
    );
    return assignmentId;
  }

  Future<Map<String, dynamic>> _event(String type) async {
    final location = await _locationService.current();
    final time = await TrustedClock.instance.now();
    return {
      'client_uuid': _uuid.v4(),
      'type': type,
      'recorded_at': time.recordedAt.toUtc().toIso8601String(),
      'device_time': time.deviceTime.toUtc().toIso8601String(),
      'time_source': time.timeSource,
      'payload': location,
    };
  }

  Future<String> _ownerId() async {
    final preferences = await SharedPreferences.getInstance();
    final userId = preferences.getInt('auth_user_id');
    if (userId == null) {
      throw StateError(
        'The signed-in user could not be identified. Sign in again.',
      );
    }
    return userId.toString();
  }

  Future<void> _insertEvent(
    Transaction transaction,
    Map<String, dynamic> event,
    String owner,
  ) async {
    await transaction.insert('outbox', {
      'owner_user_id': owner,
      'client_uuid': event['client_uuid'],
      'type': event['type'],
      'payload': jsonEncode(event['payload']),
      'recorded_at': event['recorded_at'],
      'device_time': event['device_time'],
      'time_source': event['time_source'],
      'status': 'pending',
    });
  }

  int? _intValue(Object? value) =>
      value is int ? value : int.tryParse(value?.toString() ?? '');
}
