import 'package:flutter/material.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/constants/countries.dart';
import '../../data/datasources/forum_service.dart';
import '../../data/models/forum_category.dart';
import '../../data/models/forum_topic.dart';

class CreateTopicSheet extends StatefulWidget {
  final ForumCategory? initialCategory;
  final List<ForumCategory> availableCategories;
  final String? initialCountry;

  const CreateTopicSheet({
    super.key,
    this.initialCategory,
    this.availableCategories = const [],
    this.initialCountry,
  });

  static Future<ForumTopic?> show(
    BuildContext context, {
    ForumCategory? initialCategory,
    List<ForumCategory> availableCategories = const [],
    String? initialCountry,
  }) {
    return showModalBottomSheet<ForumTopic>(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      backgroundColor: Colors.transparent,
      builder: (_) => CreateTopicSheet(
        initialCategory: initialCategory,
        availableCategories: availableCategories,
        initialCountry: initialCountry,
      ),
    );
  }

  @override
  State<CreateTopicSheet> createState() => _CreateTopicSheetState();
}

class _CreateTopicSheetState extends State<CreateTopicSheet> {
  final _formKey = GlobalKey<FormState>();
  final _scrollController = ScrollController();
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final _tagController = TextEditingController();

  ForumCategory? _selectedCategory;
  String? _selectedCountry;
  final List<String> _selectedTags = [];
  bool _isSubmitting = false;
  bool _countryError = false;
  String? _errorMessage;

  static final List<ForumCategory> _fallbackCategories = [
    ForumCategory(id: 'cat-solo', name: 'Solo Travel', slug: 'solo-travel', categoryType: 'topic'),
    ForumCategory(id: 'cat-budget', name: 'Budget Travel', slug: 'budget-travel', categoryType: 'topic'),
    ForumCategory(id: 'cat-family', name: 'Family Travel', slug: 'family-travel', categoryType: 'topic'),
    ForumCategory(id: 'cat-safety', name: 'Safety & Tips', slug: 'safety', categoryType: 'topic'),
  ];

  static const List<String> _commonTags = [
    'Hotels',
    'Food',
    'Transport',
    'Itinerary',
    'Solo',
    'Family',
    'Budget',
    'Safety',
  ];

  @override
  void initState() {
    super.initState();
    final categories = widget.availableCategories.isNotEmpty
        ? widget.availableCategories
        : _fallbackCategories;
    _selectedCategory = widget.initialCategory ?? categories.first;
    _selectedCountry = widget.initialCountry;
    if (_selectedCountry != null && !_selectedTags.contains(_selectedCountry!)) {
      _selectedTags.add(_selectedCountry!);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _titleController.dispose();
    _contentController.dispose();
    _tagController.dispose();
    super.dispose();
  }

  String _countryFlag(String code) {
    final clean = code.toUpperCase();
    if (clean.length != 2) return '🌐';
    final first = clean.codeUnitAt(0) - 0x41 + 0x1F1E6;
    final second = clean.codeUnitAt(1) - 0x41 + 0x1F1E6;
    return String.fromCharCode(first) + String.fromCharCode(second);
  }

  void _showCountryPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        String searchQuery = '';
        return StatefulBuilder(
          builder: (context, setModalState) {
            final q = searchQuery.trim().toLowerCase();
            final filtered = countriesList.where((name) {
              if (q.isEmpty) return true;
              return name.toLowerCase().contains(q);
            }).toList();
            final bottomInset = MediaQuery.of(context).viewInsets.bottom;

            return Container(
              height: MediaQuery.of(context).size.height * 0.72,
              margin: EdgeInsets.only(bottom: bottomInset),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE2E8F0),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Select Destination Country',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B)),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          splashRadius: 20,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Container(
                      height: 44,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.search_rounded, size: 20, color: Color(0xFF94A3B8)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              onChanged: (val) => setModalState(() => searchQuery = val),
                              decoration: const InputDecoration(
                                hintText: 'Search country...',
                                hintStyle: TextStyle(fontSize: 13.5, color: Color(0xFF94A3B8)),
                                border: InputBorder.none,
                                isDense: true,
                              ),
                              style: const TextStyle(fontSize: 13.5, color: Color(0xFF0F172A)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final country = filtered[index];
                        final code = countryCodeFor(country);
                        final flag = code != null ? _countryFlag(code) : '🌐';
                        final isSelected = _selectedCountry == country;

                        return ListTile(
                          leading: Text(flag, style: const TextStyle(fontSize: 20)),
                          title: Text(
                            country,
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                              color: isSelected ? AppColors.brandGreen : const Color(0xFF0F172A),
                            ),
                          ),
                          trailing: isSelected
                              ? const Icon(Icons.check_circle_rounded, color: AppColors.brandGreen, size: 18)
                              : null,
                          onTap: () {
                            setState(() {
                              if (_selectedCountry != null) {
                                _selectedTags.remove(_selectedCountry);
                              }
                              _selectedCountry = country;
                              _countryError = false;
                              _errorMessage = null;
                              if (!_selectedTags.contains(country)) {
                                _selectedTags.add(country);
                              }
                            });
                            Navigator.pop(context);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _submit() async {
    setState(() => _errorMessage = null);

    // 1. Mandatory Destination Country validation
    if (_selectedCountry == null || _selectedCountry!.trim().isEmpty) {
      setState(() {
        _countryError = true;
        _errorMessage = 'Please select a destination country.';
      });
      if (_scrollController.hasClients) {
        _scrollController.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
      return;
    }

    // 2. Validate Question Title
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      setState(() => _errorMessage = 'Please enter a question title.');
      _formKey.currentState?.validate();
      if (_scrollController.hasClients) {
        _scrollController.animateTo(60, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
      return;
    }
    if (title.length < 5) {
      setState(() => _errorMessage = 'Question title must be at least 5 characters.');
      _formKey.currentState?.validate();
      if (_scrollController.hasClients) {
        _scrollController.animateTo(60, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
      return;
    }

    // 3. Fallback category if not set
    final categories = widget.availableCategories.isNotEmpty
        ? widget.availableCategories
        : _fallbackCategories;
    _selectedCategory ??= categories.first;

    // Optional details - fall back to title if empty
    final content = _contentController.text.trim().isNotEmpty
        ? _contentController.text.trim()
        : title;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final tags = List<String>.from(_selectedTags);
    if (_selectedCountry != null && _selectedCountry!.trim().isNotEmpty && !tags.contains(_selectedCountry!)) {
      tags.insert(0, _selectedCountry!);
    }

    try {
      final topic = await ForumService().createTopic(
        categoryId: _selectedCategory!.id,
        title: title,
        content: content,
        tags: tags,
      );

      if (mounted) {
        Navigator.pop(context, topic);
      }
    } catch (e) {
      debugPrint('⚠️ Error creating topic: $e');
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _errorMessage = 'Could not post question. Please try again.';
        });
      }
    } finally {
      if (mounted && _isSubmitting) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      margin: EdgeInsets.only(bottom: bottomInset),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 44,
              height: 4.5,
              decoration: BoxDecoration(
                color: const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.brandGreen.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.help_outline_rounded,
                    color: AppColors.brandGreen,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Ask the Travel Community',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      Text(
                        'Get firsthand tips from verified locals & travelers',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),

          // Scrollable Form
          Flexible(
            child: SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Category Selector
                    const Text(
                      'SELECT FORUM / DESTINATION',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        color: Color(0xFF475569),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<ForumCategory>(
                          value: _selectedCategory,
                          isExpanded: true,
                          hint: const Text(
                            'Choose destination or topic',
                            style: TextStyle(fontSize: 14, color: Color(0xFF94A3B8)),
                          ),
                          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF64748B)),
                          items: widget.availableCategories.map((c) {
                            return DropdownMenuItem<ForumCategory>(
                              value: c,
                              child: Row(
                                children: [
                                  Icon(
                                    c.categoryType == 'topic'
                                        ? Icons.tag_rounded
                                        : Icons.location_on_rounded,
                                    size: 16,
                                    color: AppColors.brandGreen,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    c.name,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                          onChanged: (cat) {
                            if (cat != null) {
                              setState(() => _selectedCategory = cat);
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Destination Country Selector (Mandatory)
                    Row(
                      children: const [
                        Text(
                          'DESTINATION COUNTRY',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                            color: Color(0xFF475569),
                          ),
                        ),
                        SizedBox(width: 4),
                        Text(
                          '*',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            color: AppColors.error,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: _showCountryPicker,
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: _countryError && (_selectedCountry == null || _selectedCountry!.isEmpty)
                                ? AppColors.error
                                : const Color(0xFFE2E8F0),
                            width: _countryError && (_selectedCountry == null || _selectedCountry!.isEmpty) ? 1.5 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Text(
                              _selectedCountry != null
                                  ? _countryFlag(countryCodeFor(_selectedCountry!) ?? '')
                                  : '🌐',
                              style: const TextStyle(fontSize: 16),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _selectedCountry ?? 'Select country (e.g. Japan, France, Sri Lanka...)',
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: _selectedCountry != null ? FontWeight.w700 : FontWeight.w500,
                                  color: _selectedCountry != null ? const Color(0xFF0F172A) : const Color(0xFF94A3B8),
                                ),
                              ),
                            ),
                            if (_selectedCountry != null)
                              GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _selectedTags.remove(_selectedCountry);
                                    _selectedCountry = null;
                                  });
                                },
                                child: const Icon(Icons.close_rounded, size: 16, color: Color(0xFF64748B)),
                              )
                            else
                              const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: Color(0xFF64748B)),
                          ],
                        ),
                      ),
                    ),
                    if (_countryError && (_selectedCountry == null || _selectedCountry!.isEmpty)) ...[
                      const SizedBox(height: 4),
                      const Padding(
                        padding: EdgeInsets.only(left: 4),
                        child: Text(
                          'Destination country is required',
                          style: TextStyle(fontSize: 11, color: AppColors.error, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),

                    // Question Title Input
                    Row(
                      children: const [
                        Text(
                          'QUESTION TITLE',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                            color: Color(0xFF475569),
                          ),
                        ),
                        SizedBox(width: 4),
                        Text(
                          '*',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            color: AppColors.error,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _titleController,
                      maxLines: 2,
                      minLines: 1,
                      textCapitalization: TextCapitalization.sentences,
                      onChanged: (val) {
                        if (_errorMessage != null && val.trim().length >= 5) {
                          setState(() => _errorMessage = null);
                        }
                      },
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF0F172A),
                      ),
                      decoration: InputDecoration(
                        hintText: 'e.g. Best 3-day itinerary without renting a car?',
                        hintStyle: const TextStyle(fontSize: 14, color: Color(0xFF94A3B8)),
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: AppColors.brandGreen, width: 1.5),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().length < 5) {
                          return 'Please enter a clear title (at least 5 characters)';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 18),

                    // Question Details Input
                    const Text(
                      'DETAILS & CONTEXT (OPTIONAL)',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        color: Color(0xFF475569),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _contentController,
                      maxLines: 5,
                      minLines: 3,
                      textCapitalization: TextCapitalization.sentences,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF0F172A),
                        height: 1.4,
                      ),
                      decoration: InputDecoration(
                        hintText:
                            'Share dates, budget, who you are traveling with, and any specific preferences...',
                        hintStyle: const TextStyle(fontSize: 13.5, color: Color(0xFF94A3B8)),
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: AppColors.brandGreen, width: 1.5),
                        ),
                        contentPadding: const EdgeInsets.all(14),
                      ),
                      validator: (value) => null,
                    ),
                    const SizedBox(height: 18),

                    // Quick Tags
                    const Text(
                      'POPULAR TAGS',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        color: Color(0xFF475569),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _commonTags.map((tag) {
                        final isSelected = _selectedTags.contains(tag);
                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              if (isSelected) {
                                _selectedTags.remove(tag);
                              } else {
                                if (_selectedTags.length < 4) {
                                  _selectedTags.add(tag);
                                }
                              }
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppColors.brandGreen
                                  : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isSelected) ...[
                                  const Icon(Icons.check_rounded, size: 12, color: Colors.white),
                                  const SizedBox(width: 4),
                                ],
                                Text(
                                  '#$tag',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: isSelected ? Colors.white : const Color(0xFF334155),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 24),

                    // Error Notice Banner
                    if (_errorMessage != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        margin: const EdgeInsets.only(bottom: 14),
                        decoration: BoxDecoration(
                          color: AppColors.error.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline_rounded, size: 18, color: AppColors.error),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  color: AppColors.error,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // Submit Button
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _isSubmitting ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0F172A),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: _isSubmitting
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Colors.white,
                                ),
                              )
                            : const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.send_rounded, size: 18),
                                  SizedBox(width: 8),
                                  Text(
                                    'Post to Forum',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
