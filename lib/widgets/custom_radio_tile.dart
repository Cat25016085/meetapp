import 'package:flutter/material.dart';

class CustomRadioTile<T> extends StatelessWidget {
  final String title;
  final String? subtitle;
  final T value;
  final T? groupValue;
  final ValueChanged<T?>? onChanged;
  final bool enabled;

  const CustomRadioTile({
    super.key,
    required this.title,
    required this.value,
    required this.groupValue,
    required this.onChanged,
    this.subtitle,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final bool selected = value == groupValue;
    return InkWell(
      onTap: enabled && onChanged != null ? () => onChanged!(value) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              color: enabled ? (selected ? Colors.indigo : Colors.grey) : Colors.grey.shade300,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(
                    fontSize: 16,
                    color: enabled ? Colors.black : Colors.grey,
                  )),
                  if (subtitle != null)
                    Text(subtitle!, style: TextStyle(
                      fontSize: 12,
                      color: enabled ? Colors.grey.shade700 : Colors.grey.shade300,
                    )),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}