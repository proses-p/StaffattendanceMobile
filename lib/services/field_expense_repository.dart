import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:staff_attendance_mobile/services/offline_db.dart';
import 'package:uuid/uuid.dart';

class FieldExpenseRepository {
  FieldExpenseRepository({
    OfflineDb? offlineDb,
    Future<Directory> Function()? supportDirectoryProvider,
  }) : _offlineDb = offlineDb ?? OfflineDb.instance,
       _supportDirectoryProvider =
           supportDirectoryProvider ?? getApplicationSupportDirectory;

  static const _uuid = Uuid();
  final OfflineDb _offlineDb;
  final Future<Directory> Function() _supportDirectoryProvider;

  Future<String> save({
    required String assignmentClientUuid,
    required String category,
    required String amount,
    required String currency,
    required bool isOffline,
    int? fieldAssignmentId,
    String? description,
    String? receiptSourcePath,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    final ownerId = preferences.getInt('auth_user_id');
    if (ownerId == null) {
      throw StateError('The signed-in user could not be identified.');
    }

    final uuid = _uuid.v4();
    String? persistentReceiptPath;
    try {
      if (receiptSourcePath != null) {
        persistentReceiptPath = await _persistReceipt(receiptSourcePath, uuid);
      }

      final database = await _offlineDb.database;
      await database.transaction((transaction) async {
        await transaction.insert('field_expenses', {
          'owner_user_id': ownerId.toString(),
          'client_uuid': uuid,
          'field_assignment_id': fieldAssignmentId,
          'assignment_client_uuid': assignmentClientUuid,
          'category': category,
          'amount': amount,
          'currency': currency,
          'description': description?.trim().isEmpty == true
              ? null
              : description?.trim(),
          'local_receipt_path': persistentReceiptPath,
          'is_offline': isOffline ? 1 : 0,
          'sync_status': 'pending',
          'retryable': 1,
          'created_at': DateTime.now().toUtc().toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.abort);
      });
      return uuid;
    } catch (_) {
      if (persistentReceiptPath != null) {
        try {
          final receiptFile = File(persistentReceiptPath);
          if (await receiptFile.exists()) await receiptFile.delete();
        } on FileSystemException catch (cleanupError) {
          debugPrint('Unable to remove unsaved receipt image: $cleanupError');
        }
      }
      rethrow;
    }
  }

  Future<List<Map<String, Object?>>> forAssignment(
    String assignmentClientUuid,
  ) async {
    final owner = await _ownerId();
    final database = await _offlineDb.database;
    return database.query(
      'field_expenses',
      where: 'owner_user_id = ? AND assignment_client_uuid = ?',
      whereArgs: [owner, assignmentClientUuid],
      orderBy: 'local_id',
    );
  }

  Future<List<Map<String, Object?>>> pending({
    bool includeFailed = false,
  }) async {
    final owner = await _ownerId();
    final database = await _offlineDb.database;
    return database.query(
      'field_expenses',
      where: includeFailed
          ? "owner_user_id = ? AND sync_status IN ('pending', 'failed')"
          : "owner_user_id = ? AND sync_status = 'pending'",
      whereArgs: [owner],
      orderBy: 'local_id',
    );
  }

  Future<List<Map<String, Object?>>> forHistory() async {
    final owner = await _ownerId();
    final database = await _offlineDb.database;
    return database.query(
      'field_expenses',
      where: 'owner_user_id = ?',
      whereArgs: [owner],
      orderBy: 'local_id DESC',
    );
  }

  Future<bool> claim(int localId) async {
    final database = await _offlineDb.database;
    final changed = await database.update(
      'field_expenses',
      {'sync_status': 'syncing'},
      where: "local_id = ? AND sync_status = 'pending' AND retryable = 1",
      whereArgs: [localId],
    );
    return changed == 1;
  }

  Future<void> updateLocalExpense(
    int localId,
    Map<String, Object?> values,
  ) async {
    final database = await _offlineDb.database;
    await database.update(
      'field_expenses',
      values,
      where: 'local_id = ?',
      whereArgs: [localId],
    );
  }

  Future<void> attachAssignmentId(
    String assignmentClientUuid,
    int fieldAssignmentId,
  ) async {
    final database = await _offlineDb.database;
    await database.transaction((transaction) async {
      await transaction.update(
        'field_expenses',
        {'field_assignment_id': fieldAssignmentId},
        where: 'assignment_client_uuid = ? AND field_assignment_id IS NULL',
        whereArgs: [assignmentClientUuid],
      );
      await transaction.update(
        'local_session',
        {'field_assignment_id': fieldAssignmentId},
        where: 'client_uuid = ?',
        whereArgs: [assignmentClientUuid],
      );
    });
  }

  Future<void> deleteAfterConfirmation(Map<String, Object?> row) async {
    final database = await _offlineDb.database;
    await database.transaction((transaction) async {
      await transaction.delete(
        'field_expenses',
        where: 'local_id = ? AND sync_status = ?',
        whereArgs: [row['local_id'], 'syncing'],
      );
    });
    final receipt = row['local_receipt_path']?.toString();
    if (receipt != null) {
      final file = File(receipt);
      if (await file.exists()) await file.delete();
    }
  }

  Future<void> retry(int localId) async {
    await updateLocalExpense(localId, {
      'sync_status': 'pending',
      'retryable': 1,
      'last_error': null,
    });
  }

  Future<String?> _persistReceipt(String sourcePath, String uuid) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw StateError('The captured receipt image is no longer available.');
    }
    final size = await source.length();
    if (size == 0 || size > 5 * 1024 * 1024) {
      throw StateError('Receipt images must be between 1 byte and 5 MB.');
    }
    final extension = path.extension(sourcePath).toLowerCase();
    if (!const {'.jpg', '.jpeg', '.png', '.webp'}.contains(extension)) {
      throw StateError('Receipt images must be JPEG, PNG, or WEBP.');
    }

    final support = await _supportDirectoryProvider();
    final directory = Directory(path.join(support.path, 'expense_receipts'));
    await directory.create(recursive: true);
    final destination = File(path.join(directory.path, '$uuid$extension'));
    await source.copy(destination.path);
    return destination.path;
  }

  Future<String> _ownerId() async {
    final preferences = await SharedPreferences.getInstance();
    final owner = preferences.getInt('auth_user_id');
    if (owner == null) {
      throw StateError('The signed-in user could not be identified.');
    }
    return owner.toString();
  }
}
