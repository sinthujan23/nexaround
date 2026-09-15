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

    test('every alias points at a country the list actually offers', () {
      // An alias naming a country the picker cannot show would resolve a place
      // to a country the traveller can never confirm.
      for (final name in const [
        'United States', 'United Kingdom', 'United Arab Emirates', 'South Korea',
        'Czechia', 'Eswatini', 'Cabo Verde', 'Timor-Leste', 'North Macedonia',
        'Myanmar', 'Netherlands', 'Turkey', 'Russia', 'Vietnam', 'Laos',
        'Syria', 'Brunei',
      ]) {
        expect(countriesList, contains(name),
            reason: '_countryAliases points at "$name", which is not in the list');
      }
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

  group('country from a picked place', () {
    test('the country is read off the end of the address', () {
      expect(countryNameFromPlace('Sri Lanka'), 'Sri Lanka');
      expect(countryNameFromPlace('Central Province, Sri Lanka'), 'Sri Lanka');
      expect(countryNameFromPlace('Tuscany, Italy'), 'Italy');
    });

    test('the spellings Google uses are understood', () {
      // This is the third way into the planner: a traveller who knows only a
      // city types it and the country fills itself in.
      expect(countryNameFromPlace('IL, USA'), 'United States');
      expect(countryNameFromPlace('England, UK'), 'United Kingdom');
      expect(countryNameFromPlace('Dubai, UAE'), 'United Arab Emirates');
      expect(countryNameFromPlace('Türkiye'), 'Turkey');
      expect(countryNameFromPlace('Czech Republic'), 'Czechia');
      expect(countryNameFromPlace('Swaziland'), 'Eswatini');
    });

    test('the answer is spelled the way the picker spells it', () {
      // So the value can be shown in the country field and matched again.
      final found = countryNameFromPlace('IL, USA');
      expect(countriesList, contains(found));
      expect(countryCodeFor(found), 'US');
    });

    test('an address that names no country we know returns null', () {
      // Null leaves the field for the traveller; a guess would put them in a
      // country they never chose.
      expect(countryNameFromPlace('Somewhere, Wakanda'), isNull);
      expect(countryNameFromPlace(''), isNull);
      expect(countryNameFromPlace(null), isNull);
      expect(countryNameFromPlace('   '), isNull);
    });
  });
}
