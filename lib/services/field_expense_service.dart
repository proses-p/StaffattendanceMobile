import 'package:flutter/foundation.dart';
import 'package:staff_attendance_mobile/models/field_expense_model.dart';
import 'package:staff_attendance_mobile/services/api_service.dart';
import 'package:staff_attendance_mobile/services/field_expense_repository.dart';

typedef AssignmentIdResolver = Future<int?> Function(String assignmentUuid);

class FieldExpenseService {
  FieldExpenseService({
    ApiService? apiService,
    FieldExpenseRepository? repository,
  }) : _apiService = apiService ?? ApiService(),
       _repository = repository ?? FieldExpenseRepository();

  final ApiService _apiService;
  final FieldExpenseRepository _repository;
  bool _syncing = false;

  Future<String> saveExpense({
    required String assignmentClientUuid,
    required String category,
    required String amount,
    required bool isOffline,
    int? fieldAssignmentId,
    String? description,
    String? receiptPath,
  }) {
    final amountError = FieldExpenseModel.validateAmount(amount);
    if (amountError != null) throw ArgumentError(amountError);
    if (!FieldExpenseModel.categories.containsKey(category)) {
      throw ArgumentError.value(category, 'category');
    }
    return _repository.save(
      assignmentClientUuid: assignmentClientUuid,
      fieldAssignmentId: fieldAssignmentId,
      category: category,
      amount: num.parse(amount).toStringAsFixed(2),
      currency: 'TZS',
      description: description,
      receiptSourcePath: receiptPath,
      isOffline: isOffline,
    );
  }

  Future<List<FieldExpenseModel>> localExpensesForAssignment(
    String assignmentUuid,
  ) async {
    final rows = await _repository.forAssignment(assignmentUuid);
    return rows.map(FieldExpenseModel.fromLocal).toList(growable: false);
  }

  Future<List<FieldExpenseModel>> history() async {
    final rows = await _repository.forHistory();
    return rows.map(FieldExpenseModel.fromLocal).toList(growable: false);
  }

  Future<List<FieldExpenseModel>> serverHistory() async {
    final rows = await _apiService.fetchMyFieldExpenses();
    return rows.map(FieldExpenseModel.fromApi).toList(growable: false);
  }

  Future<List<FieldExpenseModel>> expensesForAssignment({
    required String assignmentUuid,
    required int? fieldAssignmentId,
    required bool online,
  }) async {
    final local = await localExpensesForAssignment(assignmentUuid);
    if (!online || fieldAssignmentId == null) return local;
    try {
      final remote = await serverHistory();
      return remote
          .where((expense) => expense.fieldAssignmentId == fieldAssignmentId)
          .toList(growable: false);
    } on ApiRequestException {
      return local;
    } on Exception {
      return local;
    }
  }

  Future<List<FieldExpenseModel>> combinedHistory({
    required bool online,
  }) async {
    final local = await history();
    if (!online) return local;
    try {
      final remote = await serverHistory();
      return [...remote, ...local];
    } on ApiRequestException {
      return local;
    } on Exception {
      return local;
    }
  }

  Future<void> retry(int localId) => _repository.retry(localId);

  Future<Set<String>> synchronizePending({
    required bool online,
    required AssignmentIdResolver resolveAssignmentId,
  }) async {
    if (!online || _syncing) return <String>{};
    _syncing = true;
    final unresolvedAssignments = <String>{};
    try {
      final rows = await _repository.pending();
      for (final row in rows) {
        final localId = row['local_id']! as int;
        if (!await _repository.claim(localId)) continue;
        var assignmentId = row['field_assignment_id'] as int?;
        final assignmentUuid = row['assignment_client_uuid']! as String;
        if (assignmentId == null) {
          try {
            assignmentId = await resolveAssignmentId(assignmentUuid);
          } on ApiRequestException catch (error) {
            await _repository.updateLocalExpense(localId, {
              'sync_status': 'pending',
              'last_error': error.message,
            });
            unresolvedAssignments.add(assignmentUuid);
            continue;
          } catch (error) {
            await _repository.updateLocalExpense(localId, {
              'sync_status': 'pending',
              'last_error': error.toString(),
            });
            unresolvedAssignments.add(assignmentUuid);
            continue;
          }
          if (assignmentId == null) {
            await _repository.updateLocalExpense(localId, {
              'sync_status': 'pending',
              'last_error':
                  'Waiting for the server to confirm the field assignment.',
            });
            unresolvedAssignments.add(assignmentUuid);
            continue;
          }
          await _repository.attachAssignmentId(assignmentUuid, assignmentId);
        }

        try {
          final response = await _apiService.submitFieldExpense(
            fieldAssignmentId: assignmentId,
            category: row['category']! as String,
            amount: row['amount']! as String,
            currency: row['currency']! as String,
            description: row['description']?.toString(),
            receiptPath: row['local_receipt_path']?.toString(),
            clientUuid: row['client_uuid']! as String,
            isOffline: row['is_offline'] == 1,
          );
          if (response['expense'] is! Map) {
            throw const FormatException(
              'The server did not confirm expense creation.',
            );
          }
          await _repository.deleteAfterConfirmation({
            ...row,
            'sync_status': 'syncing',
          });
        } on ApiRequestException catch (error) {
          final permanent =
              error.statusCode >= 400 &&
              error.statusCode < 500 &&
              error.statusCode != 401 &&
              error.statusCode != 403 &&
              error.statusCode != 408 &&
              error.statusCode != 429;
          await _repository.updateLocalExpense(localId, {
            'sync_status': permanent ? 'failed' : 'pending',
            'retryable': permanent ? 0 : 1,
            'last_error': error.message,
          });
        } catch (error, stackTrace) {
          debugPrint('Expense synchronization failed: $error\n$stackTrace');
          await _repository.updateLocalExpense(localId, {
            'sync_status': 'pending',
            'retryable': 1,
            'last_error': error.toString(),
          });
        }
      }
    } finally {
      _syncing = false;
    }
    return unresolvedAssignments;
  }
}
