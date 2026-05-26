import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../config.dart' as config;
import '../../services/auth_service.dart';

// ─── Models ──────────────────────────────────────────────────────────────────

class _Message {
  final String role; // 'user' | 'assistant'
  final String content;
  final bool isEscalated;
  _Message({required this.role, required this.content, this.isEscalated = false});
}

// ─── Support Chat Screen ──────────────────────────────────────────────────────

class SupportChatScreen extends StatefulWidget {
  const SupportChatScreen({super.key});

  @override
  State<SupportChatScreen> createState() => _SupportChatScreenState();
}

class _SupportChatScreenState extends State<SupportChatScreen> {
  final _messages = <_Message>[];
  final _controller = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool _loading = false;
  bool _escalated = false;

  static const _welcomeMessage = _Message(
    role: 'assistant',
    content: "Hi! I'm the CricScore support assistant 🏏\n\nI can help with scoring, tournaments, teams, video clips, and more. What can I help you with?",
  );

  @override
  void initState() {
    super.initState();
    _messages.add(_welcomeMessage);
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _loading) return;

    setState(() {
      _messages.add(_Message(role: 'user', content: text));
      _loading = true;
    });
    _controller.clear();
    _scrollToBottom();

    try {
      final token = await AuthService.getIdToken();
      final user  = await AuthService.getCachedUser();

      // Build history for Claude (exclude welcome message)
      final history = _messages
          .where((m) => m != _welcomeMessage)
          .map((m) => {'role': m.role, 'content': m.content})
          .toList();

      final res = await http.post(
        Uri.parse('${config.apiBase}/support/chat'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'message': text,
          'history': history.length > 1 ? history.sublist(0, history.length - 1) : [],
          'userId':     user?.sub ?? '',
          'userEmail':  user?.email ?? '',
          'appVersion': '1.0.4',
        }),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final reply      = data['reply'] as String? ?? 'Sorry, I couldn\'t process that.';
        final isEscalated = data['isEscalated'] as bool? ?? false;

        setState(() {
          _messages.add(_Message(
            role: 'assistant',
            content: reply,
            isEscalated: isEscalated,
          ));
          if (isEscalated) _escalated = true;
        });
      } else {
        _addError();
      }
    } catch (_) {
      _addError();
    } finally {
      setState(() => _loading = false);
      _scrollToBottom();
    }
  }

  void _addError() {
    setState(() {
      _messages.add(const _Message(
        role: 'assistant',
        content: "Sorry, I'm having trouble connecting. Please try again or email bellarykirankumar@gmail.com directly.",
      ));
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs    = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: const Center(child: Text('🏏', style: TextStyle(fontSize: 16))),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('CricScore Support', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                Text('AI assistant · usually instant',
                    style: TextStyle(fontSize: 11, color: cs.onSurface.withOpacity(0.6))),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.email_outlined),
            tooltip: 'Email support',
            onPressed: () => _showEmailDialog(context),
          ),
        ],
      ),
      body: Column(
        children: [
          // Escalated banner
          if (_escalated)
            Container(
              width: double.infinity,
              color: cs.tertiaryContainer,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Icon(Icons.check_circle_outline, size: 16, color: cs.onTertiaryContainer),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "Your issue has been flagged to our team. We'll follow up at your registered email.",
                      style: TextStyle(fontSize: 12, color: cs.onTertiaryContainer),
                    ),
                  ),
                ],
              ),
            ),

          // Messages list
          Expanded(
            child: ListView.builder(
              controller: _scrollCtrl,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              itemCount: _messages.length + (_loading ? 1 : 0),
              itemBuilder: (ctx, i) {
                if (i == _messages.length) return _buildTypingIndicator(cs);
                return _buildMessage(_messages[i], cs);
              },
            ),
          ),

          // Input bar
          _buildInputBar(cs),
        ],
      ),
    );
  }

  Widget _buildMessage(_Message msg, ColorScheme cs) {
    final isUser = msg.role == 'user';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              radius: 14,
              backgroundColor: cs.primaryContainer,
              child: const Text('🏏', style: TextStyle(fontSize: 12)),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isUser ? cs.primary : cs.surfaceContainerHigh,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isUser ? 18 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 18),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    msg.content,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.45,
                      color: isUser ? cs.onPrimary : cs.onSurface,
                    ),
                  ),
                  if (msg.isEscalated) ...[
                    const SizedBox(height: 6),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.support_agent, size: 12, color: cs.onSurface.withOpacity(0.5)),
                        const SizedBox(width: 4),
                        Text('Flagged to team',
                            style: TextStyle(fontSize: 11, color: cs.onSurface.withOpacity(0.5))),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (isUser) const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _buildTypingIndicator(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: cs.primaryContainer,
            child: const Text('🏏', style: TextStyle(fontSize: 12)),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHigh,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(18),
                topRight: Radius.circular(18),
                bottomRight: Radius.circular(18),
                bottomLeft: Radius.circular(4),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (i) => _Dot(delay: i * 200)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar(ColorScheme cs) {
    return Container(
      padding: EdgeInsets.fromLTRB(12, 8, 12, MediaQuery.of(context).padding.bottom + 8),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(top: BorderSide(color: cs.outlineVariant)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              minLines: 1,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'Ask a question...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: cs.surfaceContainerHigh,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              onSubmitted: (_) => _send(),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: _loading ? null : _send,
            style: FilledButton.styleFrom(
              shape: const CircleBorder(),
              padding: const EdgeInsets.all(14),
            ),
            child: const Icon(Icons.send_rounded, size: 20),
          ),
        ],
      ),
    );
  }

  void _showEmailDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Email Support'),
        content: const Text(
          'For urgent issues or anything the assistant can\'t resolve, email us directly:\n\nbellarykirankumar@gmail.com',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }
}

// ─── Animated typing dot ─────────────────────────────────────────────────────

class _Dot extends StatefulWidget {
  final int delay;
  const _Dot({required this.delay});
  @override
  State<_Dot> createState() => _DotState();
}

class _DotState extends State<_Dot> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600))
      ..repeat(reverse: true);
    _anim = Tween(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        width: 7, height: 7,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Theme.of(context).colorScheme.onSurface.withOpacity(_anim.value),
        ),
      ),
    );
  }
}
