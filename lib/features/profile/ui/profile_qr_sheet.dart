import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../../../app/motion/motion.dart';
import '../../../app/theme/luxe_tokens.dart';
import '../../../core/state/fintrack_controller.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/gradient_button.dart';
import '../../splits/domain/split_calculator.dart';

class ProfileQrSheet extends ConsumerStatefulWidget {
  final int? initialRequestAmountPaise;
  final String? friendName;

  const ProfileQrSheet({
    super.key,
    this.initialRequestAmountPaise,
    this.friendName,
  });

  @override
  ConsumerState<ProfileQrSheet> createState() => _ProfileQrSheetState();
}

class _ProfileQrSheetState extends ConsumerState<ProfileQrSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _vpaCtrl;
  late final TextEditingController _customAmountCtrl;
  bool _showUploadedImage = true;
  String? _statusMsg;

  @override
  void initState() {
    super.initState();
    final state = ref.read(finTrackControllerProvider);
    _nameCtrl = TextEditingController(text: state.upiName);
    _vpaCtrl = TextEditingController(text: state.upiVpa);
    final initRupees = widget.initialRequestAmountPaise != null
        ? (widget.initialRequestAmountPaise! / 100.0).toStringAsFixed(0)
        : '';
    _customAmountCtrl = TextEditingController(text: initRupees);
    _showUploadedImage =
        state.upiQrImagePath != null &&
        File(state.upiQrImagePath!).existsSync();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _vpaCtrl.dispose();
    _customAmountCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickUpiQrImage() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 92,
      );
      if (picked == null) return;

      final docsDir = await getApplicationDocumentsDirectory();
      final ext = p.extension(picked.path).isEmpty
          ? '.jpg'
          : p.extension(picked.path);
      final targetPath = p.join(
        docsDir.path,
        'my_upi_qr_${DateTime.now().millisecondsSinceEpoch}$ext',
      );
      await File(picked.path).copy(targetPath);

      await ref
          .read(finTrackControllerProvider.notifier)
          .updatePreferences(upiQrImagePath: targetPath);

      if (mounted) {
        LuxeHaptics.medium();
        setState(() {
          _showUploadedImage = true;
          _statusMsg = 'UPI QR Code image saved to your Profile & Splits!';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _statusMsg = 'Could not upload QR image: $e');
      }
    }
  }

  Future<void> _saveProfileIdentity() async {
    await ref.read(finTrackControllerProvider.notifier).updatePreferences(
          upiName: _nameCtrl.text.trim(),
          upiVpa: _vpaCtrl.text.trim(),
        );
    if (mounted) {
      LuxeHaptics.selection();
      setState(() => _statusMsg = 'Profile & UPI ID updated!');
    }
  }

  @override
  Widget build(BuildContext context) {
    final luxe = context.luxe;
    final state = ref.watch(finTrackControllerProvider);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    final hasUploadedQr = state.upiQrImagePath != null &&
        File(state.upiQrImagePath!).existsSync();
    final vpa = _vpaCtrl.text.trim().isEmpty
        ? (state.upiVpa.trim().isEmpty ? 'yourname@upi' : state.upiVpa.trim())
        : _vpaCtrl.text.trim();
    final name = _nameCtrl.text.trim().isEmpty ? state.upiName : _nameCtrl.text.trim();

    final reqRupees = double.tryParse(_customAmountCtrl.text.trim()) ?? 0;
    final reqPaise = (reqRupees * 100).round();

    final upiUri = SplitCalculator.buildUpiPaymentUri(
      payeeVpa: vpa,
      payeeName: name,
      amountPaise: reqPaise > 0 ? reqPaise : 0,
      note: widget.friendName != null
          ? 'Split payment with ${widget.friendName}'
          : 'Payment to $name',
    );

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.92,
      ),
      padding: EdgeInsets.fromLTRB(20, 14, 20, 24 + bottomInset),
      decoration: BoxDecoration(
        color: luxe.bgElevated,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        border: Border.all(color: luxe.borderSubtle),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: luxe.textMuted.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: luxe.primaryGradient,
                  ),
                  child: const Icon(
                    Icons.qr_code_scanner_rounded,
                    color: Color(0xFF041510),
                    size: 26,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.friendName != null
                            ? 'Split QR for ${widget.friendName}'
                            : 'Profile & Receive Payments',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      Text(
                        'Show your UPI QR to split bills or receive money instantly',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_statusMsg != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: luxe.emerald.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _statusMsg!,
                  style: TextStyle(color: luxe.emerald, fontSize: 12.5),
                ),
              ),
            ],
            const SizedBox(height: 16),
            // Mode switcher: Uploaded QR Image vs Dynamic Amount QR
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _showUploadedImage = true),
                    child: AnimatedContainer(
                      duration: LuxeMotion.fast,
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      decoration: BoxDecoration(
                        gradient: _showUploadedImage ? luxe.primaryGradient : null,
                        color: _showUploadedImage ? null : luxe.surfaceGlass,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: _showUploadedImage
                              ? Colors.transparent
                              : luxe.borderSubtle,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.image_rounded,
                            size: 17,
                            color: _showUploadedImage
                                ? const Color(0xFF041510)
                                : luxe.textSecondary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'My Uploaded QR Image',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: _showUploadedImage
                                  ? const Color(0xFF041510)
                                  : luxe.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _showUploadedImage = false),
                    child: AnimatedContainer(
                      duration: LuxeMotion.fast,
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      decoration: BoxDecoration(
                        gradient: !_showUploadedImage ? luxe.primaryGradient : null,
                        color: !_showUploadedImage ? null : luxe.surfaceGlass,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: !_showUploadedImage
                              ? Colors.transparent
                              : luxe.borderSubtle,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.qr_code_2_rounded,
                            size: 18,
                            color: !_showUploadedImage
                                ? const Color(0xFF041510)
                                : luxe.textSecondary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Dynamic UPI QR',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: !_showUploadedImage
                                  ? const Color(0xFF041510)
                                  : luxe.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // QR Display Glass Card
            GlassCard(
              padding: const EdgeInsets.all(20),
              borderColor: luxe.borderHighlight,
              glowColor: luxe.emerald,
              child: Column(
                children: [
                  Text(
                    name.toUpperCase(),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      letterSpacing: 1.1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'UPI ID: $vpa',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: luxe.emerald,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_showUploadedImage) ...[
                    if (hasUploadedQr)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: Image.file(
                          File(state.upiQrImagePath!),
                          height: 240,
                          fit: BoxFit.contain,
                        ),
                      ).animate().fadeIn().scale(begin: const Offset(0.95, 0.95))
                    else
                      Container(
                        height: 210,
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: luxe.surfaceGlass,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: luxe.borderSubtle),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.add_photo_alternate_rounded,
                              size: 46,
                              color: luxe.emerald,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Upload Your UPI QR Code Image',
                              style: Theme.of(context).textTheme.titleMedium,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Pick your GPay / PhonePe / Paytm QR screenshot to display here & when splitting bills with friends',
                              style: Theme.of(context).textTheme.bodyMedium,
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _pickUpiQrImage,
                          icon: Icon(
                            Icons.upload_rounded,
                            size: 18,
                            color: luxe.emerald,
                          ),
                          label: Text(
                            hasUploadedQr
                                ? 'Change UPI QR Image'
                                : 'Upload UPI QR Image',
                          ),
                        ),
                        if (hasUploadedQr) ...[
                          const SizedBox(width: 10),
                          IconButton(
                            tooltip: 'Remove QR Image',
                            onPressed: () async {
                              await ref
                                  .read(finTrackControllerProvider.notifier)
                                  .updatePreferences(
                                    clearUpiQrImagePath: true,
                                  );
                            },
                            icon: Icon(
                              Icons.delete_outline_rounded,
                              color: luxe.crimson,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ] else ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: QrImageView(
                        data: upiUri.toString(),
                        size: 210,
                      ),
                    ).animate().fadeIn().scale(begin: const Offset(0.95, 0.95)),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _customAmountCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        prefixText: '₹ ',
                        labelText: 'Optional Request Amount (for Dynamic QR)',
                        hintText: 'Leave empty for any amount',
                        suffixIcon: _customAmountCtrl.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded, size: 18),
                                onPressed: () =>
                                    setState(() => _customAmountCtrl.clear()),
                              )
                            : null,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Quick Edit UPI Name & VPA
            GlassCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'YOUR RECEIVE PAYMENT IDENTITY',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _nameCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Your Name',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _vpaCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Your UPI ID',
                            hintText: 'name@okaxis',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _saveProfileIdentity,
                    icon: Icon(
                      Icons.check_circle_outline_rounded,
                      size: 18,
                      color: luxe.emerald,
                    ),
                    label: const Text('Save Name & UPI ID'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            GradientButton(
              label: 'Share My Payment Link / QR Details',
              icon: Icons.share_rounded,
              onPressed: () {
                SharePlus.instance.share(
                  ShareParams(
                    text: reqPaise > 0
                        ? 'Pay ₹${reqRupees.toStringAsFixed(0)} to $name ($vpa) via UPI: $upiUri'
                        : 'Pay $name ($vpa) via UPI: $upiUri',
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

