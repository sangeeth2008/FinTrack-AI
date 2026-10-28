import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import '../../../app/motion/motion.dart';
import '../../../app/theme/luxe_tokens.dart';
import '../../../core/db/models.dart';
import '../../../core/gemini/gemini_service.dart';
import '../../../core/state/fintrack_controller.dart';
import '../../../shared/widgets/animated_amount.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/gradient_button.dart';
import '../../splits/domain/split_calculator.dart';
import '../domain/csv_statement_parser.dart';
import '../domain/sms_regex_parser.dart';

enum CaptureTab { manual, screenshot, voice, smsPaste, statement }

class MultimodalCaptureSheet extends ConsumerStatefulWidget {
  final CaptureTab initialTab;
  final String? initialSharedImagePath;
  final String? initialSharedText;
  final String? initialSharedPdfPath;

  const MultimodalCaptureSheet({
    super.key,
    this.initialTab = CaptureTab.manual,
    this.initialSharedImagePath,
    this.initialSharedText,
    this.initialSharedPdfPath,
  });

  @override
  ConsumerState<MultimodalCaptureSheet> createState() =>
      _MultimodalCaptureSheetState();
}

class _MultimodalCaptureSheetState
    extends ConsumerState<MultimodalCaptureSheet> {
  late CaptureTab _activeTab;

  // Manual entry fields
  TxnType _manualType = TxnType.debit;
  final _amountCtrl = TextEditingController();
  final _titleCtrl = TextEditingController();
  final _counterpartyCtrl = TextEditingController();
  final _friendsCtrl = TextEditingController();
  String _selectedCategoryId = 'cat_food';
  String _selectedAccountId = 'acc_upi_primary';
  PaymentMode _selectedPaymentMode = PaymentMode.upi;
  final Set<String> _selectedTags = {};
  bool _splitEnabled = false;
  final SplitMode _splitMode = SplitMode.equal;

  // Multimodal parsing state
  bool _isBusy = false;
  String? _statusMessage;
  String? _errorMessage;
  Uint8List? _selectedImageBytes;
  List<ParsedTransactionDraft> _parsedDrafts = [];
  bool _showInlineKeyEditor = false;
  final _inlineApiKeyCtrl = TextEditingController();

  // SMS / Log paste controller
  final _smsTextCtrl = TextEditingController();

  // Voice recording state
  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _isRecording = false;
  String? _recordedFilePath;
  final _voiceTranscriptFallbackCtrl = TextEditingController();

  static const _presetTags = [
    '#ProjectMARK',
    '#RoboticsLab',
    '#CollegeMess',
    '#Hackathon',
    '#Personal',
  ];

  @override
  void initState() {
    super.initState();
    _activeTab = widget.initialTab;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.initialSharedImagePath != null) {
        _loadSharedImageFile(widget.initialSharedImagePath!);
      } else if (widget.initialSharedText != null) {
        setState(() {
          _activeTab = CaptureTab.smsPaste;
          _smsTextCtrl.text = widget.initialSharedText!;
        });
        _parseSmsOrLogLocally();
      } else if (widget.initialSharedPdfPath != null) {
        setState(() => _activeTab = CaptureTab.statement);
        _loadSharedPdfFile(widget.initialSharedPdfPath!);
      }
    });
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _titleCtrl.dispose();
    _counterpartyCtrl.dispose();
    _friendsCtrl.dispose();
    _smsTextCtrl.dispose();
    _voiceTranscriptFallbackCtrl.dispose();
    _inlineApiKeyCtrl.dispose();
    _audioRecorder.dispose();
    super.dispose();
  }

  Future<void> _saveInlineApiKeyAndRetry() async {
    final key = _inlineApiKeyCtrl.text
        .trim()
        .replaceAll('"', '')
        .replaceAll("'", '');
    if (key.isEmpty) {
      setState(() => _errorMessage = 'Please paste a valid Gemini API key.');
      return;
    }
    await ref.read(finTrackControllerProvider.notifier).saveGeminiApiKey(key);
    _inlineApiKeyCtrl.clear();
    LuxeHaptics.medium();
    setState(() {
      _showInlineKeyEditor = false;
      _errorMessage = null;
      _statusMessage = 'Gemini API key saved! Ready to analyze.';
    });
    if (_activeTab == CaptureTab.screenshot && _selectedImageBytes != null) {
      await _analyzeScreenshotBytes(_selectedImageBytes!);
    }
  }

  int get _enteredManualPaise {
    final val = double.tryParse(_amountCtrl.text.replaceAll(',', '').trim());
    if (val == null || val <= 0) return 0;
    return (val * 100).round();
  }

  void _bumpAmount(int addRupees) {
    final current =
        double.tryParse(_amountCtrl.text.replaceAll(',', '').trim()) ?? 0;
    final next = current + addRupees;
    setState(() {
      _amountCtrl.text = next.toStringAsFixed(next % 1 == 0 ? 0 : 2);
    });
  }

  Future<void> _submitManualEntry() async {
    final paise = _enteredManualPaise;
    if (paise <= 0) {
      setState(() => _errorMessage = 'Enter a valid amount greater than ₹0');
      return;
    }

    final title = _titleCtrl.text.trim().isEmpty
        ? (_manualType == TxnType.credit ? 'Credited Funds' : 'Quick Expense')
        : _titleCtrl.text.trim();
    final party = _counterpartyCtrl.text.trim().isEmpty
        ? title
        : _counterpartyCtrl.text.trim();

    List<ComputedSplitShare> computedSplits = const [];
    if (_splitEnabled && _manualType == TxnType.debit) {
      final friendNames = _friendsCtrl.text
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (friendNames.isNotEmpty) {
        final pct = 100.0 / (friendNames.length + 1);
        final eachExact = paise ~/ (friendNames.length + 1);
        computedSplits = SplitCalculator.calculate(
          totalPaise: paise,
          mode: _splitMode,
          friends: friendNames
              .map(
                (n) => FriendSplitInput(
                  name: n,
                  exactPaise: eachExact,
                  percentage: pct,
                ),
              )
              .toList(),
        );
      }
    }

    await ref.read(finTrackControllerProvider.notifier).addTransaction(
          amountPaise: paise,
          type: _manualType,
          title: title,
          counterparty: party,
          categoryId: _selectedCategoryId,
          accountId: _selectedAccountId,
          paymentMode: _selectedPaymentMode,
          tags: _selectedTags.toList(),
          friendSplits: computedSplits,
        );

    if (mounted) {
      LuxeHaptics.medium();
      Navigator.of(context).pop();
    }
  }

  Future<void> _loadSharedImageFile(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      setState(() {
        _activeTab = CaptureTab.screenshot;
        _selectedImageBytes = bytes;
      });
      await _analyzeScreenshotBytes(bytes);
    } catch (e) {
      setState(() => _errorMessage = 'Could not read shared screenshot: $e');
    }
  }

  Future<void> _loadSharedPdfFile(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      await _analyzePdfBytes(bytes, p.basename(path));
    } catch (e) {
      setState(() => _errorMessage = 'Could not read shared PDF: $e');
    }
  }

  Future<void> _pickAndAnalyzeScreenshot(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      setState(() {
        _selectedImageBytes = bytes;
        _errorMessage = null;
      });
      await _analyzeScreenshotBytes(bytes);
    } catch (e) {
      setState(() => _errorMessage = 'Failed to pick screenshot: $e');
    }
  }

  Future<void> _analyzeScreenshotBytes(Uint8List bytes) async {
    final mime = GeminiService.detectImageMimeType(bytes);
    setState(() {
      _isBusy = true;
      _errorMessage = null;
      _statusMessage =
          'Gemini 3.8 Flash Vision scanning UPI screenshot ($mime) for amount, date & UTR…';
    });
    try {
      final drafts = await ref
          .read(geminiServiceProvider)
          .parsePaymentScreenshot(bytes, mimeType: mime);
      setState(() {
        _parsedDrafts = drafts;
        _isBusy = false;
        _statusMessage = drafts.isEmpty
            ? 'No transactions found in screenshot.'
            : 'Extracted ${drafts.length} transaction(s)! Review and tap Import.';
      });
    } catch (e) {
      setState(() {
        _isBusy = false;
        _statusMessage = null;
        _errorMessage = e.toString().replaceAll('Bad state: ', '');
      });
    }
  }

  Future<void> _toggleVoiceRecording() async {
    if (_isRecording) {
      final path = await _audioRecorder.stop();
      setState(() {
        _isRecording = false;
        _recordedFilePath = path;
      });
      if (path != null) {
        final bytes = await File(path).readAsBytes();
        setState(() {
          _isBusy = true;
          _errorMessage = null;
          _statusMessage =
              'Sending audio to Gemini 3.8 Flash for expense & split extraction…';
        });
        try {
          final drafts = await ref
              .read(geminiServiceProvider)
              .parseVoiceNote(bytes);
          setState(() {
            _parsedDrafts = drafts;
            _isBusy = false;
            _statusMessage = 'Extracted ${drafts.length} voice entry item(s)!';
          });
        } catch (e) {
          setState(() {
            _isBusy = false;
            _errorMessage = e.toString().replaceAll('Bad state: ', '');
          });
        }
      }
      return;
    }

    try {
      final hasPerm = await _audioRecorder.hasPermission();
      if (!hasPerm) {
        setState(() {
          _errorMessage =
              'Microphone permission denied. You can also type your voice note below.';
        });
        return;
      }
      final tempDir = await getTemporaryDirectory();
      final outPath = p.join(
        tempDir.path,
        'voice_${DateTime.now().millisecondsSinceEpoch}.m4a',
      );
      await _audioRecorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 96000),
        path: outPath,
      );
      setState(() {
        _isRecording = true;
        _errorMessage = null;
        _statusMessage =
            'Listening… Say e.g. "Spent 150 rupees on auto rickshaw with Sravan"';
      });
    } catch (e) {
      setState(() {
        _errorMessage =
            'Audio recorder unavailable on this device ($e). Use quick natural-language input below!';
      });
    }
  }

  Future<void> _parseVoiceNoteTextSimulation() async {
    final text = _voiceTranscriptFallbackCtrl.text.trim();
    if (text.isEmpty) return;

    // Try local natural-language regex + Gemini if available
    final hasKey = ref.read(finTrackControllerProvider).hasGeminiKey;
    if (hasKey) {
      setState(() {
        _isBusy = true;
        _errorMessage = null;
        _statusMessage = 'Gemini 3.8 Flash extracting voice note intent…';
      });
      try {
        final drafts = await ref
            .read(geminiServiceProvider)
            .parseTextTransactions(text, source: TxnSource.voice);
        setState(() {
          _parsedDrafts = drafts;
          _isBusy = false;
          _statusMessage = 'Extracted ${drafts.length} item(s)!';
        });
        return;
      } catch (_) {
        setState(() => _isBusy = false);
      }
    }

    // Fast offline natural language parser for e.g. "Spent 150 rupees on auto with Sravan"
    final numMatch = RegExp(r'(\d+(?:\.\d{1,2})?)').firstMatch(text);
    if (numMatch == null) {
      setState(() => _errorMessage = 'Could not detect an amount in note.');
      return;
    }
    final rupees = double.parse(numMatch.group(1)!);
    final isCredit = RegExp(
      r'\b(received|credited|got|salary|stipend)\b',
      caseSensitive: false,
    ).hasMatch(text);
    final type = isCredit ? TxnType.credit : TxnType.debit;

    final withMatch = RegExp(
      r'\bwith\s+([A-Za-z][A-Za-z\s,and]+)$',
      caseSensitive: false,
    ).firstMatch(text);
    final friends = <String>[];
    if (withMatch != null) {
      friends.addAll(
        withMatch
            .group(1)!
            .split(RegExp(r',|\band\b'))
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty),
      );
    }

    final catId = SmsRegexParser.inferCategoryId(text: text, type: type);
    setState(() {
      _parsedDrafts = [
        ParsedTransactionDraft(
          title: text.length > 34 ? '${text.substring(0, 34)}…' : text,
          amountPaise: (rupees * 100).round(),
          type: type,
          categoryId: catId,
          occurredAt: DateTime.now(),
          paymentMode: PaymentMode.upi,
          counterparty: text,
          splitFriends: friends,
          source: TxnSource.voice,
        ),
      ];
      _statusMessage = 'Extracted voice note item!';
    });
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      setState(() => _errorMessage = 'Clipboard is empty.');
      return;
    }
    setState(() {
      _smsTextCtrl.text = text;
      _errorMessage = null;
    });
    await _parseSmsOrLogLocally();
  }

  Future<void> _parseSmsOrLogLocally() async {
    final text = _smsTextCtrl.text.trim();
    if (text.isEmpty) return;

    final localMatches = SmsRegexParser.parseTextBlock(text);
    if (localMatches.isNotEmpty) {
      setState(() {
        _parsedDrafts = localMatches;
        _errorMessage = null;
        _statusMessage =
            'Instant Regex Engine extracted ${localMatches.length} transaction(s)!';
      });
      return;
    }

    // Fallback to Gemini AI
    await _parseSmsOrLogWithGemini();
  }

  Future<void> _parseSmsOrLogWithGemini() async {
    final text = _smsTextCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _isBusy = true;
      _errorMessage = null;
      _statusMessage =
          'Gemini 3.8 Flash parsing transaction details & dates…';
    });
    try {
      final drafts = await ref
          .read(geminiServiceProvider)
          .parseTextTransactions(text, source: TxnSource.sms);
      setState(() {
        _parsedDrafts = drafts;
        _isBusy = false;
        _statusMessage =
            'Gemini AI extracted ${drafts.length} transaction(s)!';
      });
    } catch (e) {
      setState(() {
        _isBusy = false;
        _errorMessage = e.toString().replaceAll('Bad state: ', '');
      });
    }
  }

  Future<void> _pickAndParseStatementFile() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'pdf', 'txt'],
      );
      if (files.isEmpty) return;
      final file = files.first;
      final ext = (file.extension ?? '').toLowerCase();
      final bytes = file.path != null
          ? await File(file.path!).readAsBytes()
          : null;

      if (bytes == null) {
        setState(() => _errorMessage = 'Could not read statement file bytes.');
        return;
      }

      if (ext == 'csv' || ext == 'txt') {
        final content = utf8.decode(bytes, allowMalformed: true);
        final csvDrafts = CsvStatementParser.parseCsvContent(content);
        if (csvDrafts.isNotEmpty) {
          setState(() {
            _parsedDrafts = csvDrafts;
            _errorMessage = null;
            _statusMessage =
                'Parsed ${csvDrafts.length} statement rows offline! Duplicates will be skipped automatically.';
          });
          return;
        }
        // Fallback to SMS/text parser or Gemini
        final regexDrafts = SmsRegexParser.parseTextBlock(content);
        if (regexDrafts.isNotEmpty) {
          setState(() {
            _parsedDrafts = regexDrafts;
            _statusMessage = 'Extracted ${regexDrafts.length} transactions!';
          });
          return;
        }
        setState(() {
          _smsTextCtrl.text = content;
        });
        await _parseSmsOrLogWithGemini();
      } else if (ext == 'pdf') {
        await _analyzePdfBytes(bytes, file.name);
      }
    } catch (e) {
      setState(() => _errorMessage = 'Statement upload failed: $e');
    }
  }

  Future<void> _analyzePdfBytes(Uint8List pdfBytes, String fileName) async {
    setState(() {
      _isBusy = true;
      _errorMessage = null;
      _statusMessage =
          'Analyzing PDF "$fileName" via Gemini 3.8 Flash Document Engine…';
    });
    try {
      final drafts = await ref
          .read(geminiServiceProvider)
          .parsePdfStatement(pdfBytes);
      setState(() {
        _parsedDrafts = drafts;
        _isBusy = false;
        _statusMessage =
            'Extracted ${drafts.length} transactions from PDF statement!';
      });
    } catch (e) {
      setState(() {
        _isBusy = false;
        _errorMessage = e.toString().replaceAll('Bad state: ', '');
      });
    }
  }

  Future<void> _confirmImportDrafts() async {
    if (_parsedDrafts.isEmpty) return;
    final imported = await ref
        .read(finTrackControllerProvider.notifier)
        .importParsedDrafts(_parsedDrafts, accountId: _selectedAccountId);

    if (mounted) {
      LuxeHaptics.medium();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            imported == _parsedDrafts.length
                ? 'Added $imported transaction(s) to your encrypted vault!'
                : 'Added $imported new transaction(s) (${_parsedDrafts.length - imported} duplicate(s) skipped).',
          ),
        ),
      );
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final luxe = context.luxe;
    final state = ref.watch(finTrackControllerProvider);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.90,
      ),
      padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + bottomInset),
      decoration: BoxDecoration(
        color: luxe.bgElevated,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        border: Border.all(color: luxe.borderSubtle),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: luxe.textMuted.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          const SizedBox(height: 14),
          _buildModeSelector(luxe),
          const SizedBox(height: 16),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_errorMessage != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: luxe.crimson.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: luxe.crimson),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _errorMessage!,
                            style: TextStyle(color: luxe.crimson, fontSize: 13),
                          ),
                          if (_activeTab != CaptureTab.manual) ...[
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    side: BorderSide(color: luxe.cyan),
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _showInlineKeyEditor = true;
                                    });
                                  },
                                  icon: Icon(
                                    Icons.key_rounded,
                                    size: 15,
                                    color: luxe.cyan,
                                  ),
                                  label: Text(
                                    state.hasGeminiKey
                                        ? 'Update Gemini API Key'
                                        : 'Add Gemini API Key',
                                    style: TextStyle(
                                      color: luxe.cyan,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                if (_activeTab == CaptureTab.screenshot &&
                                    _selectedImageBytes != null)
                                  OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      side: BorderSide(color: luxe.emerald),
                                    ),
                                    onPressed: _isBusy
                                        ? null
                                        : () => _analyzeScreenshotBytes(
                                              _selectedImageBytes!,
                                            ),
                                    icon: Icon(
                                      Icons.refresh_rounded,
                                      size: 15,
                                      color: luxe.emerald,
                                    ),
                                    label: Text(
                                      'Retry Vision Scan',
                                      style: TextStyle(
                                        color: luxe.emerald,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  if (_activeTab != CaptureTab.manual &&
                      (!state.hasGeminiKey || _showInlineKeyEditor))
                    _buildInlineGeminiKeyCard(luxe, state),
                  if (_activeTab == CaptureTab.manual)
                    _buildManualEntryView(luxe, state)
                  else ...[
                    if (_activeTab == CaptureTab.screenshot)
                      _buildScreenshotView(luxe),
                    if (_activeTab == CaptureTab.voice) _buildVoiceView(luxe),
                    if (_activeTab == CaptureTab.smsPaste)
                      _buildSmsPasteView(luxe),
                    if (_activeTab == CaptureTab.statement)
                      _buildStatementView(luxe),
                    if (_parsedDrafts.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _buildParsedDraftsPreview(luxe, state),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeSelector(LuxeTokens luxe) {
    final modes = [
      (CaptureTab.manual, Icons.edit_note_rounded, 'Manual'),
      (CaptureTab.screenshot, Icons.document_scanner_outlined, 'Screenshot'),
      (CaptureTab.voice, Icons.mic_none_rounded, 'Voice AI'),
      (CaptureTab.smsPaste, Icons.sms_outlined, 'SMS / Log'),
      (CaptureTab.statement, Icons.upload_file_rounded, 'Statement'),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: modes.map((item) {
          final isSelected = _activeTab == item.$1;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () {
                LuxeHaptics.selection();
                setState(() {
                  _activeTab = item.$1;
                  _errorMessage = null;
                });
              },
              child: AnimatedContainer(
                duration: LuxeMotion.fast,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  gradient: isSelected ? luxe.primaryGradient : null,
                  color: isSelected ? null : luxe.surfaceGlass,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: isSelected ? Colors.transparent : luxe.borderSubtle,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      item.$2,
                      size: 16,
                      color: isSelected
                          ? const Color(0xFF061510)
                          : luxe.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      item.$3,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: isSelected
                            ? const Color(0xFF061510)
                            : luxe.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildManualEntryView(LuxeTokens luxe, FinTrackState state) {
    final paise = _enteredManualPaise;
    final showWorkHours =
        _manualType == TxnType.debit &&
        paise >= 50000 && // >= ₹500
        state.hourlyRatePaise > 0;
    final workHours = showWorkHours ? (paise / state.hourlyRatePaise) : 0.0;

    final filteredCategories = state.categories
        .where((c) => _manualType == TxnType.credit ? c.isIncome : !c.isIncome)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Debit vs Credit Toggle
        Row(
          children: [
            Expanded(
              child: _TypeToggleButton(
                label: 'Spent (Debit)',
                icon: Icons.south_east_rounded,
                isSelected: _manualType == TxnType.debit,
                activeColor: luxe.crimson,
                onTap: () => setState(() {
                  _manualType = TxnType.debit;
                  _selectedCategoryId = 'cat_food';
                }),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _TypeToggleButton(
                label: 'Credited (Income)',
                icon: Icons.north_west_rounded,
                isSelected: _manualType == TxnType.credit,
                activeColor: luxe.emerald,
                onTap: () => setState(() {
                  _manualType = TxnType.credit;
                  _selectedCategoryId = 'cat_income_salary';
                }),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _amountCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: Theme.of(context).textTheme.displaySmall?.copyWith(
            color: _manualType == TxnType.credit ? luxe.emerald : luxe.textPrimary,
          ),
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            prefixText: '₹ ',
            hintText: '0',
            labelText: _manualType == TxnType.credit
                ? 'Amount Credited'
                : 'Amount Spent',
            suffixIcon: _amountCtrl.text.isNotEmpty
                ? IconButton(
                    tooltip: 'Clear entered amount',
                    onPressed: () {
                      LuxeHaptics.medium();
                      setState(() {
                        _amountCtrl.clear();
                        _errorMessage = null;
                      });
                    },
                    icon: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: luxe.crimson.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: luxe.crimson.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.backspace_rounded,
                            size: 14,
                            color: luxe.crimson,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Clear',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: luxe.crimson,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : null,
          ),
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              ...[100, 250, 500, 1000, 5000].map((amt) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ActionChip(
                    label: Text('+₹$amt'),
                    onPressed: () => _bumpAmount(amt),
                  ),
                );
              }),
              if (_amountCtrl.text.isNotEmpty)
                ActionChip(
                  avatar: Icon(
                    Icons.restart_alt_rounded,
                    size: 16,
                    color: luxe.crimson,
                  ),
                  label: Text(
                    'Reset ₹0',
                    style: TextStyle(
                      color: luxe.crimson,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  side: BorderSide(color: luxe.crimson.withValues(alpha: 0.5)),
                  onPressed: () {
                    LuxeHaptics.medium();
                    setState(() => _amountCtrl.clear());
                  },
                ),
            ],
          ),
        ),
        if (showWorkHours) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: luxe.gold.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: luxe.gold.withValues(alpha: 0.5)),
            ),
            child: Row(
              children: [
                Icon(Icons.schedule_rounded, size: 18, color: luxe.gold),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Friction Check: This spend equals ${workHours.toStringAsFixed(1)} hours of your work.',
                    style: TextStyle(
                      color: luxe.gold,
                      fontWeight: FontWeight.w600,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ],
            ),
          ).animate().fadeIn().scale(begin: const Offset(0.95, 0.95)),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _titleCtrl,
                decoration: InputDecoration(
                  labelText: _manualType == TxnType.credit
                      ? 'Source / Title (e.g. Salary, Freelance)'
                      : 'What for? (e.g. Snacks, Auto)',
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _counterpartyCtrl,
                decoration: InputDecoration(
                  labelText: _manualType == TxnType.credit
                      ? 'From Payer'
                      : 'Merchant / Payee',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          'CATEGORY (LIQUID GLASS SELECTOR)',
          style: Theme.of(context).textTheme.labelSmall,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: filteredCategories.map((cat) {
            final selected = _selectedCategoryId == cat.id;
            final catColor = Color(cat.colorValue);
            return GestureDetector(
              onTap: () {
                LuxeHaptics.selection();
                setState(() => _selectedCategoryId = cat.id);
              },
              child: AnimatedContainer(
                duration: LuxeMotion.medium,
                curve: LuxeMotion.bounce,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  gradient: selected
                      ? LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.white.withValues(
                              alpha: luxe.isDark ? 0.22 : 0.9,
                            ),
                            catColor.withValues(alpha: 0.30),
                            catColor.withValues(alpha: 0.14),
                          ],
                        )
                      : null,
                  color: selected ? null : luxe.surfaceGlass,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: selected ? catColor : luxe.borderSubtle,
                    width: selected ? 1.5 : 1.0,
                  ),
                  boxShadow: [
                    if (selected)
                      BoxShadow(
                        color: catColor.withValues(alpha: 0.38),
                        blurRadius: 16,
                        spreadRadius: 0.5,
                      ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedScale(
                      scale: selected ? 1.15 : 1.0,
                      duration: LuxeMotion.fast,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: catColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      cat.name,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500,
                        color: selected ? luxe.textPrimary : luxe.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _selectedAccountId,
                decoration: const InputDecoration(labelText: 'Account'),
                items: state.accounts
                    .map(
                      (a) => DropdownMenuItem(value: a.id, child: Text(a.name)),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _selectedAccountId = v);
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DropdownButtonFormField<PaymentMode>(
                initialValue: _selectedPaymentMode,
                decoration: const InputDecoration(labelText: 'Mode'),
                items: PaymentMode.values
                    .map(
                      (m) => DropdownMenuItem(value: m, child: Text(m.label)),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _selectedPaymentMode = v);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          'PROJECT / INVENTORY TAGS',
          style: Theme.of(context).textTheme.labelSmall,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: _presetTags.map((tag) {
            final active = _selectedTags.contains(tag);
            return FilterChip(
              label: Text(tag),
              selected: active,
              onSelected: (v) {
                setState(() {
                  if (v) {
                    _selectedTags.add(tag);
                  } else {
                    _selectedTags.remove(tag);
                  }
                });
              },
            );
          }).toList(),
        ),
        if (_manualType == TxnType.debit) ...[
          const SizedBox(height: 12),
          GlassCard(
            padding: const EdgeInsets.all(14),
            borderRadius: 18,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.group_add_outlined, color: luxe.cyan, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Split with Friends',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    Switch.adaptive(
                      value: _splitEnabled,
                      activeTrackColor: luxe.emerald,
                      onChanged: (v) => setState(() => _splitEnabled = v),
                    ),
                  ],
                ),
                if (_splitEnabled) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: _friendsCtrl,
                    decoration: const InputDecoration(
                      hintText: 'Friend names comma-separated (e.g. Sravan, Rahul)',
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: 18),
        GradientButton(
          label: _manualType == TxnType.credit
              ? 'Add Credit to Balance'
              : 'Log Expense',
          icon: _manualType == TxnType.credit
              ? Icons.add_circle_outline_rounded
              : Icons.check_circle_outline_rounded,
          gradient: _manualType == TxnType.credit
              ? luxe.creditGradient
              : luxe.primaryGradient,
          onPressed: _submitManualEntry,
        ),
      ],
    );
  }

  Widget _buildInlineGeminiKeyCard(LuxeTokens luxe, FinTrackState state) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        padding: const EdgeInsets.all(14),
        borderColor: luxe.cyan.withValues(alpha: 0.55),
        glowColor: luxe.cyan,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.vpn_key_rounded, color: luxe.cyan, size: 19),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    state.hasGeminiKey
                        ? 'Update Gemini Vision API Key'
                        : 'Activate Gemini 3.8 Flash Vision Key',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (state.hasGeminiKey && _showInlineKeyEditor)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: () =>
                        setState(() => _showInlineKeyEditor = false),
                    icon: Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: luxe.textSecondary,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Paste your Google AI Studio API key (AIzaSy...) once to unlock instant UPI screenshot, voice, and PDF statement vision.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontSize: 12.5,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _inlineApiKeyCtrl,
              obscureText: true,
              decoration: InputDecoration(
                hintText: 'Paste AIzaSy... key here',
                suffixIcon: TextButton.icon(
                  onPressed: () async {
                    final data = await Clipboard.getData(Clipboard.kTextPlain);
                    final text = data?.text?.trim() ?? '';
                    if (text.isNotEmpty) {
                      setState(() => _inlineApiKeyCtrl.text = text);
                      await _saveInlineApiKeyAndRetry();
                    }
                  },
                  icon: Icon(
                    Icons.content_paste_rounded,
                    size: 16,
                    color: luxe.cyan,
                  ),
                  label: Text(
                    'Paste & Save',
                    style: TextStyle(
                      color: luxe.cyan,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
              onSubmitted: (_) => _saveInlineApiKeyAndRetry(),
            ),
            const SizedBox(height: 10),
            GradientButton(
              label: _selectedImageBytes != null
                  ? 'Save Key & Scan Screenshot Now'
                  : 'Save Gemini API Key',
              icon: Icons.bolt_rounded,
              gradient: luxe.copilotGradient,
              isLoading: _isBusy,
              onPressed: _saveInlineApiKeyAndRetry,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScreenshotView(LuxeTokens luxe) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlassCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              if (_selectedImageBytes != null)
                Stack(
                  alignment: Alignment.center,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.memory(
                        _selectedImageBytes!,
                        height: 190,
                        fit: BoxFit.cover,
                      ),
                    ),
                    if (_isBusy)
                      Container(
                        height: 4,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          gradient: luxe.copilotGradient,
                          boxShadow: [
                            BoxShadow(
                              color: luxe.cyan,
                              blurRadius: 14,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                      )
                          .animate(onPlay: (c) => c.repeat(reverse: true))
                          .moveY(begin: -80, end: 80, duration: 1200.ms),
                  ],
                )
              else ...[
                Icon(
                  Icons.document_scanner_rounded,
                  size: 46,
                  color: luxe.cyan,
                ),
                const SizedBox(height: 10),
                Text(
                  'Share any GPay / PhonePe / Paytm screenshot directly to FinTrack AI, or pick one below.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
              if (_statusMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  _statusMessage!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: luxe.emerald, fontSize: 13),
                ),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: GradientButton(
                      label: 'Pick Screenshot',
                      icon: Icons.photo_library_outlined,
                      isLoading: _isBusy,
                      onPressed: () =>
                          _pickAndAnalyzeScreenshot(ImageSource.gallery),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GradientButton(
                      label: 'Camera',
                      icon: Icons.camera_alt_outlined,
                      gradient: luxe.copilotGradient,
                      isLoading: _isBusy,
                      onPressed: () =>
                          _pickAndAnalyzeScreenshot(ImageSource.camera),
                    ),
                  ),
                ],
              ),
              if (_selectedImageBytes != null && !_isBusy) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 44),
                    side: BorderSide(color: luxe.emerald.withValues(alpha: 0.6)),
                  ),
                  onPressed: () =>
                      _analyzeScreenshotBytes(_selectedImageBytes!),
                  icon: Icon(
                    Icons.auto_awesome_rounded,
                    size: 18,
                    color: luxe.emerald,
                  ),
                  label: Text(
                    'Re-Scan Selected Screenshot',
                    style: TextStyle(
                      color: luxe.emerald,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildVoiceView(LuxeTokens luxe) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlassCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              GestureDetector(
                onTap: _toggleVoiceRecording,
                child: AnimatedContainer(
                  duration: LuxeMotion.medium,
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: _isRecording
                        ? luxe.debitGradient
                        : luxe.copilotGradient,
                    boxShadow: [
                      BoxShadow(
                        color: (_isRecording ? luxe.crimson : luxe.cyan)
                            .withValues(alpha: 0.4),
                        blurRadius: _isRecording ? 32 : 18,
                        spreadRadius: _isRecording ? 6 : 1,
                      ),
                    ],
                  ),
                  child: Icon(
                    _isRecording ? Icons.stop_rounded : Icons.mic_rounded,
                    size: 38,
                    color: const Color(0xFF041512),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _isRecording
                    ? 'Recording Voice Note… Tap to Stop & Analyze'
                    : 'Tap Mic to Log by Voice (Gemini 3.8 Flash Audio)',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              if (_recordedFilePath != null && !_isRecording)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Audio captured (${p.basename(_recordedFilePath!)})',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              if (_statusMessage != null) ...[
                const SizedBox(height: 8),
                Text(
                  _statusMessage!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: luxe.emerald, fontSize: 13),
                ),
              ],
              const SizedBox(height: 16),
              TextField(
                controller: _voiceTranscriptFallbackCtrl,
                decoration: InputDecoration(
                  hintText:
                      'Or type quick voice phrase: "Spent 150 on auto with Sravan"',
                  suffixIcon: IconButton(
                    icon: Icon(Icons.send_rounded, color: luxe.emerald),
                    onPressed: _parseVoiceNoteTextSimulation,
                  ),
                ),
                onSubmitted: (_) => _parseVoiceNoteTextSimulation(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSmsPasteView(LuxeTokens luxe) {
    final finState = ref.watch(finTrackControllerProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlassCard(
          padding: const EdgeInsets.all(16),
          borderColor: luxe.emerald.withValues(alpha: 0.45),
          glowColor: luxe.emerald,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.mark_chat_read_rounded,
                    color: luxe.emerald,
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Auto-Analyze Device Bank SMS',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          'Automatically scans incoming & recent bank/UPI SMS messages and adds spend details',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                  Switch.adaptive(
                    value: finState.autoSmsEnabled,
                    activeTrackColor: luxe.emerald,
                    onChanged: (v) => ref
                        .read(finTrackControllerProvider.notifier)
                        .setAutoSmsEnabled(v),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              GradientButton(
                label: 'Scan Android SMS Inbox Now & Auto-Add',
                icon: Icons.sync_rounded,
                isLoading: _isBusy,
                onPressed: () async {
                  setState(() {
                    _isBusy = true;
                    _errorMessage = null;
                    _statusMessage =
                        'Scanning Android SMS inbox for bank & UPI transactions…';
                  });
                  final count = await ref
                      .read(finTrackControllerProvider.notifier)
                      .syncBankSmsInbox(requestPermissionIfNeeded: true);
                  if (mounted) {
                    setState(() {
                      _isBusy = false;
                      _statusMessage = count > 0
                          ? 'Auto-imported $count new SMS transaction(s) into your vault!'
                          : 'SMS inbox synced! All detected bank SMS transactions are up to date.';
                    });
                  }
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        GlassCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Or Paste Bank SMS / Log Manually',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  TextButton.icon(
                    onPressed: _pasteFromClipboard,
                    icon: Icon(Icons.content_paste_rounded, color: luxe.emerald),
                    label: Text(
                      'Paste Clipboard',
                      style: TextStyle(color: luxe.emerald),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _smsTextCtrl,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText:
                      'e.g. "Rs 450.00 debited from A/C XX1234 on 28-OCT-26 to SWIGGY Ref 630192837465" or paste multiple lines…',
                ),
              ),
              if (_statusMessage != null) ...[
                const SizedBox(height: 10),
                Text(
                  _statusMessage!,
                  style: TextStyle(color: luxe.emerald, fontSize: 13),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: GradientButton(
                      label: 'Instant Parse',
                      icon: Icons.bolt_rounded,
                      isLoading: _isBusy,
                      onPressed: _parseSmsOrLogLocally,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GradientButton(
                      label: 'Gemini AI Parse',
                      icon: Icons.auto_awesome_rounded,
                      gradient: luxe.copilotGradient,
                      isLoading: _isBusy,
                      onPressed: _parseSmsOrLogWithGemini,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatementView(LuxeTokens luxe) {
    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Icon(Icons.upload_file_rounded, size: 46, color: luxe.gold),
          const SizedBox(height: 10),
          Text(
            'Upload Bank Statement (PDF or CSV)',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          Text(
            'CSVs are parsed 100% offline. PDFs are analyzed via Gemini 3.8 Flash Document Engine. Existing reference IDs & hashes are automatically deduplicated.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (_statusMessage != null) ...[
            const SizedBox(height: 10),
            Text(
              _statusMessage!,
              textAlign: TextAlign.center,
              style: TextStyle(color: luxe.emerald, fontSize: 13),
            ),
          ],
          const SizedBox(height: 16),
          GradientButton(
            label: 'Select PDF or CSV Statement',
            icon: Icons.folder_open_rounded,
            isLoading: _isBusy,
            onPressed: _pickAndParseStatementFile,
          ),
        ],
      ),
    );
  }

  Widget _buildParsedDraftsPreview(LuxeTokens luxe, FinTrackState state) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      borderColor: luxe.emerald.withValues(alpha: 0.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'READY TO IMPORT (${_parsedDrafts.length})',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: luxe.emerald,
                ),
              ),
              TextButton(
                onPressed: () => setState(() => _parsedDrafts = []),
                child: const Text('Clear'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ..._parsedDrafts.take(8).map((d) {
            final isCredit = d.type == TxnType.credit;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Icon(
                    isCredit
                        ? Icons.south_west_rounded
                        : Icons.north_east_rounded,
                    size: 18,
                    color: isCredit ? luxe.emerald : luxe.crimson,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          d.title,
                          style: Theme.of(context).textTheme.titleMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${d.paymentMode.label} • ${state.categoryById(d.categoryId).name}${d.splitFriends.isNotEmpty ? ' • Split with ${d.splitFriends.join(", ")}' : ''}',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                  AnimatedAmount(
                    paise: d.amountPaise,
                    showSign: true,
                    tone: isCredit ? AmountTone.credit : AmountTone.debit,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
            );
          }),
          if (_parsedDrafts.length > 8)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '+ ${_parsedDrafts.length - 8} more transactions…',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          const SizedBox(height: 14),
          GradientButton(
            label: 'Confirm & Import (${_parsedDrafts.length})',
            icon: Icons.bolt_rounded,
            onPressed: _confirmImportDrafts,
          ),
        ],
      ),
    );
  }
}

class _TypeToggleButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final Color activeColor;
  final VoidCallback onTap;

  const _TypeToggleButton({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.activeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final luxe = context.luxe;
    return GestureDetector(
      onTap: () {
        LuxeHaptics.selection();
        onTap();
      },
      child: AnimatedContainer(
        duration: LuxeMotion.fast,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        decoration: BoxDecoration(
          color: isSelected
              ? activeColor.withValues(alpha: 0.18)
              : luxe.surfaceGlass,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? activeColor : luxe.borderSubtle,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected ? activeColor : luxe.textSecondary,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: isSelected ? activeColor : luxe.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

