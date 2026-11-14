import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:staff_attendance_mobile/services/api_service.dart';

class AiAssistantScreen extends StatefulWidget {
  const AiAssistantScreen({super.key, this.apiService});

  final ApiService? apiService;

  @override
  State<AiAssistantScreen> createState() => _AiAssistantScreenState();
}

class _AiAssistantScreenState extends State<AiAssistantScreen> {
  static const _accent = Color(0xFFFB923C);
  late final ApiService _api = widget.apiService ?? ApiService();
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final List<_ChatMessage> _messages = [];
  int _remainingQuota = 15;
  bool _sending = false;
  bool _disabled = false;

  static const _quickPrompts = <(String, String)>[
    (
      'My Performance & Earnings',
      'Summarize my attendance, daily work reports, and earnings for this month.',
    ),
    (
      'Schedule & Leave Status',
      'What does my assigned schedule say, what upcoming holidays are listed, and what is my leave request summary?',
    ),
    (
      'How to Lower My Risk Score',
      'Based only on my records, what actions could help improve my performance risk score?',
    ),
  ];

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadSavedQuota();
  }

  Future<void> _loadSavedQuota() async {
    final preferences = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final userId = preferences.getInt('auth_user_id');
    if (!mounted ||
        preferences.getString('ai_quota_day') != today ||
        userId == null ||
        preferences.getInt('ai_quota_user_id') != userId) {
      return;
    }
    setState(() {
      _remainingQuota = _intValue(
        preferences.getInt('ai_remaining_quota'),
        fallback: 15,
      ).clamp(0, 15).toInt();
    });
  }

  Future<void> _send([String? prompt]) async {
    final message = (prompt ?? _messageController.text).trim();
    if (message.isEmpty || _sending || _disabled || _remainingQuota == 0) {
      return;
    }
    _messageController.clear();
    setState(() {
      _messages.add(_ChatMessage(message, isAssistant: false));
      _sending = true;
    });
    _scrollToBottom();
    try {
      final response = await _api.askStaffAiAssistant(message);
      if (!mounted) return;
      final reply = response['reply']?.toString();
      if (reply == null || reply.trim().isEmpty) {
        throw Exception('The assistant returned an empty reply.');
      }
      setState(() {
        _remainingQuota = _intValue(
          response['remaining_quota'],
          fallback: _remainingQuota,
        ).clamp(0, 15).toInt();
        _messages.add(_ChatMessage(reply, isAssistant: true));
      });
    } on ApiRequestException catch (error) {
      if (!mounted) return;
      setState(() {
        if (error.remainingQuota != null) {
          _remainingQuota = error.remainingQuota!;
        }
        if (error.statusCode == 403) _disabled = true;
        if (error.statusCode == 429) _remainingQuota = 0;
        _messages.add(
          _ChatMessage(error.message, isAssistant: true, isError: true),
        );
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _messages.add(
          _ChatMessage(
            error.toString().replaceFirst('Exception: ', ''),
            isAssistant: true,
            isError: true,
          ),
        );
      });
    } finally {
      if (mounted) {
        setState(() => _sending = false);
        _scrollToBottom();
      }
    }
  }

  int _intValue(Object? value, {required int fallback}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
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
          'AI Work Assistant',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF1E6),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '$_remainingQuota/15 prompts left today',
                        style: const TextStyle(
                          color: Color(0xFF9A4D0A),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  if (_disabled) ...[
                    const SizedBox(height: 10),
                    const _DisabledNotice(),
                  ],
                  if (!_disabled) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'Quick help',
                      style: TextStyle(
                        color: Color(0xFF334155),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final (label, prompt) in _quickPrompts)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ActionChip(
                                onPressed: _sending || _remainingQuota == 0
                                    ? null
                                    : () => _send(prompt),
                                label: Text(label),
                                avatar: const Icon(
                                  Icons.auto_awesome,
                                  color: _accent,
                                  size: 17,
                                ),
                                backgroundColor: Colors.white,
                                side: const BorderSide(
                                  color: Color(0xFFE2E8F0),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: _messages.isEmpty
                  ? _welcome()
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                      itemCount: _messages.length + (_sending ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (_sending && index == _messages.length) {
                          return const _TypingIndicator();
                        }
                        return _messageBubble(_messages[index]);
                      },
                    ),
            ),
            _composer(),
          ],
        ),
      ),
    );
  }

  Widget _welcome() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.psychology_outlined, size: 48, color: _accent),
            const SizedBox(height: 12),
            const Text(
              'Your personal work assistant',
              style: TextStyle(
                color: Color(0xFF172033),
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Ask about your own attendance, schedule, leave, reports, or earnings.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.blueGrey.shade600, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _messageBubble(_ChatMessage message) {
    final isAssistant = message.isAssistant;
    final background = message.isError
        ? const Color(0xFFFFF1F2)
        : isAssistant
        ? Colors.white
        : const Color(0xFFFFF1E6);
    final foreground = message.isError
        ? const Color(0xFF9F1239)
        : const Color(0xFF253247);
    return Align(
      alignment: isAssistant ? Alignment.centerLeft : Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * .88,
        ),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: message.isError
                  ? const Color(0xFFFDA4AF)
                  : const Color(0xFFE7ECF2),
            ),
          ),
          child: isAssistant && !message.isError
              ? _structuredText(message.text, foreground)
              : Text(
                  message.text,
                  style: TextStyle(color: foreground, height: 1.4),
                ),
        ),
      ),
    );
  }

  Widget _structuredText(String markdown, Color color) {
    final children = <Widget>[];
    for (final rawLine in markdown.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('### ')) {
        children.add(
          Padding(
            padding: EdgeInsets.only(top: children.isEmpty ? 0 : 11, bottom: 4),
            child: Text(
              line.substring(4),
              style: const TextStyle(
                color: Color(0xFF172033),
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        );
      } else if (line.startsWith('- ')) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('• ', style: TextStyle(color: _accent, fontSize: 16)),
                Expanded(child: _inlineMarkdown(line.substring(2), color)),
              ],
            ),
          ),
        );
      } else {
        children.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: _inlineMarkdown(line, color),
          ),
        );
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  Widget _inlineMarkdown(String value, Color color) {
    final spans = <TextSpan>[];
    final pattern = RegExp(r'\*\*(.+?)\*\*');
    var cursor = 0;
    for (final match in pattern.allMatches(value)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: value.substring(cursor, match.start)));
      }
      spans.add(
        TextSpan(
          text: match.group(1),
          style: const TextStyle(
            color: Color(0xFF172033),
            fontWeight: FontWeight.w800,
          ),
        ),
      );
      cursor = match.end;
    }
    if (cursor < value.length) {
      spans.add(TextSpan(text: value.substring(cursor)));
    }
    return Text.rich(
      TextSpan(
        style: TextStyle(color: color, height: 1.4, fontSize: 13),
        children: spans.isEmpty ? [TextSpan(text: value)] : spans,
      ),
    );
  }

  Widget _composer() {
    final unavailable = _disabled || _remainingQuota == 0;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE7ECF2))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              minLines: 1,
              maxLines: 4,
              enabled: !unavailable && !_sending,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: unavailable
                    ? (_disabled
                          ? 'AI is not enabled for your organization'
                          : 'Daily prompt limit reached')
                    : 'Ask about your work or earnings…',
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (_) => _send(),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: unavailable || _sending ? null : () => _send(),
            style: IconButton.styleFrom(backgroundColor: _accent),
            icon: const Icon(Icons.send_rounded, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _ChatMessage {
  const _ChatMessage(
    this.text, {
    required this.isAssistant,
    this.isError = false,
  });

  final String text;
  final bool isAssistant;
  final bool isError;
}

class _DisabledNotice extends StatelessWidget {
  const _DisabledNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFED7AA)),
      ),
      child: const Text(
        "AI Assistant features are not enabled for your organization's subscription plan.",
        style: TextStyle(color: Color(0xFF9A3412), fontSize: 13),
      ),
    );
  }
}

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE7ECF2)),
        ),
        child: const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Color(0xFFFB923C),
          ),
        ),
      ),
    );
  }
}
