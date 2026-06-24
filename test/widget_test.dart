import 'package:flutter_test/flutter_test.dart';

import 'package:featherdash/game_data.dart';

void main() {
  test('There are 40 levels with increasing targets', () {
    expect(Levels.all.length, 40);
    expect(Levels.all.first.targetScore < Levels.all.last.targetScore, true);
  });

  test('Each level has at least one hoop', () {
    for (final lvl in Levels.all) {
      expect(lvl.hoops.isNotEmpty, true);
    }
  });
}
