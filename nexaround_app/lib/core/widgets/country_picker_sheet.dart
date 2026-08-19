import 'package:flutter/material.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/constants/countries.dart';

/// Shows a modern, searchable modal bottom sheet to pick or filter by country.
///
/// Returns the selected country name, or `null` if dismissed without selection.
Future<String?> showCountryPickerSheet(
  BuildContext context, {
  String? selectedCountry,
  bool includeGlobal = false,
  String title = 'Select Country',
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    backgroundColor: Colors.transparent,
    builder: (context) => _CountryPickerSheet(
      selectedCountry: selectedCountry,
      includeGlobal: includeGlobal,
      title: title,
    ),
  );
}

class _CountryPickerSheet extends StatefulWidget {
  final String? selectedCountry;
  final bool includeGlobal;
  final String title;

  const _CountryPickerSheet({
    required this.selectedCountry,
    required this.includeGlobal,
    required this.title,
  });

  @override
  State<_CountryPickerSheet> createState() => _CountryPickerSheetState();
}

class _CountryPickerSheetState extends State<_CountryPickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final query = _searchQuery.trim().toLowerCase();

    final filteredCountries = countriesList.where((country) {
      if (query.isEmpty) return true;
      return country.toLowerCase().contains(query);
    }).toList();

    final showGlobal = widget.includeGlobal &&
        (query.isEmpty || 'global all'.contains(query));

    return Container(
      height: MediaQuery.of(context).size.height * 0.78,
      margin: EdgeInsets.only(bottom: bottomInset),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          // Single Clean Drag Handle
          Container(
            width: 40,
            height: 5,
            margin: const EdgeInsets.only(top: 12, bottom: 12),
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(10),
            ),
          ),

          // Header Title
          Padding(
            padding: const EdgeInsets.only(left: 20, right: 20, top: 2, bottom: 12),
            child: Row(
              children: [
                Text(
                  widget.title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Colors.black87,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1, color: AppColors.border),

          // Search Box with Live Filter and Clear Button
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: TextField(
                controller: _searchController,
                autofocus: false,
                style: const TextStyle(color: Colors.black87, fontSize: 14.5),
                onChanged: (val) {
                  setState(() {
                    _searchQuery = val;
                  });
                },
                decoration: InputDecoration(
                  hintText: 'Search country...',
                  hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                  prefixIcon: const Icon(Icons.search_rounded, color: Colors.grey, size: 20),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, color: Colors.grey, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {
                              _searchQuery = '';
                            });
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  focusedErrorBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  filled: false,
                  fillColor: Colors.transparent,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                ),
              ),
            ),
          ),

          // Country List
          Expanded(
            child: (filteredCountries.isEmpty && !showGlobal)
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.search_off_rounded, size: 48, color: Colors.grey.shade300),
                          const SizedBox(height: 12),
                          Text(
                            'No countries found for "$_searchQuery"',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    children: [
                      if (showGlobal) ...[
                        ListTile(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          leading: const Text('🌐', style: TextStyle(fontSize: 20)),
                          title: const Text(
                            'Global (All)',
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, color: Colors.black87),
                          ),
                          trailing: widget.selectedCountry == 'Global' || widget.selectedCountry == null
                              ? const Icon(Icons.check_circle_rounded, color: AppColors.brandGreen, size: 20)
                              : null,
                          onTap: () => Navigator.pop(context, 'Global'),
                        ),
                        const Divider(height: 1, indent: 16, endIndent: 16),
                      ],
                      ...filteredCountries.map((country) {
                        final isSelected = widget.selectedCountry == country;
                        return ListTile(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          title: Text(
                            country,
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                              color: isSelected ? AppColors.brandGreen : Colors.black87,
                            ),
                          ),
                          trailing: isSelected
                              ? const Icon(Icons.check_circle_rounded, color: AppColors.brandGreen, size: 20)
                              : null,
                          onTap: () => Navigator.pop(context, country),
                        );
                      }),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
