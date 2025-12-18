import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';

class ProductionButton extends StatefulWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool isDisabled;
  final Duration debounceTime;
  final Color? backgroundColor;
  final Color? textColor;
  final IconData? icon;
  final double? height;
  final double? width;

  const ProductionButton({
    super.key,
    required this.text,
    this.onPressed,
    this.isLoading = false,
    this.isDisabled = false,
    this.debounceTime = const Duration(seconds: 2),
    this.backgroundColor,
    this.textColor,
    this.icon,
    this.height = 50,
    this.width,
  });

  @override
  State<ProductionButton> createState() => _ProductionButtonState();
}

class _ProductionButtonState extends State<ProductionButton> {
  DateTime? _lastClickTime;
  bool _isInternalLoading = false;

  bool get _canPress {
    if (widget.isLoading || widget.isDisabled || _isInternalLoading) {
      return false;
    }

    final now = DateTime.now();
    if (_lastClickTime != null && 
        now.difference(_lastClickTime!) < widget.debounceTime) {
      return false;
    }

    return true;
  }

  void _handlePress() async {
    if (!_canPress || widget.onPressed == null) return;

    setState(() {
      _lastClickTime = DateTime.now();
      _isInternalLoading = true;
    });

    // Minimum loading süresini garantileyelim (UX için)
    final futures = [
      Future.delayed(const Duration(milliseconds: 500)),
      Future.microtask(() => widget.onPressed!()),
    ];

    try {
      await Future.wait(futures);
    } finally {
      if (mounted) {
        setState(() {
          _isInternalLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCurrentlyLoading = widget.isLoading || _isInternalLoading;
    final canPress = _canPress;

    return SizedBox(
      height: widget.height,
      width: widget.width,
      child: ElevatedButton(
        onPressed: canPress ? _handlePress : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: widget.backgroundColor ?? 
              (canPress ? AppColors.white : AppColors.grey300),
          foregroundColor: widget.textColor ?? 
              (canPress ? AppColors.primary : AppColors.grey600),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: canPress ? 2 : 0,
        ),
        child: isCurrentlyLoading
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: widget.textColor ?? AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text('İşleniyor...'),
                ],
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.icon != null) ...[
                    Icon(widget.icon, size: 20),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    widget.text,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
