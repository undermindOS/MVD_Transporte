import 'package:flutter/material.dart';

import '../theme/timbre_text.dart';
import '../theme/timbre_tokens.dart';

/// Segmented control of the design: a mist track with the selected segment
/// lit in amber on ink. Day types in Horarios, 3 / 5 / 10 min in "Estoy
/// esperando".
class TimbreSegmented<T> extends StatelessWidget {
  const TimbreSegmented({
    super.key,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onChanged,
    this.semanticLabel,
  });

  final List<T> values;
  final T selected;
  final String Function(T value) labelOf;
  final ValueChanged<T> onChanged;

  /// Name of the whole group for screen readers ("Tipo de día").
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: semanticLabel,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: TimbreColors.niebla,
          borderRadius: BorderRadius.circular(TimbreRadii.button),
        ),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Row(
            children: [
              for (var i = 0; i < values.length; i++) ...[
                if (i > 0) const SizedBox(width: 4),
                Expanded(child: _segment(values[i])),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _segment(T value) {
    final isSelected = value == selected;
    final label = labelOf(value);
    final onTap = isSelected ? null : () => onChanged(value);
    // excludeSemantics drops the InkWell's tap action too: the node needs
    // its own onTap, or screen readers cannot pick a segment
    return Semantics(
      button: true,
      selected: isSelected,
      inMutuallyExclusiveGroup: true,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      // The chosen option lights up like the header plate
      child: Material(
        color: isSelected ? TimbreColors.tinta : Colors.transparent,
        borderRadius: BorderRadius.circular(11),
        child: InkWell(
          borderRadius: BorderRadius.circular(11),
          onTap: onTap,
          child: ConstrainedBox(
            // Grows with the system font size; a label wider than its
            // segment scales down instead of losing letters ("Hábil…")
            constraints: const BoxConstraints(minHeight: TimbreSpace.touch),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: TextStyle(
                      fontFamily: TimbreFonts.fira,
                      fontSize: 15,
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w600,
                      color:
                          isSelected ? TimbreColors.ambar : TimbreColors.tinta,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
