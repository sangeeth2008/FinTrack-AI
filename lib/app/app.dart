import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/native/reminder_service.dart';
import '../core/native/share_intent_bridge.dart';
import '../core/security/lock_controller.dart';
import '../core/state/fintrack_controller.dart';
import '../features/auth/ui/vault_lock_screen.dart';
import '../features/capture/ui/multimodal_capture_sheet.dart';
import '../features/copilot/ui/copilot_analytics_tab.dart';
import '../features/dashboard/ui/daily_summary_sheet.dart';
import '../features/dashboard/ui/home_tab.dart';
import '../features/profile/ui/profile_qr_sheet.dart';
import '../features/settings/ui/settings_sheet.dart';
import '../features/splits/ui/splits_tab.dart';
import '../features/wishlist/ui/impulse_locker_tab.dart';
import '../shared/widgets/luxe_scaffold.dart';
import 'motion/motion.dart';
import 'theme/luxe_theme.dart';
import 'theme/luxe_tokens.dart';

class _Luxe120HzScrollBehavior extends MaterialScrollBehavior {
  const _Luxe120HzScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
  }
}

class FinTrackApp extends ConsumerStatefulWidget {
  const FinTrackApp({super.key});

  @override
  ConsumerState<FinTrackApp> createState() => _FinTrackAppState();
}

class _FinTrackAppState extends ConsumerState<FinTrackApp> {
  late final AppLifecycleListener _lifecycleListener;
  bool _isPrivacyShieldVisible = false;

  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(
      onInactive: () {
        final lockNotifier = ref.read(lockControllerProvider.notifier);
        final lockState = ref.read(lockControllerProvider);
        if (mounted &&
            lockState.status == VaultStatus.unlocked &&
            !lockNotifier.isBiometricDialogActive) {
          setState(() => _isPrivacyShieldVisible = true);
        }
      },
      onHide: () {
        ref.read(lockControllerProvider.notifier).onAppBackgrounded();
      },
      onPause: () {
        ref.read(lockControllerProvider.notifier).onAppBackgrounded();
      },
      onDetach: () {
        ref.read(lockControllerProvider.notifier).onAppBackgrounded();
      },
      onResume: () {
        if (mounted && _isPrivacyShieldVisible) {
          setState(() => _isPrivacyShieldVisible = false);
        }
        ref.read(lockControllerProvider.notifier).onAppResumed();
        // Defer clipboard/SMS check by 650ms so unlock & resume animations run at locked 120fps/60fps
        Future.delayed(const Duration(milliseconds: 650), () {
          if (!mounted) return;
          final finState = ref.read(finTrackControllerProvider);
          if (finState.autoSmsEnabled && finState.smsPermissionGranted) {
            ref
                .read(finTrackControllerProvider.notifier)
                .syncBankSmsInbox(requestPermissionIfNeeded: false);
          }
        });
      },
    );
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final finState = ref.watch(finTrackControllerProvider);
    final lockState = ref.watch(lockControllerProvider);

    final isUnlocked = lockState.status == VaultStatus.unlocked;

    return MaterialApp(
      title: 'FinTrack AI',
      debugShowCheckedModeBanner: false,
      scrollBehavior: const _Luxe120HzScrollBehavior(),
      theme: LuxeTheme.light(),
      darkTheme: LuxeTheme.dark(),
      themeMode: finState.themeMode,
      themeAnimationDuration: const Duration(milliseconds: 180),
      themeAnimationCurve: Curves.easeOutCubic,
      builder: (context, child) {
        return Stack(
          fit: StackFit.expand,
          children: [
            ?child,
            if (_isPrivacyShieldVisible)
              const RepaintBoundary(
                child: ColoredBox(
                  color: Color(0xF2060A0E),
                  child: Center(
                    child: Icon(
                      Icons.shield_moon_rounded,
                      size: 58,
                      color: Color(0xFF10E5A0),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
      home: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) {
          return FadeTransition(opacity: animation, child: child);
        },
        child: !isUnlocked
            ? const RepaintBoundary(
                key: ValueKey('locked_screen'),
                child: VaultLockScreen(),
              )
            : Stack(
                key: const ValueKey('unlocked_stack'),
                fit: StackFit.expand,
                children: [
                  const RepaintBoundary(
                    child: MainVaultShell(key: ValueKey('unlocked_shell')),
                  ),
                  if (lockState.showWelcomeScreen)
                    const RepaintBoundary(
                      child: VaultWelcomeScreen(
                        key: ValueKey('welcome_screen'),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class MainVaultShell extends ConsumerStatefulWidget {
  const MainVaultShell({super.key});

  @override
  ConsumerState<MainVaultShell> createState() => _MainVaultShellState();
}

class _MainVaultShellState extends ConsumerState<MainVaultShell>
    with SingleTickerProviderStateMixin {
  int _selectedIndex = 0;
  StreamSubscription<SharedIntentPayload>? _shareSub;
  late final AnimationController _tabAnimCtrl;
  late final Animation<double> _tabFade;
  late final Animation<Offset> _tabSlide;

  @override
  void initState() {
    super.initState();
    _tabAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 190),
      value: 1.0,
    );
    _tabFade = CurvedAnimation(
      parent: _tabAnimCtrl,
      curve: Curves.easeOutCubic,
    );
    _tabSlide = Tween<Offset>(
      begin: const Offset(0.025, 0.0),
      end: Offset.zero,
    ).animate(_tabFade);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final bridge = ref.read(nativeBridgeProvider);
      final initial = await bridge.consumeInitialSharedPayload();
      if (initial != null && mounted) {
        _handleSharedPayload(initial);
      }
      _shareSub = bridge.sharedPayloadStream.listen((payload) {
        if (mounted) _handleSharedPayload(payload);
      });

      final notifRoute = await ReminderService.getPendingNotificationRoute();
      if (notifRoute != null && mounted) {
        if (notifRoute == 'daily_summary') {
          DailySummarySheet.show(context);
        } else {
          _openCaptureSheet(CaptureTab.manual);
        }
      }
    });
  }

  @override
  void dispose() {
    _tabAnimCtrl.dispose();
    _shareSub?.cancel();
    super.dispose();
  }

  void _handleSharedPayload(SharedIntentPayload payload) {
    if (payload.type == 'image' && payload.path != null) {
      _openCaptureSheet(
        CaptureTab.screenshot,
        sharedImagePath: payload.path,
      );
    } else if (payload.type == 'pdf' && payload.path != null) {
      _openCaptureSheet(
        CaptureTab.statement,
        sharedPdfPath: payload.path,
      );
    } else if (payload.text != null) {
      _openCaptureSheet(
        CaptureTab.smsPaste,
        sharedText: payload.text,
      );
    }
  }

  void _openCaptureSheet(
    CaptureTab tab, {
    String? sharedImagePath,
    String? sharedText,
    String? sharedPdfPath,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MultimodalCaptureSheet(
        initialTab: tab,
        initialSharedImagePath: sharedImagePath,
        initialSharedText: sharedText,
        initialSharedPdfPath: sharedPdfPath,
      ),
    );
  }

  void _openSettingsSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const SettingsSheet(),
    );
  }

  void _openProfileQrSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const ProfileQrSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final luxe = context.luxe;
    final finState = ref.watch(finTrackControllerProvider);

    final pages = [
      RepaintBoundary(child: HomeTab(onOpenCapture: _openCaptureSheet)),
      const RepaintBoundary(child: SplitsTab()),
      const RepaintBoundary(child: CopilotAnalyticsTab()),
      const RepaintBoundary(child: ImpulseLockerTab()),
    ];

    return LuxeScaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(11),
                boxShadow: [
                  BoxShadow(
                    color: luxe.emerald.withValues(alpha: 0.38),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: Image.asset(
                  'assets/images/app_logo.png',
                  width: 36,
                  height: 36,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(width: 10),
            const Text('FinTrack AI'),
          ],
        ),
        actions: [
          // Custom Liquid-Glass Profile & Receive UPI QR Badge
          _LuxeGlassTopBadge(
            tooltip: 'My Profile & Receive UPI QR',
            accentColor: luxe.cyan,
            onTap: _openProfileQrSheet,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  Icons.qr_code_scanner_rounded,
                  size: 19,
                  color: luxe.cyan,
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: luxe.emerald,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Custom Liquid-Glass Celestial Theme Switcher Badge
          _LuxeGlassTopBadge(
            tooltip: 'Switch Obsidian / Ivory Luxe Theme',
            accentColor: luxe.gold,
            onTap: () {
              final next = finState.themeMode == ThemeMode.light
                  ? ThemeMode.dark
                  : ThemeMode.light;
              ref.read(finTrackControllerProvider.notifier).setThemeMode(next);
            },
            child: AnimatedSwitcher(
              duration: LuxeMotion.fast,
              transitionBuilder: (child, anim) => RotationTransition(
                turns: Tween<double>(begin: 0.75, end: 1.0).animate(anim),
                child: ScaleTransition(scale: anim, child: child),
              ),
              child: finState.themeMode == ThemeMode.light
                  ? Stack(
                      key: const ValueKey('theme_dark_orb'),
                      alignment: Alignment.center,
                      children: [
                        Icon(
                          Icons.nights_stay_rounded,
                          size: 19,
                          color: luxe.gold,
                        ),
                        Positioned(
                          top: 1,
                          right: 1,
                          child: Icon(
                            Icons.auto_awesome,
                            size: 9,
                            color: luxe.emerald,
                          ),
                        ),
                      ],
                    )
                  : Stack(
                      key: const ValueKey('theme_light_orb'),
                      alignment: Alignment.center,
                      children: [
                        Icon(
                          Icons.wb_sunny_rounded,
                          size: 19,
                          color: luxe.gold,
                        ),
                        Positioned(
                          top: 1,
                          right: 1,
                          child: Icon(
                            Icons.flare_rounded,
                            size: 9,
                            color: luxe.cyan,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          const SizedBox(width: 8),
          // Custom Liquid-Glass Biometric Shield Vault Lock Badge
          _LuxeGlassTopBadge(
            tooltip: 'Lock Encrypted Vault Now',
            accentColor: luxe.crimson,
            onTap: () {
              LuxeHaptics.medium();
              ref.read(lockControllerProvider.notifier).lockVault();
            },
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  Icons.shield_moon_rounded,
                  size: 19,
                  color: luxe.crimson,
                ),
                Positioned(
                  bottom: 1,
                  right: 1,
                  child: Icon(
                    Icons.lock_rounded,
                    size: 9,
                    color: luxe.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Custom Liquid-Glass Control Matrix Settings Badge
          _LuxeGlassTopBadge(
            tooltip: 'Vault Settings, SMS Sync & Encrypted Backup',
            accentColor: luxe.emerald,
            onTap: _openSettingsSheet,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  Icons.tune_rounded,
                  size: 19,
                  color: luxe.emerald,
                ),
                Positioned(
                  top: 1,
                  right: 1,
                  child: Icon(
                    Icons.auto_awesome,
                    size: 8,
                    color: luxe.gold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
        ],
      ),
      // Smooth 120fps tab transition keeping all tab states alive in memory
      body: FadeTransition(
        opacity: _tabFade,
        child: SlideTransition(
          position: _tabSlide,
          child: IndexedStack(
            index: _selectedIndex,
            children: pages,
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: GestureDetector(
        onTap: () {
          LuxeHaptics.medium();
          _openCaptureSheet(CaptureTab.manual);
        },
        child: Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: luxe.primaryGradient,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.35),
              width: 1.4,
            ),
            boxShadow: [
              BoxShadow(
                color: luxe.emerald.withValues(alpha: 0.50),
                blurRadius: 24,
                spreadRadius: 2,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: const Icon(
            Icons.add_rounded,
            size: 32,
            color: Color(0xFF041510),
          ),
        ),
      ),
      bottomNavigationBar: RepaintBoundary(
        child: _LiquidGlassBottomNavBar(
          selectedIndex: _selectedIndex,
          onSelect: (index) {
            if (_selectedIndex == index) return;
            LuxeHaptics.selection();
            setState(() => _selectedIndex = index);
            _tabAnimCtrl.forward(from: 0.0);
          },
        ),
      ),
    );
  }
}

/// Custom-designed multi-layered Liquid Glass Top Bar Icon Badge
class _LuxeGlassTopBadge extends StatefulWidget {
  final Widget child;
  final String tooltip;
  final Color accentColor;
  final VoidCallback onTap;

  const _LuxeGlassTopBadge({
    required this.child,
    required this.tooltip,
    required this.accentColor,
    required this.onTap,
  });

  @override
  State<_LuxeGlassTopBadge> createState() => _LuxeGlassTopBadgeState();
}

class _LuxeGlassTopBadgeState extends State<_LuxeGlassTopBadge> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final luxe = context.luxe;
    final radius = BorderRadius.circular(14);

    return Tooltip(
      message: widget.tooltip,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: () {
          LuxeHaptics.selection();
          widget.onTap();
        },
        child: AnimatedScale(
          scale: _pressed ? 0.88 : 1.0,
          duration: LuxeMotion.micro,
          child: AnimatedContainer(
            duration: LuxeMotion.fast,
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: luxe.isDark ? 0.16 : 0.90),
                  widget.accentColor.withValues(alpha: 0.16),
                  luxe.surfaceGlass,
                ],
              ),
              borderRadius: radius,
              border: Border.all(
                color: _pressed
                    ? widget.accentColor
                    : widget.accentColor.withValues(alpha: 0.38),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: widget.accentColor.withValues(
                    alpha: _pressed ? 0.35 : 0.16,
                  ),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// Liquid Glass Bottom Navigation Dock with a Sliding Liquid Glass Selection Box
/// that smoothly glides over the category names and icons.
class _LiquidGlassBottomNavBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  const _LiquidGlassBottomNavBar({
    required this.selectedIndex,
    required this.onSelect,
  });

  static const _items = [
    (Icons.space_dashboard_outlined, Icons.space_dashboard_rounded, 'Overview'),
    (Icons.diversity_3_outlined, Icons.diversity_3_rounded, 'Splits'),
    (Icons.insights_outlined, Icons.auto_awesome_rounded, 'AI Audit'),
    (Icons.hourglass_empty_rounded, Icons.hourglass_full_rounded, 'Locker'),
  ];

  // Center x-fraction in the 5-slot dock (slot 2 is the center FAB gap)
  double _slotLeftFraction(int index) {
    return switch (index) {
      0 => 0.015,
      1 => 0.215,
      2 => 0.565,
      _ => 0.765,
    };
  }

  @override
  Widget build(BuildContext context) {
    final luxe = context.luxe;
    final dockRadius = BorderRadius.circular(30);

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: Container(
        height: 70,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: luxe.isDark
                ? [
                    const Color(0xFF172030).withValues(alpha: 0.96),
                    luxe.bgElevated.withValues(alpha: 0.97),
                    const Color(0xFF0E1824).withValues(alpha: 0.97),
                  ]
                : [
                    Colors.white.withValues(alpha: 0.97),
                    luxe.bgElevated.withValues(alpha: 0.96),
                    Colors.white.withValues(alpha: 0.95),
                  ],
          ),
          borderRadius: dockRadius,
          border: Border.all(
            color: Colors.white.withValues(
              alpha: luxe.isDark ? 0.16 : 0.65,
            ),
            width: 1.25,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(
                alpha: luxe.isDark ? 0.48 : 0.10,
              ),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final totalWidth = constraints.maxWidth;
            final boxWidth = totalWidth * 0.22;
            final boxLeft = totalWidth * _slotLeftFraction(selectedIndex);

            return Stack(
              alignment: Alignment.centerLeft,
              children: [
                // Sliding Liquid Glass Box over the active category icon & name
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOutBack,
                  left: boxLeft,
                  top: 7,
                  bottom: 7,
                  width: boxWidth,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.white.withValues(
                            alpha: luxe.isDark ? 0.24 : 0.95,
                          ),
                          luxe.emerald.withValues(
                            alpha: luxe.isDark ? 0.24 : 0.18,
                          ),
                          luxe.cyan.withValues(
                            alpha: luxe.isDark ? 0.14 : 0.10,
                          ),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: luxe.emerald.withValues(alpha: 0.65),
                        width: 1.3,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: luxe.emerald.withValues(alpha: 0.32),
                          blurRadius: 16,
                          spreadRadius: 0.5,
                        ),
                      ],
                    ),
                  ),
                ),
                // Category Icons & Labels Row
                Row(
                  children: [
                    Expanded(
                      flex: 22,
                      child: _DockCategoryItem(
                        icon: _items[0].$1,
                        activeIcon: _items[0].$2,
                        label: _items[0].$3,
                        isSelected: selectedIndex == 0,
                        onTap: () => onSelect(0),
                      ),
                    ),
                    Expanded(
                      flex: 22,
                      child: _DockCategoryItem(
                        icon: _items[1].$1,
                        activeIcon: _items[1].$2,
                        label: _items[1].$3,
                        isSelected: selectedIndex == 1,
                        onTap: () => onSelect(1),
                      ),
                    ),
                    const Spacer(flex: 12), // Center FAB space
                    Expanded(
                      flex: 22,
                      child: _DockCategoryItem(
                        icon: Icons.insights_outlined,
                        activeIcon: _items[2].$2,
                        label: _items[2].$3,
                        isSelected: selectedIndex == 2,
                        onTap: () => onSelect(2),
                      ),
                    ),
                    Expanded(
                      flex: 22,
                      child: _DockCategoryItem(
                        icon: _items[3].$1,
                        activeIcon: _items[3].$2,
                        label: _items[3].$3,
                        isSelected: selectedIndex == 3,
                        onTap: () => onSelect(3),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _DockCategoryItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _DockCategoryItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final luxe = context.luxe;
    final color = isSelected ? luxe.emerald : luxe.textMuted;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedScale(
            scale: isSelected ? 1.16 : 1.0,
            duration: LuxeMotion.fast,
            curve: LuxeMotion.bounce,
            child: Icon(
              isSelected ? activeIcon : icon,
              color: color,
              size: 22,
            ),
          ),
          const SizedBox(height: 3),
          AnimatedDefaultTextStyle(
            duration: LuxeMotion.fast,
            style: TextStyle(
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
              color: isSelected ? luxe.textPrimary : color,
              letterSpacing: isSelected ? 0.2 : 0,
            ),
            child: Text(label),
          ),
        ],
      ),
    );
  }
}
