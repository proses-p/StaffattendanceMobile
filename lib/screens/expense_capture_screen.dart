import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:staff_attendance_mobile/models/field_expense_model.dart';
import 'package:staff_attendance_mobile/screens/my_expenses_screen.dart';
import 'package:staff_attendance_mobile/services/field_expense_service.dart';
import 'package:staff_attendance_mobile/services/receipt_capture_service.dart';
import 'package:staff_attendance_mobile/services/sync_service.dart';

class ExpenseCaptureScreen extends StatefulWidget {
  const ExpenseCaptureScreen({
    required this.assignmentClientUuid,
    this.fieldAssignmentId,
    this.expenseService,
    this.captureFromCamera,
    this.receiptLength,
    super.key,
  });

  final String assignmentClientUuid;
  final int? fieldAssignmentId;
  final FieldExpenseService? expenseService;
  final Future<XFile?> Function()? captureFromCamera;
  final Future<int> Function(String path)? receiptLength;

  @override
  State<ExpenseCaptureScreen> createState() => _ExpenseCaptureScreenState();
}

class _ExpenseCaptureScreenState extends State<ExpenseCaptureScreen> {
  static const _accent = Color(0xFFFB923C);

  late final FieldExpenseService _expenses =
      widget.expenseService ?? FieldExpenseService();
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();
  String _category = FieldExpenseModel.categories.keys.first;
  XFile? _receipt;
  List<FieldExpenseModel> _recordedExpenses = const [];
  bool _loadingExpenses = true;
  bool _saving = false;
  bool _savedExpense = false;
  String? _amountError;

  @override
  void initState() {
    super.initState();
    _loadRecordedExpenses();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadRecordedExpenses() async {
    try {
      final records = await _expenses.expensesForAssignment(
        assignmentUuid: widget.assignmentClientUuid,
        fieldAssignmentId: widget.fieldAssignmentId,
        online: SyncService.instance.online,
      );
      if (!mounted) return;
      setState(() {
        _recordedExpenses = records;
        _loadingExpenses = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadingExpenses = false);
      _showMessage('Unable to load expenses: $error');
    }
  }

  Future<void> _captureReceipt() async {
    try {
      final capture =
          widget.captureFromCamera ?? ReceiptCaptureService().captureFromCamera;
      final image = await capture();
      if (image == null || !mounted) return;
      final extension = image.path.toLowerCase().split('.').last;
      if (!const {'jpg', 'jpeg', 'png', 'webp'}.contains(extension)) {
        _showMessage('Use a JPEG, PNG, or WEBP receipt image.');
        return;
      }
      final length = widget.receiptLength == null
          ? await File(image.path).length()
          : await widget.receiptLength!(image.path);
      if (length == 0 || length > 5 * 1024 * 1024) {
        _showMessage('Receipt images must be between 1 byte and 5 MB.');
        return;
      }
      setState(() => _receipt = image);
    } on PlatformException catch (error) {
      if (!mounted) return;
      _showMessage(
        error.code == 'camera_access_denied'
            ? 'Camera access is denied. Enable camera permission in Settings or continue without a receipt.'
            : 'Unable to open the camera. You can continue without a receipt.',
      );
    } catch (error) {
      if (!mounted) return;
      _showMessage('Unable to capture receipt: $error');
    }
  }

  Future<void> _saveExpense() async {
    final amountError = FieldExpenseModel.validateAmount(
      _amountController.text,
    );
    setState(() {
      _amountError = amountError;
      _savedExpense = false;
    });
    if (amountError != null || _saving) return;

    setState(() => _saving = true);
    try {
      await _expenses.saveExpense(
        assignmentClientUuid: widget.assignmentClientUuid,
        fieldAssignmentId: widget.fieldAssignmentId,
        category: _category,
        amount: _amountController.text,
        description: _descriptionController.text,
        receiptPath: _receipt?.path,
        isOffline:
            !SyncService.instance.online || widget.fieldAssignmentId == null,
      );
      if (!mounted) return;
      setState(() {
        _amountController.clear();
        _descriptionController.clear();
        _receipt = null;
        _savedExpense = true;
      });
      _showMessage('Expense saved on this device.');
      await SyncService.instance.flush();
      await _loadRecordedExpenses();
    } catch (error) {
      if (mounted) _showMessage('Expense was not saved: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
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
          'Field expenses',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            tooltip: 'My expenses',
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(builder: (_) => const MyExpensesScreen()),
            ),
            icon: const Icon(Icons.receipt_long_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          _buildRecordedExpenses(),
          const SizedBox(height: 16),
          Card(
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Add an expense',
                    style: TextStyle(
                      color: Color(0xFF172033),
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: _category,
                    decoration: const InputDecoration(
                      labelText: 'Expense category',
                      border: OutlineInputBorder(),
                    ),
                    items: FieldExpenseModel.categories.entries
                        .map(
                          (entry) => DropdownMenuItem(
                            value: entry.key,
                            child: Text(entry.value),
                          ),
                        )
                        .toList(),
                    onChanged: _saving
                        ? null
                        : (value) {
                            if (value != null) {
                              setState(() => _category = value);
                            }
                          },
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _amountController,
                    enabled: !_saving,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                    ],
                    onChanged: (value) => setState(
                      () => _amountError = FieldExpenseModel.validateAmount(
                        value,
                      ),
                    ),
                    decoration: InputDecoration(
                      labelText: 'Amount',
                      prefixText: 'TZS ',
                      border: const OutlineInputBorder(),
                      errorText: _amountError,
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _descriptionController,
                    enabled: !_saving,
                    maxLength: 5000,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Description (optional)',
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_receipt case final receipt?)
                    _receiptPreview(receipt)
                  else
                    OutlinedButton.icon(
                      onPressed: _saving ? null : _captureReceipt,
                      icon: const Icon(Icons.camera_alt_outlined),
                      label: const Text('Take receipt photo (optional)'),
                    ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _saveExpense,
                      icon: _saving
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.save_outlined),
                      label: Text(_saving ? 'Saving...' : 'Save Expense'),
                      style: FilledButton.styleFrom(
                        backgroundColor: _accent,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  if (_savedExpense) ...[
                    const SizedBox(height: 8),
                    Center(
                      child: TextButton.icon(
                        onPressed: () => setState(() => _savedExpense = false),
                        icon: const Icon(Icons.add),
                        label: const Text('Add another expense'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Finish and Continue Clock-Out'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordedExpenses() {
    return Card(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Recorded for this assignment',
              style: TextStyle(
                color: Color(0xFF172033),
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            if (_loadingExpenses)
              const Center(child: CircularProgressIndicator())
            else if (_recordedExpenses.isEmpty)
              const Text(
                'No expenses recorded yet.',
                style: TextStyle(color: Color(0xFF64748B)),
              )
            else
              ..._recordedExpenses.map(
                (expense) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.receipt_long_outlined,
                    color: _accent,
                  ),
                  title: Text(
                    '${FieldExpenseModel.categories[expense.category] ?? expense.category} · ${expense.currency} ${expense.amount}',
                  ),
                  subtitle: Text(_expenseStatusLabel(expense)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _receiptPreview(XFile receipt) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.file(
            File(receipt.path),
            height: 180,
            width: double.infinity,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const SizedBox(
              height: 120,
              child: Center(child: Text('Unable to preview this image.')),
            ),
          ),
        ),
        Row(
          children: [
            TextButton.icon(
              onPressed: _saving ? null : _captureReceipt,
              icon: const Icon(Icons.refresh),
              label: const Text('Retake'),
            ),
            TextButton.icon(
              onPressed: _saving ? null : () => setState(() => _receipt = null),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Remove'),
            ),
          ],
        ),
      ],
    );
  }

  String _expenseStatusLabel(FieldExpenseModel expense) {
    if (expense.syncStatus == 'failed') return 'Synchronization failed';
    if (expense.syncStatus == 'pending' || expense.syncStatus == 'syncing') {
      return 'Pending synchronization';
    }
    return switch (expense.status) {
      'approved' => 'Approved',
      'rejected' => 'Rejected',
      _ => 'Pending',
    };
  }
}
