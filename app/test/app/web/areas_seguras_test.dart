import 'package:calculadoradarf/app/web/areas_seguras.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('padding e viewPadding ficam com o maior valor de cada lado', () {
    final m = comAreasSeguras(
      const MediaQueryData(padding: EdgeInsets.only(top: 10)),
      const EdgeInsets.only(top: 47, bottom: 34),
    );
    expect(m.padding, const EdgeInsets.only(top: 47, bottom: 34));
    expect(m.viewPadding, const EdgeInsets.only(top: 47, bottom: 34));
  });

  test('o que o sistema já dá a mais é mantido', () {
    final m = comAreasSeguras(
      const MediaQueryData(
        padding: EdgeInsets.only(left: 20),
        viewPadding: EdgeInsets.only(left: 20, bottom: 40),
      ),
      const EdgeInsets.only(bottom: 34),
    );
    expect(m.padding, const EdgeInsets.only(left: 20, bottom: 34));
    expect(m.viewPadding, const EdgeInsets.only(left: 20, bottom: 40));
  });
}
