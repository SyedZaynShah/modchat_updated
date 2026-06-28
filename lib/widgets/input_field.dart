import 'dart:typed_data';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../theme/theme.dart';
import '../models/message_model.dart';
import '../services/firestore_service.dart';
import '../services/message_moderation_service.dart';
import '../services/media_picker_service.dart';
import '../screens/media/media_preview_screen.dart';

typedef SendText = Future<void> Function(String text);
typedef SendMedia =
    Future<void> Function(
      Uint8List bytes,
      String fileName,
      String contentType,
      MessageType type, {
      String? localPath,
      String? thumbnailPath,
      int? durationMs,
      String? caption,
      bool? viewOnce,
      Map<String, dynamic>? meta,
    });

typedef SendPoll = Future<void> Function(Map<String, dynamic> poll);

class InputField extends StatefulWidget {
  final SendText onSend;
  final SendMedia onSendMedia;
  final SendPoll? onSendPoll;
  final ValueChanged<bool>? onTypingChanged;
  final ValueChanged<String>? onTextChanged;
  final ValueChanged<bool>? onVoiceRecordingChanged;
  final bool sendDisabled;

  const InputField({
    super.key,
    required this.onSend,
    required this.onSendMedia,
    this.onSendPoll,
    this.onTypingChanged,
    this.onTextChanged,
    this.onVoiceRecordingChanged,
    this.sendDisabled = false,
  });

  @override
  State<InputField> createState() => _InputFieldState();
}

class _PollDraft {
  final String question;
  final List<String> options;
  final bool allowMultipleVotes;
  final bool allowVoteChange;
  final bool isAnonymous;

  const _PollDraft({
    required this.question,
    required this.options,
    required this.allowMultipleVotes,
    required this.allowVoteChange,
    required this.isAnonymous,
  });
}

class _PollComposerSheet extends StatefulWidget {
  const _PollComposerSheet();

  @override
  State<_PollComposerSheet> createState() => _PollComposerSheetState();
}

class _PollComposerSheetState extends State<_PollComposerSheet> {
  final _question = TextEditingController();
  final List<TextEditingController> _options = <TextEditingController>[
    TextEditingController(),
    TextEditingController(),
  ];

  bool _allowMultiple = false;
  bool _allowChange = true;
  bool _isAnonymous = false;

  @override
  void dispose() {
    _question.dispose();
    for (final c in _options) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0F0F0F) : Colors.white;

    return SafeArea(
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.18),
              blurRadius: 24,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 12,
          bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.black26,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Create Poll',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                ),
              ),
              const SizedBox(height: 12),
              _field(context, controller: _question, hint: 'Question'),
              const SizedBox(height: 12),
              ..._options.asMap().entries.map((e) {
                final i = e.key;
                final c = e.value;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: _field(
                          context,
                          controller: c,
                          hint: 'Option ${i + 1}',
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (_options.length > 2)
                        IconButton(
                          onPressed: () {
                            setState(() {
                              final removed = _options.removeAt(i);
                              removed.dispose();
                            });
                          },
                          icon: Icon(
                            Icons.close,
                            color: isDark ? Colors.white54 : Colors.black45,
                          ),
                        ),
                    ],
                  ),
                );
              }),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _options.length >= 8
                      ? null
                      : () {
                          setState(() {
                            _options.add(TextEditingController());
                          });
                        },
                  icon: const Icon(Icons.add),
                  label: const Text('Add option'),
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile.adaptive(
                value: _allowMultiple,
                onChanged: (v) => setState(() => _allowMultiple = v),
                title: const Text('Allow multiple answers'),
                contentPadding: EdgeInsets.zero,
              ),
              SwitchListTile.adaptive(
                value: _allowChange,
                onChanged: (v) => setState(() => _allowChange = v),
                title: const Text('Allow vote change'),
                contentPadding: EdgeInsets.zero,
              ),
              SwitchListTile.adaptive(
                value: _isAnonymous,
                onChanged: (v) => setState(() => _isAnonymous = v),
                title: const Text('Anonymous voting'),
                subtitle: const Text('Votes will not show voter identities'),
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF5865F2),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () {
                    final q = _question.text;
                    final opts = _options.map((e) => e.text).toList();
                    Navigator.of(context).pop(
                      _PollDraft(
                        question: q,
                        options: opts,
                        allowMultipleVotes: _allowMultiple,
                        allowVoteChange: _allowChange,
                        isAnonymous: _isAnonymous,
                      ),
                    );
                  },
                  child: const Text(
                    'Create Poll',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(
    BuildContext context, {
    required TextEditingController controller,
    required String hint,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fill = isDark ? Colors.white10 : Colors.black.withOpacity(0.04);

    return TextField(
      controller: controller,
      textInputAction: TextInputAction.next,
      style: TextStyle(color: isDark ? Colors.white : Colors.black87),
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: fill,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
      ),
    );
  }
}

class _InputFieldState extends State<InputField> {
  final _controller = TextEditingController();
  bool _hasText = false;

  Future<void> _sendQueue = Future<void>.value();

  bool _fsRecoveryInFlight = false;

  // Voice note state
  final AudioRecorder _rec = AudioRecorder();
  bool _recording = false;
  DateTime? _recStart;
  String? _recPath;
  StreamSubscription<Amplitude>? _ampSub;
  Timer? _tick;
  final List<double> _wave = <double>[]; // recent amps

  @override
  void dispose() {
    if (_recording) {
      widget.onVoiceRecordingChanged?.call(false);
    }
    _controller.dispose();
    _ampSub?.cancel();
    _tick?.cancel();
    _rec.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    await _showAttachmentSheet();
  }

  Future<void> _showAttachmentSheet() async {
    final size = MediaQuery.of(context).size;
    final maxSheetHeight = size.height * 0.55;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      transitionAnimationController: AnimationController(
        vsync: Navigator.of(context) as TickerProvider,
        duration: const Duration(milliseconds: 300),
      ),
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final isDark = theme.brightness == Brightness.dark;
        final sheetBg = isDark ? const Color(0xFF0F0F0F) : Colors.white;
        final dragHandleColor = isDark ? Colors.white24 : Colors.black26;

        final tiles = <_AttachmentTileData>[
          _AttachmentTileData(
            icon: Icons.photo_library_outlined,
            label: 'Gallery',
            color: const Color(0xFF5865F2), // Electric blue
            onTap: _openGalleryFlow,
          ),
          _AttachmentTileData(
            icon: Icons.photo_camera_outlined,
            label: 'Camera',
            color: const Color(0xFF8B5CF6), // Purple
            onTap: _openCameraFlow,
          ),
          _AttachmentTileData(
            icon: Icons.insert_drive_file_outlined,
            label: 'Document',
            color: const Color(0xFFF59E0B), // Orange
            onTap: _openDocumentFlow,
          ),
          _AttachmentTileData(
            icon: Icons.audiotrack_outlined,
            label: 'Audio',
            color: const Color(0xFF10B981), // Green
            onTap: _openAudioFlow,
          ),
          _AttachmentTileData(
            icon: Icons.location_on_outlined,
            label: 'Location',
            color: const Color(0xFFEF4444), // Red
            onTap: () => _stubFeature('Location (coming soon)'),
          ),
          _AttachmentTileData(
            icon: Icons.person_outline,
            label: 'Contact',
            color: const Color(0xFF14B8A6), // Teal
            onTap: () => _stubFeature('Contact (coming soon)'),
          ),
          _AttachmentTileData(
            icon: Icons.poll_outlined,
            label: 'Poll',
            color: const Color(0xFF6366F1), // Indigo
            onTap: _openPollFlow,
          ),
        ];

        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxSheetHeight),
            child: Container(
              decoration: BoxDecoration(
                color: sheetBg,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 20,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Drag handle
                  Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 8),
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: dragHandleColor,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  // Header
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Text(
                          'Share',
                          style: TextStyle(
                            color: isDark
                                ? Colors.white
                                : const Color(0xFF1A1A2E),
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, indent: 20, endIndent: 20),
                  // Scrollable content for small screens
                  Flexible(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 20,
                      ),
                      child: GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 4,
                              mainAxisSpacing: 16,
                              crossAxisSpacing: 12,
                              childAspectRatio: 0.85,
                            ),
                        itemCount: tiles.length,
                        itemBuilder: (context, index) {
                          final tile = tiles[index];
                          return _PremiumAttachmentTile(
                            icon: tile.icon,
                            label: tile.label,
                            color: tile.color,
                            isDark: isDark,
                            onTap: () {
                              Navigator.of(ctx).pop();
                              tile.onTap();
                            },
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _stubFeature(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _openPollFlow() async {
    if (widget.onSendPoll == null) {
      _stubFeature('Poll (coming soon)');
      return;
    }

    final res = await showModalBottomSheet<_PollDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return const _PollComposerSheet();
      },
    );

    if (!mounted || res == null) return;

    final question = res.question.trim();
    final options = res.options
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);

    if (question.isEmpty || options.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a question and 2 options')),
      );
      return;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final poll = <String, dynamic>{
      'question': question,
      'options': options
          .asMap()
          .entries
          .map(
            (e) => {
              'id': 'opt_${now}_${e.key}',
              'text': e.value,
              'votes': <String>[],
              'voteCount': 0,
            },
          )
          .toList(growable: false),
      'allowMultipleVotes': res.allowMultipleVotes,
      'allowVoteChange': res.allowVoteChange,
      'isAnonymous': res.isAnonymous,
      'totalVotes': 0,
    };

    await widget.onSendPoll!(poll);
  }

  Future<void> _openGalleryFlow() async {
    final items = await MediaPickerService.instance.pickGalleryMulti(limit: 30);
    if (!mounted || items.isEmpty) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MediaPreviewScreen(
          items: items,
          onSendMedia: widget.onSendMedia,
          onSendText: widget.onSend,
        ),
      ),
    );
  }

  Future<void> _openCameraFlow() async {
    final items = await MediaPickerService.instance.captureCamera(video: false);
    if (!mounted || items.isEmpty) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MediaPreviewScreen(
          items: items,
          onSendMedia: widget.onSendMedia,
          onSendText: widget.onSend,
        ),
      ),
    );
  }

  Future<void> _openDocumentFlow() async {
    final items = await MediaPickerService.instance.pickDocuments();
    if (!mounted || items.isEmpty) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MediaPreviewScreen(
          items: items,
          onSendMedia: widget.onSendMedia,
          onSendText: widget.onSend,
        ),
      ),
    );
  }

  Future<void> _openAudioFlow() async {
    final items = await MediaPickerService.instance.pickAudio();
    if (!mounted || items.isEmpty) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MediaPreviewScreen(
          items: items,
          onSendMedia: widget.onSendMedia,
          onSendText: widget.onSend,
        ),
      ),
    );
  }

  // ===== Voice note logic =====
  Future<void> _startRec() async {
    if (kIsWeb) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Voice recording is not supported on Web'),
        ),
      );
      return;
    }
    final status = await Permission.microphone.request();
    if (!status.isGranted) return;
    try {
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.wav';
      _recStart = DateTime.now();
      await _rec.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 44100,
          numChannels: 1,
        ),
        path: path,
      );
      _recPath = path;
      _wave.clear();
      _ampSub?.cancel();
      _ampSub = _rec
          .onAmplitudeChanged(const Duration(milliseconds: 80))
          .listen((a) {
            final cur = a.current; // dB [-160..0]
            final norm = ((cur + 60.0) / 60.0).clamp(0.0, 1.0).toDouble();
            if (!mounted) return;
            setState(() {
              _wave.add(norm);
              if (_wave.length > 32) _wave.removeAt(0);
            });
          });
      _tick?.cancel();
      _tick = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (mounted) setState(() {});
      });
      setState(() {
        _recording = true;
      });
      widget.onVoiceRecordingChanged?.call(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Unable to start recording: $e')));
    }
  }

  Future<void> _cancelRec() async {
    try {
      await _rec.stop();
    } catch (_) {}
    _ampSub?.cancel();
    _tick?.cancel();
    if (_recPath != null) {
      try {
        File(_recPath!).deleteSync();
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _recording = false;
      _recPath = null;
    });
    widget.onVoiceRecordingChanged?.call(false);
  }

  Future<void> _finishRecSend() async {
    final path = await _rec.stop();
    _ampSub?.cancel();
    _tick?.cancel();
    final duration = DateTime.now()
        .difference(_recStart ?? DateTime.now())
        .inMilliseconds;
    if (!mounted) return;
    setState(() {
      _recording = false;
    });
    widget.onVoiceRecordingChanged?.call(false);
    if (path == null) return;
    final bytes = await File(path).readAsBytes();
    await widget.onSendMedia(
      bytes,
      'voice_${DateTime.now().millisecondsSinceEpoch}.wav',
      'audio/wav',
      MessageType.audio,
      localPath: path,
      durationMs: duration,
    );
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final draft = text;
    _controller.clear();
    if (_hasText) {
      setState(() => _hasText = false);
      widget.onTypingChanged?.call(false);
      widget.onTextChanged?.call('');
    }

    _sendQueue = _sendQueue.catchError((_) {}).then((_) async {
      try {
        await widget.onSend(text);
      } on MessageBlockedException {
        // Message was blocked by AI moderation in a group. The group screen
        // already showed a friendly explanation — just restore the draft so
        // the user can edit and retry, and suppress the generic error below.
        if (!mounted) return;
        if (_controller.text.trim().isEmpty) {
          _controller.text = draft;
          _controller.selection = TextSelection.fromPosition(
            TextPosition(offset: _controller.text.length),
          );
          if (!_hasText) {
            setState(() => _hasText = true);
            widget.onTypingChanged?.call(true);
            widget.onTextChanged?.call(_controller.text);
          }
        }
        return;
      } catch (e) {
        final msg = e.toString();

        if (kIsWeb &&
            !_fsRecoveryInFlight &&
            (msg.contains('INTERNAL ASSERTION FAILED') ||
                msg.contains('Unexpected state'))) {
          _fsRecoveryInFlight = true;
          try {
            await FirestoreService.resetPersistenceAndNetwork();
          } catch (_) {
            // ignore
          } finally {
            _fsRecoveryInFlight = false;
          }
        }

        if (!mounted) return;
        if (_controller.text.trim().isEmpty) {
          _controller.text = draft;
          _controller.selection = TextSelection.fromPosition(
            TextPosition(offset: _controller.text.length),
          );
          if (!_hasText) {
            setState(() => _hasText = true);
            widget.onTypingChanged?.call(true);
            widget.onTextChanged?.call(_controller.text);
          }
        }
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Send failed: $e')));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final inputBg = isDark ? const Color(0xFF0F0F0F) : AppColors.inputBgLight;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      height: 48,
      decoration: BoxDecoration(
        color: inputBg,
        borderRadius: BorderRadius.circular(24),
      ),
      child: _recording ? _buildRecordingUI() : _buildNormalUI(),
    );
  }

  Widget _buildNormalUI() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : AppColors.textLightPrimary;
    final hintColor = isDark
        ? const Color(0xFF8A8A8A)
        : AppColors.textLightSecondary;
    final iconColor = isDark
        ? const Color(0xFF9A9A9A)
        : AppColors.textLightSecondary;
    return Row(
      children: [
        IconButton(
          onPressed: _pickFile,
          icon: Icon(Icons.attach_file, color: iconColor, size: 20),
        ),
        Expanded(
          child: TextField(
            controller: _controller,
            minLines: 1,
            maxLines: 4,
            onChanged: (v) {
              widget.onTextChanged?.call(v);
              final has = v.trim().isNotEmpty;
              if (has != _hasText) {
                setState(() => _hasText = has);
                widget.onTypingChanged?.call(has);
              }
            },
            style: TextStyle(color: textColor, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Message',
              hintStyle: TextStyle(color: hintColor, fontSize: 14),
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 10,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        _buildActionButton(),
      ],
    );
  }

  Widget _buildRecordingUI() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : AppColors.textLightPrimary;
    final actionBg = Theme.of(context).colorScheme.primary;
    final actionFg = Theme.of(context).colorScheme.onPrimary;
    return Row(
      children: [
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _Waveform(values: _wave),
              const SizedBox(width: 10),
              Text(
                _fmtElapsed(),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: textColor,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: _cancelRec,
          icon: const Icon(
            Icons.delete_outline,
            color: Color(0xFF5865F2),
            size: 20,
          ),
        ),
        const SizedBox(width: 2),
        GestureDetector(
          onTap: _finishRecSend,
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: actionBg, shape: BoxShape.circle),
            child: Icon(Icons.send, color: actionFg, size: 20),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton() {
    final actionBg = Theme.of(context).colorScheme.primary;
    final actionFg = Theme.of(context).colorScheme.onPrimary;
    return GestureDetector(
      onTap: () {
        if (widget.sendDisabled) return;
        if (_hasText) {
          _send();
          return;
        }
        if (!_recording) {
          _startRec();
        }
      },
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(color: actionBg, shape: BoxShape.circle),
        child: Icon(
          _hasText ? Icons.send : Icons.mic,
          color: widget.sendDisabled ? const Color(0xFF5A5A5A) : actionFg,
          size: 20,
        ),
      ),
    );
  }

  String _fmtElapsed() {
    final d = _recStart == null
        ? Duration.zero
        : DateTime.now().difference(_recStart!);
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

class _AttachmentTileData {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _AttachmentTileData({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
}

class _PremiumAttachmentTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool isDark;
  final VoidCallback onTap;

  const _PremiumAttachmentTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        splashColor: color.withOpacity(0.2),
        highlightColor: color.withOpacity(0.1),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: ClipRect(
            child: Column(
              mainAxisSize: MainAxisSize.max,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: color.withOpacity(isDark ? 0.2 : 0.12),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: color.withOpacity(isDark ? 0.3 : 0.2),
                      width: 1,
                    ),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                const SizedBox(height: 4),
                Flexible(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Waveform extends StatelessWidget {
  final List<double> values; // 0..1
  const _Waveform({required this.values});

  @override
  Widget build(BuildContext context) {
    final v = values.isEmpty
        ? List<double>.filled(16, 0.1)
        : values.takeLast(24);
    return SizedBox(
      height: 26,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: v.map((e) {
          final h = 6 + (e * 20);
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1.5),
            child: Container(
              width: 3,
              height: h,
              decoration: BoxDecoration(
                color: AppColors.navy,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

extension on List<double> {
  List<double> takeLast(int n) {
    if (length <= n) return List<double>.from(this);
    return sublist(length - n);
  }
}
