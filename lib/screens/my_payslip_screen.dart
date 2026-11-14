import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:staff_attendance_mobile/services/api_service.dart';

class MyPayslipScreen extends StatefulWidget {
  const MyPayslipScreen({this.apiService, super.key});

  final ApiService? apiService;

  @override
  State<MyPayslipScreen> createState() => _MyPayslipScreenState();
}

class _MyPayslipScreenState extends State<MyPayslipScreen> {
  static const _accent = Color(0xFFFB923C);
  late final ApiService _apiService = widget.apiService ?? ApiService();
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  Map<String, dynamic>? _payslip;
  String? _error;
  bool _isLoading = true;

  String get _monthKey =>
      '${_selectedMonth.year}-${_selectedMonth.month.toString().padLeft(2, '0')}';

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return _selectedMonth.year == now.year && _selectedMonth.month == now.month;
  }

  bool get _allowancesOnly => _payslip?['payroll_mode'] == 'allowances_only';

  @override
  void initState() {
    super.initState();
    _loadPayslip();
  }

  Future<void> _loadPayslip() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final result = await _apiService.fetchMyPayslip(month: _monthKey);
      if (!mounted) return;
      setState(() {
        _payslip = result;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _isLoading = false;
      });
    }
  }

  void _changeMonth(int offset) {
    setState(() {
      _selectedMonth = DateTime(
        _selectedMonth.year,
        _selectedMonth.month + offset,
      );
      _payslip = null;
    });
    _loadPayslip();
  }

  double _number(String key) {
    final value = _payslip?[key];
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _money(double amount) {
    final formatted = NumberFormat('#,##0.##', 'en_US').format(amount);
    return '${_payslip?['currency'] ?? 'TZS'} $formatted';
  }

  bool get _hasPendingAdvance {
    final requests = _payslip?['advance_requests'];
    return requests is List &&
        requests.any(
          (request) =>
              request is Map<String, dynamic> &&
              request['status']?.toString() == 'pending',
        );
  }

  Future<void> _requestSalaryAdvance() async {
    final formKey = GlobalKey<FormState>();
    final amountController = TextEditingController();
    final reasonController = TextEditingController();
    final maximum = _number('max_eligible_advance');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        title: const Text('Request Salary Advance'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Maximum eligible amount: ${_money(maximum)}'),
              const SizedBox(height: 14),
              TextFormField(
                controller: amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Amount (TZS)',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  final amount = double.tryParse(value?.trim() ?? '');
                  if (amount == null || amount < 1000) {
                    return 'Enter an amount of at least TZS 1,000.';
                  }
                  if (amount > maximum) {
                    return 'Amount exceeds your eligible maximum.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: reasonController,
                maxLength: 500,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Reason',
                  border: OutlineInputBorder(),
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Please provide a reason.'
                    : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.pop(dialogContext, true);
              }
            },
            child: const Text('Submit Request'),
          ),
        ],
      ),
    );

    try {
      if (confirmed == true) {
        await _apiService.submitSalaryAdvanceRequest(
          amount: double.parse(amountController.text.trim()),
          reason: reasonController.text.trim(),
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Salary advance request submitted.')),
        );
        await _loadPayslip();
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      amountController.dispose();
      reasonController.dispose();
    }
  }

  int _count(String key) => _number(key).round();

  String get _riskCategory {
    final score = _number('risk_score');
    if (score <= 25) return 'Low';
    if (score <= 55) return 'Moderate';
    return 'High';
  }

  Color _riskColor(BuildContext context) {
    if (_riskCategory == 'Low') return Colors.green.shade700;
    if (_riskCategory == 'Moderate') return Colors.orange.shade800;
    return Theme.of(context).colorScheme.error;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surface = theme.colorScheme.surface;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Payslip & Earnings'),
        actions: [
          IconButton(
            tooltip: 'Refresh payslip',
            onPressed: _isLoading ? null : _loadPayslip,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Previous month',
                  onPressed: () => _changeMonth(-1),
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Text(
                    DateFormat('MMMM yyyy').format(_selectedMonth),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Next month',
                  onPressed: _isCurrentMonth ? null : () => _changeMonth(1),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: _accent))
                : _error != null
                ? _buildError(theme)
                : _payslip == null
                ? const Center(child: Text('Payslip data is unavailable.'))
                : RefreshIndicator(
                    onRefresh: _loadPayslip,
                    color: _accent,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      children: [
                        _buildNetPayCard(theme),
                        const SizedBox(height: 14),
                        if (_isCurrentMonth &&
                            _payslip?['status'] == 'estimated')
                          _buildAdvanceRequestAction(theme, surface),
                        if (_isCurrentMonth &&
                            _payslip?['status'] == 'estimated')
                          const SizedBox(height: 14),
                        _buildBreakdownCard(theme, surface),
                        const SizedBox(height: 14),
                        _buildAdvanceRequestsCard(theme, surface),
                        const SizedBox(height: 14),
                        _buildPerformanceCard(theme, surface),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, size: 42, color: theme.hintColor),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _loadPayslip,
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNetPayCard(ThemeData theme) {
    final approved = _payslip?['status'] == 'approved';
    return Card(
      elevation: 0,
      color: _accent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _allowancesOnly ? 'TOTAL EARNED ALLOWANCES' : 'NET PAY',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    approved ? 'Approved Payslip' : 'Live Estimate',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 17),
            Text(
              _money(_number('net_pay')),
              style: theme.textTheme.headlineSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              approved
                  ? 'Final amount approved for ${DateFormat('MMMM yyyy').format(_selectedMonth)}'
                  : 'Current estimate for ${DateFormat('MMMM yyyy').format(_selectedMonth)}',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBreakdownCard(ThemeData theme, Color surface) {
    return Card(
      elevation: 0,
      color: surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Earnings & Deductions',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            if (!_allowancesOnly)
              _breakdownRow(
                'Basic Salary',
                _money(_number('basic_salary')),
                Icons.payments_outlined,
              ),
            _breakdownRow(
              'Overtime Pay (${_number('overtime_hours').toStringAsFixed(2)} hrs)',
              _money(_number('overtime_pay')),
              Icons.more_time_outlined,
            ),
            _breakdownRow(
              'Early Arrival Bonus (${_count('before_time_days')} days)',
              _money(_number('punctuality_allowance')),
              Icons.wb_sunny_outlined,
            ),
            _breakdownRow(
              'Daily Work Reports (${_count('accepted_work_reports')})',
              _money(_number('work_report_allowance')),
              Icons.assignment_turned_in_outlined,
            ),
            if (!_allowancesOnly)
              _breakdownRow(
                'Absence Deductions',
                '-${_money(_number('absence_deduction'))}',
                Icons.remove_circle_outline,
                valueColor: _number('absence_deduction') > 0
                    ? theme.colorScheme.error
                    : null,
                showDivider: false,
              ),
            if (_number('salary_advance_deduction') > 0)
              _breakdownRow(
                'Salary Advance Deduction',
                '-${_money(_number('salary_advance_deduction'))}',
                Icons.account_balance_wallet_outlined,
                valueColor: theme.colorScheme.error,
                showDivider: false,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdvanceRequestAction(ThemeData theme, Color surface) {
    final maximum = _number('max_eligible_advance');
    return Card(
      elevation: 0,
      color: surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.account_balance_wallet_outlined,
                  color: _accent,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _hasPendingAdvance
                        ? 'You already have a pending request for this month.'
                        : 'Maximum eligible: ${_money(maximum)}',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
            if (!_hasPendingAdvance) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonal(
                  onPressed: maximum < 1000 ? null : _requestSalaryAdvance,
                  child: const Text('Request Salary Advance'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAdvanceRequestsCard(ThemeData theme, Color surface) {
    final requests = _payslip?['advance_requests'];
    final items = requests is List
        ? requests.whereType<Map<String, dynamic>>().toList(growable: false)
        : const <Map<String, dynamic>>[];
    return Card(
      elevation: 0,
      color: surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Salary Advance Requests',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  'No requests for this month.',
                  style: theme.textTheme.bodySmall,
                ),
              )
            else
              ...items.map((item) {
                final status = item['status']?.toString() ?? 'pending';
                final statusColor = switch (status) {
                  'approved' => Colors.green.shade700,
                  'rejected' => theme.colorScheme.error,
                  _ => Colors.orange.shade800,
                };
                final createdAt = DateTime.tryParse(
                  item['created_at']?.toString() ?? '',
                );
                return Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _money(
                                double.tryParse(
                                      item['amount']?.toString() ?? '',
                                    ) ??
                                    0,
                              ),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              status[0].toUpperCase() + status.substring(1),
                              style: TextStyle(
                                color: statusColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (createdAt != null)
                        Text(
                          DateFormat('d MMM yyyy').format(createdAt),
                          style: theme.textTheme.bodySmall,
                        ),
                      if ((item['admin_note']?.toString() ?? '').isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'Admin note: ${item['admin_note']}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      const Divider(height: 18),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _breakdownRow(
    String title,
    String value,
    IconData icon, {
    Color? valueColor,
    bool showDivider = true,
  }) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 11),
          child: Row(
            children: [
              Icon(icon, size: 19, color: _accent),
              const SizedBox(width: 11),
              Expanded(child: Text(title, style: theme.textTheme.bodyMedium)),
              const SizedBox(width: 8),
              Text(
                value,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: valueColor,
                ),
              ),
            ],
          ),
        ),
        if (showDivider) const Divider(height: 1),
      ],
    );
  }

  Widget _buildPerformanceCard(ThemeData theme, Color surface) {
    final riskColor = _riskColor(context);
    final rate = _number('on_time_rate');
    return Card(
      elevation: 0,
      color: surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Performance & Risk Standing',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 17),
            Row(
              children: [
                Expanded(
                  child: _performanceMetric(
                    'On-Time Rate',
                    '${rate.toStringAsFixed(1)}%',
                    Icons.schedule,
                    _accent,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _performanceMetric(
                    'Risk Score',
                    '${_count('risk_score')}% · $_riskCategory',
                    Icons.shield_outlined,
                    riskColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: (rate / 100).clamp(0, 1),
                minHeight: 8,
                color: _accent,
                backgroundColor: theme.colorScheme.onSurface.withValues(
                  alpha: 0.1,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Tip: arrive before your shift starts and submit complete daily work reports to improve your standing and maximize your allowances.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _performanceMetric(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 10),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 3),
          Text(label, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}
