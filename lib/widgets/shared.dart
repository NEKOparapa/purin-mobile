import 'dart:ui' show ImageFilter;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'app_theme.dart';

class AtmosphereBackground extends StatelessWidget {
  const AtmosphereBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: dark
              ? const [Color(0xFF141A24), Color(0xFF121B28), Color(0xFF152030)]
              : const [Color(0xFFF8F7F4), Color(0xFFEDF4FC), Color(0xFFF7FAFE)],
          stops: dark ? const [0, 0.55, 1] : const [0, 0.52, 1],
        ),
      ),
      child: CustomPaint(
        painter: _SkyMistPainter(dark: dark),
        child: child,
      ),
    );
  }
}

class _SkyMistPainter extends CustomPainter {
  const _SkyMistPainter({required this.dark});
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    final bloomCenter = Offset(size.width * 0.50, -size.height * 0.08);
    final bloomRadius = size.longestSide * 0.55;
    canvas.drawRect(
      rect,
      Paint()
        ..shader =
            RadialGradient(
              colors: dark
                  ? const [Color(0x14FFE0BA), Color(0x00FFE0BA)]
                  : const [Color(0xE6FFFAEE), Color(0x00FFFAEE)],
              stops: const [0.0, 1.0],
            ).createShader(
              Rect.fromCircle(center: bloomCenter, radius: bloomRadius),
            ),
    );
  }

  @override
  bool shouldRepaint(_SkyMistPainter oldDelegate) => oldDelegate.dark != dark;
}

/// Paint the header wash above scrolling content, leaving controls fully opaque.
class FadingPageHeader extends StatelessWidget {
  const FadingPageHeader({super.key, required this.child});
  final Widget child;
  static const feather = 14.0;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          bottom: -feather,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    colors.surface.withValues(alpha: .52),
                    colors.surface.withValues(alpha: .24),
                    colors.surface.withValues(alpha: .07),
                    colors.surface.withValues(alpha: 0),
                  ],
                  stops: const [0, .35, .70, 1],
                ),
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

/// Standard secondary page with a clean flat surface background.
class AtmosphereScaffold extends StatelessWidget {
  const AtmosphereScaffold({
    super.key,
    required this.body,
    this.title,
    this.actions,
    this.showBack = true,
    this.resizeToAvoidBottomInset = true,
  });

  final Widget body;
  final String? title;
  final List<Widget>? actions;
  final bool showBack;
  final bool resizeToAvoidBottomInset;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colors.surface,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      appBar: title == null
          ? null
          : AppBar(
              automaticallyImplyLeading: false,
              toolbarHeight: 58,
              titleSpacing: showBack ? 2 : 20,
              leading: showBack
                  ? IconButton(
                      tooltip: '返回',
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: Icon(
                        Icons.arrow_back_rounded,
                        size: 22,
                        color: colors.onSurface,
                      ),
                    )
                  : null,
              title: Text(title!),
              actions: [...?actions, const SizedBox(width: 8)],
            ),
      body: body,
    );
  }
}

/// Rounded surface shared by settings and secondary pages.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.radius = 18,
    this.padding,
    this.color,
    this.borderColor,
    this.shadows = true,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry? padding;
  final Color? color;
  final Color? borderColor;
  final bool shadows;

  @override
  Widget build(BuildContext context) {
    final atmo = AppAtmosphere.of(context);
    final shape = BorderRadius.circular(radius);
    final baseFill = color ?? atmo.cardFill;
    Widget inner = BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: baseFill,
          borderRadius: shape,
          border: Border.all(color: borderColor ?? atmo.cardBorder, width: 0.9),
        ),
        child: child,
      ),
    );
    inner = ClipRRect(borderRadius: shape, child: inner);
    if (!shadows) return inner;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: shape,
        boxShadow: [
          BoxShadow(
            color: atmo.shadowColor,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: inner,
    );
  }
}

/// Grouped Apple-style settings card with muted section header above.
class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    this.title,
    this.footer,
    required this.children,
    this.dividers = true,
  });

  final String? title;
  final String? footer;
  final List<Widget> children;
  final bool dividers;

  @override
  Widget build(BuildContext context) {
    final atmo = AppAtmosphere.of(context);
    final items = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      items.add(children[i]);
      if (dividers && i < children.length - 1) {
        items.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Divider(height: 0.9, thickness: 0.9, color: atmo.hairline),
          ),
        );
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Text(
              title!,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
                color: atmo.sectionHeader,
                letterSpacing: -0.1,
              ),
            ),
          ),
        GlassCard(
          radius: 26,
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: items,
          ),
        ),
        if (footer != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              footer!,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: atmo.sectionHeader,
              ),
            ),
          ),
      ],
    );
  }
}

/// Clean Apple-style list row inside a [SettingsSection].
class SettingsTile extends StatelessWidget {
  const SettingsTile({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.showChevron = false,
    this.enabled = true,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final bool showChevron;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final opacity = enabled ? 1.0 : 0.45;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Opacity(
          opacity: opacity,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
            child: Row(
              children: [
                if (leading != null) ...[leading!, const SizedBox(width: 12)],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: colors.onSurface,
                          letterSpacing: -0.2,
                        ),
                      ),
                      if (subtitle != null && subtitle!.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          subtitle!,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.4,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...[const SizedBox(width: 12), trailing!],
                if (showChevron) ...[
                  const SizedBox(width: 6),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: colors.onSurfaceVariant.withValues(alpha: 0.7),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Restrained Cupertino switch row matching Screenshot 1's pastel-blue toggles.
class SettingsSwitchTile extends StatelessWidget {
  const SettingsSwitchTile({
    super.key,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final atmo = AppAtmosphere.of(context);
    final enabled = onChanged != null;
    return SettingsTile(
      title: title,
      subtitle: subtitle,
      enabled: enabled,
      onTap: enabled ? () => onChanged!(!value) : null,
      trailing: Transform.scale(
        scale: 0.9,
        alignment: Alignment.centerRight,
        child: CupertinoSwitch(
          value: value,
          activeTrackColor: atmo.switchActiveTrack,
          inactiveTrackColor: atmo.switchInactiveTrack,
          onChanged: onChanged,
        ),
      ),
    );
  }
}

/// Sliding pill segmented control for 2-4 mutually exclusive choices.
class AppleSegmentedControl<T> extends StatelessWidget {
  const AppleSegmentedControl({
    super.key,
    required this.items,
    required this.selected,
    required this.onChanged,
    this.enabled = true,
  });

  final List<(T, String)> items;
  final T selected;
  final ValueChanged<T> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final atmo = AppAtmosphere.of(context);
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: atmo.segmentTrack,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          for (final (value, label) in items)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: enabled && value != selected
                    ? () => onChanged(value)
                    : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: value == selected
                        ? atmo.segmentThumb
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(11),
                    boxShadow: value == selected
                        ? [
                            BoxShadow(
                              color: atmo.shadowColor,
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: value == selected
                          ? FontWeight.w600
                          : FontWeight.w500,
                      color: value == selected
                          ? colors.onSurface
                          : colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Soft pill chip for selectable options or removable place tags.
class ApplePillChip extends StatelessWidget {
  const ApplePillChip({
    super.key,
    required this.label,
    this.selected = false,
    this.onTap,
    this.onDelete,
    this.deleteTooltip,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;
  final String? deleteTooltip;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final atmo = AppAtmosphere.of(context);
    return Material(
      color: selected ? colors.primary.withValues(alpha: 0.14) : atmo.inputFill,
      shape: StadiumBorder(
        side: BorderSide(
          color: selected
              ? colors.primary.withValues(alpha: 0.45)
              : atmo.hairline,
          width: 0.9,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Padding(
          padding: EdgeInsets.fromLTRB(13, 7, onDelete != null ? 8 : 13, 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected ? colors.primary : colors.onSurface,
                ),
              ),
              if (onDelete != null) ...[
                const SizedBox(width: 4),
                Tooltip(
                  message: deleteTooltip ?? '移除',
                  child: GestureDetector(
                    onTap: onDelete,
                    child: Icon(
                      Icons.close_rounded,
                      size: 15,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

Route<T> appleRoute<T>(Widget page) =>
    CupertinoPageRoute<T>(builder: (_) => page);
