import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:staff_attendance_mobile/services/api_service.dart';

class PrivateChatScreen extends StatefulWidget {
  const PrivateChatScreen({
    required this.colleagueId,
    required this.colleagueName,
    this.colleagueRole,
    this.quotedMessage,
    this.apiService,
    super.key,
  });

  final int colleagueId;
  final String colleagueName;
  final String? colleagueRole;
  final String? quotedMessage;
  final ApiService? apiService;

  @override
  State<PrivateChatScreen> createState() => _PrivateChatScreenState();
}

class _PrivateChatScreenState extends State<PrivateChatScreen> {
  late final ApiService _api = widget.apiService ?? ApiService();
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  Timer? _pollTimer;
  int? _userId;
  String? _pendingQuote;
  bool _isLoading = true;
  bool _isRefreshing = false;
  bool _isSending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _pendingQuote = widget.quotedMessage;
    _loadUserId();
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      _loadMessages();
    });
  }

  Future<void> _loadUserId() async {
    final preferences = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _userId =
          preferences.getInt('auth_user_id') ??
          int.tryParse(preferences.getString('auth_user_id') ?? '');
    });
    await _loadMessages();
  }

  Future<void> _loadMessages() async {
    if (_isRefreshing) return;
    _isRefreshing = true;
    try {
      final result = await _api.fetchPrivateChat(widget.colleagueId);
      final rawMessages = result['messages'];
      if (!mounted) return;
      final shouldScroll =
          _messages.isEmpty ||
          (_scrollController.hasClients &&
              _scrollController.position.maxScrollExtent -
                      _scrollController.position.pixels <
                  80);
      setState(() {
        _isLoading = false;
        _error = null;
        _messages = rawMessages is List
            ? rawMessages
                  .whereType<Map>()
                  .map((item) => Map<String, dynamic>.from(item))
                  .toList()
            : [];
      });
      if (shouldScroll) _scrollToBottom();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = error.toString().replaceFirst(
          RegExp(r'^(Exception|ApiRequestException):\s*'),
          '',
        );
      });
    } finally {
      _isRefreshing = false;
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _isSending) return;
    setState(() => _isSending = true);
    try {
      final response = await _api.sendPrivateChatMessage(
        colleagueId: widget.colleagueId,
        message: text,
        quotedMessage: _pendingQuote,
      );
      final message = response['message'];
      if (!mounted) return;
      if (message is Map) {
        setState(() {
          _messages.add(Map<String, dynamic>.from(message));
          _pendingQuote = null;
        });
        _messageController.clear();
        _scrollToBottom();
      }
    } catch (error) {
      _showError(error.toString());
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _messageActions(Map<String, dynamic> message) async {
    if ((message['sender_id'] as num?)?.toInt() != _userId) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit Message'),
              onTap: () => Navigator.pop(context, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Delete Message'),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (action == 'edit') await _editMessage(message);
    if (action == 'delete') await _deleteMessage(message);
  }

  Future<void> _editMessage(Map<String, dynamic> message) async {
    final controller = TextEditingController(
      text: message['message']?.toString(),
    );
    final updated = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit message'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 2000,
          maxLines: 5,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (updated == null || updated.isEmpty) return;
    try {
      final result = await _api.updatePrivateChatMessage(
        messageId: (message['id'] as num).toInt(),
        message: updated,
      );
      final updatedMessage = result['message'];
      if (updatedMessage is Map && mounted) {
        setState(() {
          final index = _messages.indexWhere(
            (item) => item['id'] == message['id'],
          );
          if (index >= 0) {
            _messages[index] = Map<String, dynamic>.from(updatedMessage);
          }
        });
      }
    } catch (error) {
      _showError(error.toString());
    }
  }

  Future<void> _deleteMessage(Map<String, dynamic> message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete message?'),
        content: const Text('This message will be removed for both people.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _api.deletePrivateChatMessage((message['id'] as num).toInt());
      if (mounted) {
        setState(
          () => _messages.removeWhere((item) => item['id'] == message['id']),
        );
      }
    } catch (error) {
      _showError(error.toString());
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  String _timestamp(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    return date == null ? '' : DateFormat('dd MMM, HH:mm').format(date);
  }

  void _showError(String error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          error.replaceFirst(
            RegExp(r'^(Exception|ApiRequestException):\s*'),
            '',
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.colleagueName),
            if (widget.colleagueRole != null)
              Text(
                widget.colleagueRole!.toUpperCase(),
                style: Theme.of(context).textTheme.labelSmall,
              ),
          ],
        ),
      ),
      body: Column(
        children: [
          if (_pendingQuote != null && _pendingQuote!.isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7ED),
                border: Border.all(color: const Color(0xFFFED7AA)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.format_quote, color: Color(0xFFEA580C)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _pendingQuote!,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: () => setState(() => _pendingQuote = null),
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ],
              ),
            ),
          if (_error != null)
            MaterialBanner(
              content: Text(_error!),
              actions: [
                TextButton(
                  onPressed: _loadMessages,
                  child: const Text('Retry'),
                ),
              ],
            ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                ? const Center(child: Text('No messages yet. Send a reply.'))
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(14),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final item = _messages[index];
                      final own =
                          (item['sender_id'] as num?)?.toInt() == _userId;
                      return GestureDetector(
                        onLongPress: () => _messageActions(item),
                        onTap: own ? () => _messageActions(item) : null,
                        child: Align(
                          alignment: own
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                            constraints: BoxConstraints(
                              maxWidth: MediaQuery.sizeOf(context).width * .82,
                            ),
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: own
                                  ? const Color(0xFFFFF1E6)
                                  : Colors.white,
                              border: Border.all(
                                color: const Color(0xFFE2E8F0),
                              ),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (item['quoted_message'] != null)
                                  Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    padding: const EdgeInsets.only(left: 8),
                                    decoration: const BoxDecoration(
                                      border: Border(
                                        left: BorderSide(
                                          color: Color(0xFFFB923C),
                                          width: 2,
                                        ),
                                      ),
                                    ),
                                    child: Text(
                                      item['quoted_message'].toString(),
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: Colors.grey.shade700,
                                          ),
                                    ),
                                  ),
                                Text(item['message']?.toString() ?? ''),
                                const SizedBox(height: 6),
                                Text(
                                  '${_timestamp(item['created_at'])}'
                                  '${item['edited_at'] != null ? ' · (edited)' : ''}',
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: 2000,
                      decoration: const InputDecoration(
                        hintText: 'Write a private message',
                        counterText: '',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(22)),
                        ),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _isSending ? null : _sendMessage,
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFFFB923C),
                    ),
                    icon: _isSending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
