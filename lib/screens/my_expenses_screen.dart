import 'package:flutter/material.dart';
import 'package:staff_attendance_mobile/models/field_expense_model.dart';
import 'package:staff_attendance_mobile/services/field_expense_service.dart';
import 'package:staff_attendance_mobile/services/sync_service.dart';

class MyExpensesScreen extends StatefulWidget {
  const MyExpensesScreen({this.expenseService, super.key});

  final FieldExpenseService? expenseService;

  @override
  State<MyExpensesScreen> createState() => _MyExpensesScreenState();
}

class _MyExpensesScreenState extends State<MyExpensesScreen> {
  late final FieldExpenseService _expenses =
      widget.expenseService ?? FieldExpenseService();
  List<FieldExpenseModel> _records = const [];
  bool _loading = true;
  Object? _loadError;

  @override
  void initState() {
    super.initState();
    _loadExpenses();
  }

  Future<void> _loadExpenses() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final records = await _expenses.combinedHistory(
        online: SyncService.instance.online,
      );
      if (!mounted) return;
      setState(() {
        _records = records;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error;
        _loading = false;
      });
    }
  }

  Future<void> _retry(FieldExpenseModel expense) async {
    final id = expense.localId;
    if (id == null) return;
    await _expenses.retry(id);
    await SyncService.instance.flush();
    await _loadExpenses();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF8FAFC),
        foregroundColor: const Color(0xFF172033),
        elevation: 0,
        title: const Text(
          'My expenses',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _loadExpenses,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _loadError != null
            ? ListView(
                children: [
                  const SizedBox(height: 120),
                  Center(child: Text('Unable to load expenses: $_loadError')),
                ],
              )
            : _records.isEmpty
            ? ListView(
                children: const [
                  SizedBox(height: 120),
                  Center(
                    child: Text(
                      'No expenses submitted yet.',
                      style: TextStyle(color: Color(0xFF64748B)),
                    ),
                  ),
                ],
              )
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: _records.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) =>
                    _expenseCard(context, _records[index]),
              ),
      ),
    );
  }

  Widget _expenseCard(BuildContext context, FieldExpenseModel expense) {
    final (label, color, icon) = _status(expense);
    final date = expense.submittedAt?.toLocal();
    final dateText = date == null
        ? 'Date unavailable'
        : MaterialLocalizations.of(context).formatMediumDate(date);
    return Card(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    FieldExpenseModel.categories[expense.category] ??
                        expense.category,
                    style: const TextStyle(
                      color: Color(0xFF172033),
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 15, color: color),
                      const SizedBox(width: 4),
                      Text(
                        label,
                        style: TextStyle(
                          color: color,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${expense.currency} ${expense.amount}',
              style: const TextStyle(
                color: Color(0xFF172033),
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '$dateText · Assignment ${expense.fieldAssignmentId == null ? 'pending sync' : '#${expense.fieldAssignmentId}'}',
              style: const TextStyle(color: Color(0xFF64748B)),
            ),
            if (expense.description?.isNotEmpty == true) ...[
              const SizedBox(height: 6),
              Text(expense.description!),
            ],
            if (expense.status == 'rejected' &&
                expense.adminNotes?.isNotEmpty == true) ...[
              const SizedBox(height: 8),
              Text(
                'Admin note: ${expense.adminNotes}',
                style: const TextStyle(color: Color(0xFF991B1B)),
              ),
            ],
            if (expense.syncError?.isNotEmpty == true) ...[
              const SizedBox(height: 8),
              Text(
                expense.syncError!,
                style: const TextStyle(color: Color(0xFF9A3412)),
              ),
            ],
            if (expense.syncStatus == 'failed' && expense.localId != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => _retry(expense),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry sync'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  (String, Color, IconData) _status(FieldExpenseModel expense) {
    if (expense.syncStatus == 'failed') {
      return (
        'Synchronization Failed',
        const Color(0xFFB91C1C),
        Icons.error_outline,
      );
    }
    if (expense.syncStatus == 'pending' ||
        expense.syncStatus == 'syncing' ||
        (expense.fieldAssignmentId == null && expense.syncStatus != null)) {
      return (
        'Pending Synchronization',
        const Color(0xFFB45309),
        Icons.cloud_upload_outlined,
      );
    }
    return switch (expense.status) {
      'approved' => (
        'Approved',
        const Color(0xFF15803D),
        Icons.check_circle_outline,
      ),
      'rejected' => (
        'Rejected',
        const Color(0xFFB91C1C),
        Icons.cancel_outlined,
      ),
      _ => ('Pending', const Color(0xFFB45309), Icons.hourglass_empty),
    };
  }
}
