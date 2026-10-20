import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/constants/app_colors.dart';

/// Shared form controls for PolaMove's auth and profile forms.
///
/// Prefixed `App` because `FormField` and `DropdownField` would collide with
/// Flutter's own widgets of those names.

class AppFormField extends StatelessWidget {
  final String label;
  final String placeholder;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final bool obscure;
  final VoidCallback? onToggleObscure;
  final List<TextInputFormatter>? inputFormatters;
  final String? errorText;

  const AppFormField({super.key, required this.label, required this.placeholder,
      required this.controller, this.keyboardType, this.obscure = false,
      this.onToggleObscure, this.inputFormatters, this.errorText});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
          color: AppColors.textSecondary, letterSpacing: 0.7)),
      const SizedBox(height: 5),
      TextFormField(controller: controller, keyboardType: keyboardType,
        obscureText: obscure, inputFormatters: inputFormatters,
        style: const TextStyle(fontFamily: 'DM Sans', fontSize: 14,
            fontWeight: FontWeight.w500, color: AppColors.textPrimary),
        decoration: InputDecoration(hintText: placeholder, errorText: errorText,
          suffixIcon: onToggleObscure != null
              ? GestureDetector(onTap: onToggleObscure,
                  child: Icon(obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                      color: AppColors.textTertiary, size: 18)) : null)),
    ]);
  }
}

class AppDateField extends StatelessWidget {
  final String label;
  final String placeholder;
  final TextEditingController controller;
  final VoidCallback onTap;
  final String? errorText;

  const AppDateField({super.key, required this.label, required this.placeholder,
      required this.controller, required this.onTap, this.errorText});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
          color: AppColors.textSecondary, letterSpacing: 0.7)),
      const SizedBox(height: 5),
      TextFormField(controller: controller, readOnly: true, onTap: onTap,
        style: const TextStyle(fontFamily: 'DM Sans', fontSize: 14,
            fontWeight: FontWeight.w500, color: AppColors.textPrimary),
        decoration: InputDecoration(hintText: placeholder, errorText: errorText,
          suffixIcon: const Icon(Icons.calendar_today_outlined,
              color: AppColors.textTertiary, size: 17))),
    ]);
  }
}

class AppDropdownField<T> extends StatelessWidget {
  final String label;
  final String placeholder;
  final T? value;
  final List<T> items;
  final String Function(T) itemLabel;
  final void Function(T?) onChanged;
  final String? errorText;

  const AppDropdownField({super.key, required this.label, required this.placeholder,
      required this.value, required this.items, required this.itemLabel,
      required this.onChanged, this.errorText});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
          color: AppColors.textSecondary, letterSpacing: 0.7)),
      const SizedBox(height: 5),
      DropdownButtonFormField<T>(
        initialValue: value,
        hint: Text(placeholder, style: const TextStyle(fontFamily: 'DM Sans',
            fontSize: 14, color: AppColors.textTertiary)),
        items: items.map((e) => DropdownMenuItem(value: e,
            child: Text(itemLabel(e), style: const TextStyle(fontFamily: 'DM Sans',
                fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.textPrimary)))).toList(),
        onChanged: onChanged,
        decoration: InputDecoration(filled: true, fillColor: AppColors.surfaceAlt,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          errorText: errorText,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.border, width: 1.5)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.border, width: 1.5)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.primary, width: 1.5))),
        dropdownColor: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(12)),
    ]);
  }
}
