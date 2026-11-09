import 'package:flutter/material.dart';
import 'package:staff_attendance_mobile/custom/sync_banner.dart';
import 'package:staff_attendance_mobile/screens/expense_capture_screen.dart';
import 'package:staff_attendance_mobile/screens/my_expenses_screen.dart';
import 'package:staff_attendance_mobile/services/field_expense_service.dart';
import 'package:staff_attendance_mobile/services/field_service.dart';
import 'package:staff_attendance_mobile/services/sync_service.dart';

class FieldModeScreen extends StatefulWidget {
  const FieldModeScreen({
    super.key,
    this.fieldService,
    this.expenseService,
    this.initializeSync,
  });

  final FieldService? fieldService;
  final FieldExpenseService? expenseService;
  final Future<void> Function()? initializeSync;

  @override
  State<FieldModeScreen> createState() => _FieldModeScreenState();
}

class _FieldModeScreenState extends State<FieldModeScreen> {
  static const _taskTypes = {
    'marketing': 'Marketing',
    'research': 'Research',
    'client_meeting': 'Client meeting',
    'innovation_week': 'Innovation week',
  };

  late final FieldService _fieldService = widget.fieldService ?? FieldService();
  final _purposeController = TextEditingController();
  final _clientController = TextEditingController();
  Map<String, Object?>? _session;
  List<Map<String, Object?>> _visits = const [];
  String _taskType = 'marketing';
  bool _loading = true;
  bool _submitting = false;
  bool _checkingRemoteSession = true;
  bool _clockingOut = false;
  Object? _loadError;

  @override
  void initState() {
    super.initState();
    (widget.initializeSync ?? SyncService.instance.initialize)();
    _loadLocalState();
    _restoreActiveSession();
  }

  Future<void> _restoreActiveSession() async {
    try {
      await _fieldService.restoreActiveFromServer();
      if (!mounted) return;
      setState(() {
        _checkingRemoteSession = false;
        _loadError = null;
      });
      await _loadLocalState();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _checkingRemoteSession = false;
        _loadError = error;
      });
    }
  }

  @override
  void dispose() {
    _purposeController.dispose();
    _clientController.dispose();
    super.dispose();
  }

  Future<void> _loadLocalState() async {
    try {
      final session = await _fieldService.currentSession();
      final visits = await _fieldService.todaysVisits();
      if (!mounted) return;
      setState(() {
        _session = session;
        _visits = visits;
        _loading = false;
        _loadError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error;
        _loading = false;
      });
    }
  }

  Future<void> _runAction(Future<void> Function() action) async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      await action();
      await SyncService.instance.refreshCounts();
      await _loadLocalState();
    } catch (error) {
      if (mounted) {
        final message = error.toString().replaceFirst(
          RegExp(r'^(Exception|StateError|ArgumentError): '),
          '',
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _promptClockOut() async {
    if (_submitting || _clockingOut || _session == null) return;
    setState(() => _clockingOut = true);
    try {
      final addExpenses = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Field expenses'),
          content: const Text(
            'Did you incur any expenses during this field assignment?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('No, Continue'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFB923C),
              ),
              child: const Text('Yes, Add Expenses'),
            ),
          ],
        ),
      );
      if (!mounted || addExpenses == null) return;
      if (addExpenses) {
        final session = _session!;
        final assignmentUuid = session['client_uuid']?.toString();
        if (assignmentUuid == null || assignmentUuid.isEmpty) {
          throw StateError(
            'The active field assignment could not be identified.',
          );
        }
        final finished = await Navigator.of(context).push<bool>(
          MaterialPageRoute<bool>(
            builder: (_) => ExpenseCaptureScreen(
              assignmentClientUuid: assignmentUuid,
              fieldAssignmentId: _toInt(session['field_assignment_id']),
              expenseService: widget.expenseService,
            ),
          ),
        );
        if (!mounted || finished != true) return;
      }
      await _runAction(_fieldService.clockOut);
    } catch (error) {
      if (mounted) {
        final message = error.toString().replaceFirst(
          RegExp(r'^(Exception|StateError|ArgumentError): '),
          '',
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
        );
      }
    } finally {
      if (mounted) setState(() => _clockingOut = false);
    }
  }

  int? _toInt(Object? value) =>
      value is int ? value : int.tryParse(value?.toString() ?? '');

  @override
  Widget build(BuildContext context) {
    final session = _session;
    final openVisit = _visits.cast<Map<String, Object?>?>().firstWhere(
      (visit) => visit?['departed_at'] == null,
      orElse: () => null,
    );
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF8FAFC),
        foregroundColor: const Color(0xFF172033),
        elevation: 0,
        title: const Text(
          'Field Mode',
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
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
          ? Center(
              child: Text('Unable to load saved field activity: $_loadError'),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              children: [
                const SyncBanner(),
                if (_loadError != null && !_checkingRemoteSession)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7ED),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Could not verify an existing server field session. Connect and retry before starting a new session.',
                      style: TextStyle(color: Color(0xFF9A3412)),
                    ),
                  ),
                if (session == null) ...[
                  _buildClockInForm(
                    disabled: _loadError != null || _checkingRemoteSession,
                  ),
                ] else ...[
                  _buildSessionCard(session),
                  const SizedBox(height: 18),
                  if (openVisit == null) ...[
                    TextField(
                      controller: _clientController,
                      decoration: const InputDecoration(
                        labelText: 'Client name',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _submitting
                            ? null
                            : () => _runAction(
                                () => _fieldService.arrive(
                                  _clientController.text,
                                ),
                              ),
                        icon: const Icon(Icons.place_outlined),
                        label: const Text('Arrived'),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFFB923C),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  ] else ...[
                    FilledButton.tonalIcon(
                      onPressed: _submitting
                          ? null
                          : () => _runAction(
                              () => _fieldService.depart(
                                openVisit['client_uuid']!.toString(),
                              ),
                            ),
                      icon: const Icon(Icons.logout),
                      label: Text('Depart ${openVisit['client_name']}'),
                    ),
                  ],
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    onPressed: _submitting || _clockingOut
                        ? null
                        : _promptClockOut,
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: const Text('Clock Out of Field'),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    "Today's route",
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF172033),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_visits.isEmpty)
                    const Text(
                      'No client visits recorded today.',
                      style: TextStyle(color: Color(0xFF64748B)),
                    )
                  else
                    ..._visits.map(_visitCard),
                ],
              ],
            ),
    );
  }

  Widget _buildClockInForm({required bool disabled}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Choose task type',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _taskTypes.entries
              .map(
                (task) => ChoiceChip(
                  label: Text(task.value),
                  selected: _taskType == task.key,
                  onSelected: (selected) {
                    if (selected) setState(() => _taskType = task.key);
                  },
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _purposeController,
          maxLength: 1000,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Purpose (optional)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _submitting || disabled
                ? null
                : () => _runAction(
                    () => _fieldService.clockIn(
                      _taskType,
                      purpose: _purposeController.text,
                    ),
                  ),
            icon: const Icon(Icons.play_arrow),
            label: const Text('Clock In to Field'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFB923C),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSessionCard(Map<String, Object?> session) {
    final start = DateTime.tryParse(session['clock_in_at']!.toString())
        ?.toLocal();
    return Card(
      color: Colors.white,
      child: ListTile(
        leading: const CircleAvatar(
          backgroundColor: Color(0xFFFFF7ED),
          child: Icon(Icons.work_outline, color: Color(0xFFEA580C)),
        ),
        title: Text(
          _taskTypes[session['task_type']] ?? session['task_type'].toString(),
        ),
        subtitle: Text(
          'Clocked in ${start == null ? '' : MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(start))}'
          '${session['purpose_description'] == null ? '' : '\n${session['purpose_description']}'}',
        ),
      ),
    );
  }

  Widget _visitCard(Map<String, Object?> visit) {
    final arrived = DateTime.tryParse(visit['arrived_at']!.toString())
        ?.toLocal();
    final time = arrived == null
        ? ''
        : MaterialLocalizations.of(context)
              .formatTimeOfDay(TimeOfDay.fromDateTime(arrived));
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.location_on_outlined, color: Color(0xFFFB923C)),
      title: Text(visit['client_name']!.toString()),
      subtitle: Text(
        '$time${visit['departed_at'] == null ? ' · Visit open' : ' · Departed'}',
      ),
    );
  }
}
