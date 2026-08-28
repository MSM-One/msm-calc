import 'package:msm_calc/utils/steel_helper.dart';

void main() {
  final labels = [
    '0.75" 19x19(1.2) 4',
    '0.75" 19x19(1.6) 5',
    '0.75" 19x19(2.0) 6',
    '1" 25x25(1.2) 6',
    '1" 25x25(1.6) 7',
    '1" 25x25(2.0) 9'
  ];

  for (var label in labels) {
    print(
        'Original: $label -> Normalized: ${SteelHelper.normalizeSizeText(label)}');
  }
}
