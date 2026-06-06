import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../theme/app_theme.dart';
import '../../services/api_service.dart';

class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key});
  @override State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  final _ctrl = TextEditingController();
  File? _screenshot;
  bool _checking = false;
  bool _submitting = false;
  _AiResult? _aiResult;
  bool _dismissed = false; // user dismissed AI suggestion and wants to submit anyway

  @override void dispose() { _ctrl.dispose(); super.dispose(); }

  Future<void> _checkWithAi() async {
    final text = _ctrl.text.trim();
    if (text.length < 10) return;
    setState(() { _checking = true; _aiResult = null; _dismissed = false; });
    try {
      final data = await AiApi.checkFeedback(text);
      setState(() => _aiResult = _AiResult(
        type:    data['type']    as String? ?? 'new',
        message: data['message'] as String? ?? '',
        howTo:   data['howTo']   as String?,
      ));
    } catch (_) {
      // AI check failed silently — user can still submit
    } finally {
      setState(() => _checking = false);
    }
  }

  Future<void> _pickScreenshot() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked != null) setState(() => _screenshot = File(picked.path));
  }

  Future<void> _submit() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _submitting = true);
    try {
      await FeedbackApi.submit(
        text: text,
        screenshot: _screenshot,
        aiCategory: _aiResult?.category,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Thanks! Your feedback has been submitted.')));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to submit: $e')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('Feedback & Suggestions')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Share your thoughts', style: TextStyle(
            fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.text)),
          const SizedBox(height: 6),
          const Text(
            'Bug report, feature request, or general feedback — we read everything.',
            style: TextStyle(color: AppColors.text2, fontSize: 13)),
          const SizedBox(height: 20),

          // Text input
          TextField(
            controller: _ctrl,
            maxLines: 5,
            minLines: 3,
            style: const TextStyle(color: AppColors.text),
            decoration: const InputDecoration(
              hintText: 'e.g. I wish the scoring sheet could export to PDF…',
              alignLabelWithHint: true,
            ),
            onChanged: (_) => setState(() { _aiResult = null; _dismissed = false; }),
          ),
          const SizedBox(height: 12),

          // Check with AI button
          if (!_checking && _aiResult == null && !_dismissed)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _ctrl.text.trim().length >= 10 ? _checkWithAi : null,
                icon: const Icon(Icons.auto_awesome, size: 16),
                label: const Text('Check with AI before submitting'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.accent,
                  side: const BorderSide(color: AppColors.accent),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),

          if (_checking)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Row(children: [
                SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2,
                    color: AppColors.accent)),
                SizedBox(width: 12),
                Text('Checking against existing features…',
                  style: TextStyle(color: AppColors.text2, fontSize: 13)),
              ]),
            ),

          // AI result card
          if (_aiResult != null && !_dismissed) ...[
            const SizedBox(height: 12),
            _AiResultCard(
              result: _aiResult!,
              onDismiss: () => setState(() => _dismissed = true),
            ),
          ],

          const SizedBox(height: 20),

          // Screenshot section
          const Text('ATTACH SCREENSHOT (OPTIONAL)', style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w700,
            color: AppColors.text2, letterSpacing: 1.2)),
          const SizedBox(height: 10),
          if (_screenshot != null) ...[
            Stack(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.file(_screenshot!, height: 180,
                  width: double.infinity, fit: BoxFit.cover),
              ),
              Positioned(top: 8, right: 8,
                child: GestureDetector(
                  onTap: () => setState(() => _screenshot = null),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.black54, shape: BoxShape.circle),
                    child: const Icon(Icons.close, color: Colors.white, size: 16),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 10),
          ],
          OutlinedButton.icon(
            onPressed: _pickScreenshot,
            icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
            label: Text(_screenshot == null ? 'Add screenshot' : 'Change screenshot'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.text2,
              side: const BorderSide(color: AppColors.border),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),

          const SizedBox(height: 32),

          // Submit
          SizedBox(
            width: double.infinity, height: 52,
            child: ElevatedButton(
              onPressed: (_submitting || _ctrl.text.trim().isEmpty ||
                  (_aiResult?.type == 'exists' && !_dismissed))
                  ? null
                  : _submit,
              child: _submitting
                  ? const SizedBox(width: 22, height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5,
                    color: AppColors.textOnAcc))
                  : const Text('Submit Feedback'),
            ),
          ),

          if (_aiResult?.type == 'exists' && !_dismissed)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Center(child: TextButton(
                onPressed: () => setState(() => _dismissed = true),
                child: const Text('Submit anyway',
                  style: TextStyle(color: AppColors.text2, fontSize: 13)),
              )),
            ),
        ]),
      ),
    );
  }
}

// ── AI result card ─────────────────────────────────────────────

class _AiResult {
  final String type;      // 'exists' | 'duplicate' | 'new'
  final String message;
  final String? howTo;

  const _AiResult({required this.type, required this.message, this.howTo});

  String? get category => type == 'new' ? null : type;
}

class _AiResultCard extends StatelessWidget {
  final _AiResult result;
  final VoidCallback onDismiss;
  const _AiResultCard({required this.result, required this.onDismiss});

  @override Widget build(BuildContext context) {
    Color bg, border, iconColor;
    IconData icon;
    switch (result.type) {
      case 'exists':
        bg = AppColors.accent.withOpacity(0.07);
        border = AppColors.accent.withOpacity(0.3);
        iconColor = AppColors.accent;
        icon = Icons.lightbulb_outline;
        break;
      case 'duplicate':
        bg = AppColors.ball.withOpacity(0.07);
        border = AppColors.ball.withOpacity(0.3);
        iconColor = AppColors.ball;
        icon = Icons.content_copy_outlined;
        break;
      default:
        bg = Colors.green.withOpacity(0.07);
        border = Colors.green.withOpacity(0.3);
        iconColor = Colors.green;
        icon = Icons.check_circle_outline;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: iconColor, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(
            result.type == 'exists' ? 'Feature already exists!'
                : result.type == 'duplicate' ? 'Similar suggestion found'
                : 'Looks like a new idea!',
            style: TextStyle(fontWeight: FontWeight.w800,
              color: iconColor, fontSize: 13),
          )),
          GestureDetector(
            onTap: onDismiss,
            child: Icon(Icons.close, color: iconColor.withOpacity(0.6), size: 16)),
        ]),
        const SizedBox(height: 8),
        Text(result.message, style: const TextStyle(
          color: AppColors.text, fontSize: 13, height: 1.4)),
        if (result.howTo != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.directions_outlined, size: 14, color: iconColor),
              const SizedBox(width: 6),
              Expanded(child: Text(result.howTo!, style: TextStyle(
                fontSize: 12, color: iconColor, fontWeight: FontWeight.w600,
                height: 1.4))),
            ]),
          ),
        ],
        if (result.type != 'new') ...[
          const SizedBox(height: 10),
          Text('You can still submit to add your voice →',
            style: TextStyle(fontSize: 11,
              color: iconColor.withOpacity(0.7))),
        ],
      ]),
    );
  }
}
