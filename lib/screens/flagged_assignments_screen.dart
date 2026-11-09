import 'package:flutter/material.dart';
import 'package:staff_attendance_mobile/services/api_service.dart';

class FlaggedAssignmentsScreen extends StatefulWidget {
  const FlaggedAssignmentsScreen({super.key, this.apiService});

  final ApiService? apiService;

  @override
  State<FlaggedAssignmentsScreen> createState() =>
      _FlaggedAssignmentsScreenState();
}

class _FlaggedAssignmentsScreenState extends State<FlaggedAssignmentsScreen> {
  late final ApiService _api = widget.apiService ?? ApiService();
  List<Map<String, dynamic>> _assignments = const [];
  Object? _error;
  bool _loading = true;
  int? _reviewingId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final assignments = await _api.fetchFlaggedAssignments();
      if (!mounted) return;
      setState(() {
        _assignments = assignments;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _review(int id) async {
    setState(() => _reviewingId = id);
    try {
      await _api.reviewFieldAssignment(id);
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    } finally {
      if (mounted) setState(() => _reviewingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF8FAFC),
        foregroundColor: const Color(0xFF172033),
        elevation: 0,
        title: const Text('Flagged assignments'),
      ),
      body: _loading && _assignments.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _assignments.isEmpty
          ? Center(child: Text('Unable to load reviews: $_error'))
          : RefreshIndicator(
              onRefresh: _load,
              child: _assignments.isEmpty
                  ? ListView(
                      children: const [
                        SizedBox(height: 120),
                        Center(
                          child: Text('No flagged assignments need review.'),
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _assignments.length,
                      itemBuilder: (context, index) {
                        final assignment = _assignments[index];
                        final id = assignment['assignment_id'] as int;
                        final reasons = assignment['flag_reasons'] is List
                            ? (assignment['flag_reasons'] as List).join(', ')
                            : '';
                        return Card(
                          color: Colors.white,
                          child: ListTile(
                            title: Text(
                              '${assignment['name']} · ${assignment['task_type']}',
                            ),
                            subtitle: Text(
                              'Risk ${assignment['risk_score']}: $reasons',
                            ),
                            trailing: TextButton(
                              onPressed: _reviewingId == id
                                  ? null
                                  : () => _review(id),
                              child: _reviewingId == id
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text('Review'),
                            ),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}
