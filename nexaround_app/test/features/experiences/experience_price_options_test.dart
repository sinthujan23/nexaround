import 'package:flutter_test/flutter_test.dart';
import 'package:nexaround_app/features/experiences/data/models/experience_model.dart';

void main() {
  test('price options are read from the card JSON, blanks filled in', () {
    final package = ExperiencePackageModel.fromJson({
      'id': 'p1',
      'title': 'Pigeon Island snorkeling',
      'vendor_id': 'v1',
      'vendor_name': 'Blue Ocean Adventures',
      'price_label': r'LKR 30,000 ($90) / group (max 7)',
      'price_options': [
        {'id': 'a', 'label': r'LKR 30,000 ($90) / group (max 7)',
          'basis': 'per_group', 'min_people': 1, 'max_people': 7},
        {'id': 'b', 'label': r'LKR 8,000 ($24) / person (min 3)',
          'basis': 'per_person', 'min_people': 3, 'max_people': null},
        {'label': 'no id, skipped'},
      ],
    });

    expect(package.priceOptions.map((o) => o.id), ['a', 'b']);
    expect(package.priceOptions[1].minPeople, 3);
    expect(package.priceOptions[1].maxPeople, isNull);
    expect(package.priceOptions[0].basis, 'per_group');
  });

  test('a server from before price options gives none', () {
    final package = ExperiencePackageModel.fromJson({
      'id': 'p1', 'title': 'T', 'vendor_id': 'v', 'vendor_name': 'V',
      'price_label': 'LKR 7,000 / person',
    });
    expect(package.priceOptions, isEmpty);
  });
}
