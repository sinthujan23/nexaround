import 'package:flutter_test/flutter_test.dart';
import 'package:nexaround_app/core/constants/countries.dart';

/// The country list and its ISO codes live in one file so they ship together,
/// which is the only thing stopping them drifting apart. This is what makes
/// that guarantee real: a country added to the list without a code would
/// silently widen the entry/exit search back to the whole world, which is the
/// bug the restriction exists to prevent.
void main() {
  group('country codes', () {
    test('every country in the list has a code', () {
      final missing =
          countriesList.where((c) => countryCodeFor(c) == null).toList();
      expect(missing, isEmpty,
          reason: 'add these to countryCodes in countries.dart: $missing');
    });

    test('every code is a real ISO 3166-1 alpha-2 shape', () {
      final bad = countryCodes.entries
          .where((e) =>
              e.value.length != 2 || e.value != e.value.toUpperCase())
          .map((e) => '${e.key}=${e.value}')
          .toList();
      expect(bad, isEmpty, reason: 'not two upper-case letters: $bad');
    });

    test('no two countries share a code', () {
      final seen = <String, String>{};
      final clashes = <String>[];
      for (final entry in countryCodes.entries) {
        final first = seen[entry.value];
        if (first != null) {
          clashes.add('${entry.value}: $first and ${entry.key}');
        } else {
          seen[entry.value] = entry.key;
        }
      }
      expect(clashes, isEmpty, reason: 'duplicate codes: $clashes');
    });

    test('the map has no country the list does not offer', () {
      final orphans =
          countryCodes.keys.where((k) => !countriesList.contains(k)).toList();
      expect(orphans, isEmpty,
          reason: 'in countryCodes but not countriesList: $orphans');
    });

    test('a few known codes are right', () {
      expect(countryCodeFor('Sri Lanka'), 'LK');
      expect(countryCodeFor('India'), 'IN');
      expect(countryCodeFor('United Kingdom'), 'GB');
      expect(countryCodeFor('United States'), 'US');
      expect(countryCodeFor('Russia'), 'RU');
      expect(countryCodeFor('Vietnam'), 'VN');
    });

    test('lookup is forgiving about case and spacing', () {
      expect(countryCodeFor('  sri lanka  '), 'LK');
      expect(countryCodeFor('INDIA'), 'IN');
    });

    test('an unknown name returns null rather than a guess', () {
      // Null means "search everywhere"; a made-up code would be rejected by
      // Google outright, which is worse than not restricting at all.
      expect(countryCodeFor('Wakanda'), isNull);
      expect(countryCodeFor(''), isNull);
      expect(countryCodeFor('   '), isNull);
      expect(countryCodeFor(null), isNull);
    });
  });
}
