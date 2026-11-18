// Card mode: the same demo with SYNQT's private card add-on, which adds CARD as a PCI DSS compliant merchant's app
// would. It needs the synqt_card package (see README), so it lives outside lib/ and analysis.
// Run with: flutter run -t card/main.dart
import 'package:synqt_card/synqt_card.dart';
import 'package:synqt_demo/main.dart';

void main() {
  SynqtCardAddon.enable();
  runDemo();
}
