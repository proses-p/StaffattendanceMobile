import 'package:flutter/material.dart';
import 'package:staff_attendance_mobile/models/leave_request_model.dart';
import 'package:staff_attendance_mobile/services/api_service.dart';

class LeaveManagementScreen extends StatefulWidget {
  const LeaveManagementScreen({this.apiService, super.key});

  final ApiService? apiService;

  @override
  State<LeaveManagementScreen> createState() => _LeaveManagementScreenState();
}

class _LeaveManagementScreenState extends State<LeaveManagementScreen> {
  static const _accent = Color(0xFFFB923C);
  static const _background = Color(0xFFF8FAFC);

  late final ApiService _apiService = widget.apiService ?? ApiService();
  List<LeaveRequest> _requests = const [];
  Object? _loadError;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final requests = await _apiService.fetchLeaveRequests();
      if (!mounted) return;
      setState(() {
        _requests = requests;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error;
        _isLoading = false;
      });
    }
  }

  Future<void> _openRequestForm() async {
    final savedRequest = await showModalBottomSheet<LeaveRequest>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _LeaveRequestForm(
        onSubmit:
            ({
              required leaveType,
              required startDate,
              required endDate,
              required reason,
            }) => _apiService.submitLeaveRequest(
              leaveType: leaveType,
              startDate: startDate,
              endDate: endDate,
              reason: reason,
            ),
      ),
    );
    if (savedRequest == null || !mounted) return;

    setState(() {
      _requests = [
        savedRequest,
        ..._requests.where((request) => request.id != savedRequest.id),
      ];
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Leave request submitted successfully.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  int _countFor(String status) =>
      _requests.where((request) => request.status == status).length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _background,
        foregroundColor: const Color(0xFF172033),
        elevation: 0,
        title: const Text(
          'Leave management',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: _isLoading && _requests.isEmpty
          ? const Center(child: CircularProgressIndicator(color: _accent))
          : _loadError != null && _requests.isEmpty
          ? _buildLoadError()
          : RefreshIndicator(
              color: _accent,
              onRefresh: _loadRequests,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                children: [
                  _buildOverview(),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: _openRequestForm,
                    icon: const Icon(Icons.add),
                    label: const Text('Request leave'),
                    style: FilledButton.styleFrom(
                      backgroundColor: _accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      textStyle: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Your requests',
                    style: TextStyle(
                      color: Color(0xFF172033),
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (_loadError != null) _buildInlineError(),
                  if (_isLoading && _requests.isNotEmpty)
                    const LinearProgressIndicator(color: _accent),
                  if (_requests.isEmpty)
                    _buildEmptyState()
                  else
                    ..._requests.map(_buildRequestCard),
                ],
              ),
            ),
    );
  }

  Widget _buildOverview() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Leave overview',
            style: TextStyle(
              color: Color(0xFF172033),
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${_requests.length} ${_requests.length == 1 ? 'request' : 'requests'} in your history',
            style: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _StatusCount(
                label: 'Pending',
                count: _countFor('pending'),
                background: const Color(0xFFFFF7ED),
                foreground: const Color(0xFF9A3412),
              ),
              _StatusCount(
                label: 'Approved',
                count: _countFor('approved'),
                background: const Color(0xFFECFDF5),
                foreground: const Color(0xFF047857),
              ),
              _StatusCount(
                label: 'Rejected',
                count: _countFor('rejected'),
                background: const Color(0xFFFFF1F2),
                foreground: const Color(0xFFBE123C),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRequestCard(LeaveRequest request) {
    final (Color foreground, Color background) = switch (request.status) {
      'approved' => (const Color(0xFF047857), const Color(0xFFECFDF5)),
      'rejected' => (const Color(0xFFBE123C), const Color(0xFFFFF1F2)),
      _ => (const Color(0xFF9A3412), const Color(0xFFFFF7ED)),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  request.leaveType,
                  style: const TextStyle(
                    color: Color(0xFF172033),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _capitalize(request.status),
                  style: TextStyle(
                    color: foreground,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Text(
              '${_formatDate(request.startDate)} – ${_formatDate(request.endDate)}'
              '${request.leaveDays == null ? '' : '\n${request.leaveDays} scheduled leave ${request.leaveDays == 1 ? 'day' : 'days'} (holidays excluded)'}'
              '${request.submittedAt == null ? '' : '\nSubmitted ${_formatDate(request.submittedAt!)}'}',
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontSize: 12,
                height: 1.45,
              ),
            ),
          ),
          children: [
            _DetailText(label: 'Reason', value: request.reason),
            if (request.decisionNote?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 10),
              _DetailText(
                label: 'Administrator response',
                value: request.decisionNote!,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: const Column(
        children: [
          Icon(Icons.event_note_outlined, size: 34, color: Color(0xFF94A3B8)),
          SizedBox(height: 10),
          Text(
            'No leave requests yet',
            style: TextStyle(
              color: Color(0xFF172033),
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Your submitted requests and their decisions will appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: _ErrorPanel(
          message: _errorMessage(_loadError!),
          onRetry: _loadRequests,
        ),
      ),
    );
  }

  Widget _buildInlineError() => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: _ErrorPanel(
      message: _errorMessage(_loadError!),
      onRetry: _loadRequests,
    ),
  );
}

class _LeaveRequestForm extends StatefulWidget {
  const _LeaveRequestForm({required this.onSubmit});

  final Future<LeaveRequest> Function({
    required String leaveType,
    required DateTime startDate,
    required DateTime endDate,
    required String reason,
  })
  onSubmit;

  @override
  State<_LeaveRequestForm> createState() => _LeaveRequestFormState();
}

class _LeaveRequestFormState extends State<_LeaveRequestForm> {
  static const _leaveTypes = ['Leave'];
  final _formKey = GlobalKey<FormState>();
  final _reasonController = TextEditingController();
  String _leaveType = _leaveTypes.first;
  DateTime? _startDate;
  DateTime? _endDate;
  bool _isSubmitting = false;
  Object? _submitError;

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _selectDate({required bool isStartDate}) async {
    final selected = await showDatePicker(
      context: context,
      initialDate: isStartDate
          ? _startDate ?? DateTime.now()
          : _endDate ?? _startDate ?? DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
      helpText: isStartDate ? 'Select start date' : 'Select end date',
    );
    if (selected == null || !mounted) return;
    setState(() {
      if (isStartDate) {
        _startDate = selected;
        if (_endDate != null && _endDate!.isBefore(selected)) {
          _endDate = null;
        }
      } else {
        _endDate = selected;
      }
    });
  }

  Future<void> _confirmAndSubmit() async {
    if (_isSubmitting || !(_formKey.currentState?.validate() ?? false)) return;
    final startDate = _startDate!;
    final endDate = _endDate!;
    final reason = _reasonController.text.trim();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Submit leave request?'),
        content: Text(
          'Request $_leaveType from ${_formatDate(startDate)} to ${_formatDate(endDate)}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Review'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFB923C),
            ),
            child: const Text('Submit request'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });
    try {
      final request = await widget.onSubmit(
        leaveType: _leaveType,
        startDate: startDate,
        endDate: endDate,
        reason: reason,
      );
      if (mounted) Navigator.of(context).pop(request);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitError = error;
        _isSubmitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          MediaQuery.viewInsetsOf(context).bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFCBD5E1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Request leave',
                  style: TextStyle(
                    color: Color(0xFF172033),
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 18),
                DropdownButtonFormField<String>(
                  initialValue: _leaveType,
                  decoration: const InputDecoration(
                    labelText: 'Leave type',
                    border: OutlineInputBorder(),
                  ),
                  items: _leaveTypes
                      .map(
                        (type) =>
                            DropdownMenuItem(value: type, child: Text(type)),
                      )
                      .toList(),
                  onChanged: _isSubmitting
                      ? null
                      : (type) {
                          if (type != null) setState(() => _leaveType = type);
                        },
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _dateField(
                        label: 'Start date',
                        date: _startDate,
                        onTap: () => _selectDate(isStartDate: true),
                        validator: (_) =>
                            _startDate == null ? 'Select a start date.' : null,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _dateField(
                        label: 'End date',
                        date: _endDate,
                        onTap: () => _selectDate(isStartDate: false),
                        validator: (_) {
                          if (_endDate == null) return 'Select an end date.';
                          if (_startDate != null &&
                              _endDate!.isBefore(_startDate!)) {
                            return 'End date must be on or after start date.';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _reasonController,
                  enabled: !_isSubmitting,
                  minLines: 3,
                  maxLines: 5,
                  maxLength: 2000,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Reason for leave',
                    hintText: 'Explain why you are requesting leave',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Enter a reason for your leave request.'
                      : null,
                ),
                if (_submitError != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    _errorMessage(_submitError!),
                    style: const TextStyle(
                      color: Color(0xFFB91C1C),
                      fontSize: 13,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _isSubmitting ? null : _confirmAndSubmit,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFFB923C),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Review and submit'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _dateField({
    required String label,
    required DateTime? date,
    required VoidCallback onTap,
    required FormFieldValidator<String> validator,
  }) {
    return TextFormField(
      key: ValueKey('$label-${date?.toIso8601String() ?? 'empty'}'),
      readOnly: true,
      onTap: _isSubmitting ? null : onTap,
      initialValue: date == null ? '' : _formatDate(date),
      decoration: InputDecoration(
        labelText: label,
        hintText: 'Select date',
        suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
        border: const OutlineInputBorder(),
      ),
      validator: validator,
    );
  }
}

class _StatusCount extends StatelessWidget {
  const _StatusCount({
    required this.label,
    required this.count,
    required this.background,
    required this.foreground,
  });

  final String label;
  final int count;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      '$label $count',
      style: TextStyle(
        color: foreground,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _DetailText extends StatelessWidget {
  const _DetailText({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(
          color: Color(0xFF475569),
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 3),
      Text(
        value,
        style: const TextStyle(
          color: Color(0xFF334155),
          fontSize: 13,
          height: 1.45,
        ),
      ),
    ],
  );
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFFECACA)),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.cloud_off_outlined, color: Color(0xFFB91C1C)),
        const SizedBox(height: 8),
        const Text(
          'Unable to load leave requests',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(message, textAlign: TextAlign.center),
        TextButton(onPressed: onRetry, child: const Text('Try again')),
      ],
    ),
  );
}

String _formatDate(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/'
    '${date.month.toString().padLeft(2, '0')}/${date.year}';

String _capitalize(String value) =>
    value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';

String _errorMessage(Object error) =>
    error.toString().replaceFirst(RegExp(r'^(Exception|StateError): '), '');
