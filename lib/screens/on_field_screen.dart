import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:staff_attendance_mobile/services/api_service.dart';
import 'package:url_launcher/url_launcher.dart';

class OnFieldScreen extends StatefulWidget {
  const OnFieldScreen({super.key, this.apiService});

  final ApiService? apiService;

  @override
  State<OnFieldScreen> createState() => _OnFieldScreenState();
}

class _OnFieldScreenState extends State<OnFieldScreen> {
  late final ApiService _api = widget.apiService ?? ApiService();
  List<Map<String, dynamic>> _rows = const [];
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await _api.fetchOnField();
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _error = null;
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

  Future<void> _openMap(Map<String, dynamic> row) async {
    final latitude = row['latitude'];
    final longitude = row['longitude'];
    if (latitude == null || longitude == null) return;
    final uri = Uri.https('www.google.com', '/maps/search/', {
      'api': '1',
      'query': '$latitude,$longitude',
    });
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Unable to open the map.')),
        );
    }
  }

  String _startTime(Object? value) {
    final start = DateTime.tryParse(value?.toString() ?? '');
    return start == null
        ? 'Start time unavailable'
        : DateFormat('d MMM yyyy · h:mm a').format(start.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF8FAFC),
        foregroundColor: const Color(0xFF172033),
        elevation: 0,
        title: const Text('Currently on field'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _rows.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Unable to load on-field staff: $_error',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _load,
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: _rows.isEmpty
                  ? ListView(
                      children: const [
                        SizedBox(height: 120),
                        Center(child: Text('No staff are currently on field.')),
                      ],
                    )
                  : ListView(
                      padding: const EdgeInsets.all(12),
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
                          child: Text(
                            '${_rows.length} active ${_rows.length == 1 ? 'visit' : 'visits'}',
                            style: const TextStyle(
                              color: Color(0xFF64748B),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        ..._rows.map(_visitCard),
                      ],
                    ),
            ),
    );
  }

  Widget _visitCard(Map<String, dynamic> row) {
    final hasLocation =
        row['latitude'] != null && row['longitude'] != null;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CircleAvatar(
                  backgroundColor: Color(0xFFFFF1E6),
                  child: Icon(
                    Icons.person_pin_circle_outlined,
                    color: Color(0xFFFB923C),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row['name']?.toString() ?? 'Staff',
                        style: const TextStyle(
                          color: Color(0xFF172033),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        row['client_or_service_name']?.toString() ??
                            'Field Visit',
                        style: const TextStyle(
                          color: Color(0xFF334155),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _detail('Purpose', row['purpose']?.toString() ?? 'Not provided'),
            _detail('Started', _startTime(row['clock_in_at'])),
            const SizedBox(height: 8),
            if (hasLocation)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => _openMap(row),
                  icon: const Icon(Icons.map_outlined, size: 18),
                  label: const Text('View Location on Google Maps'),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF0E7490),
                    padding: EdgeInsets.zero,
                  ),
                ),
              )
            else
              const Text(
                'Location unavailable',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
              ),
          ],
        ),
      ),
    );
  }

  Widget _detail(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(color: Color(0xFF334155), fontSize: 13),
          ),
        ],
      ),
    );
  }
}
