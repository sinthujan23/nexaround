import 'package:flutter/material.dart';
import '../../../../app/theme/app_colors.dart';
import '../../data/datasources/forum_service.dart';
import '../../data/models/forum_category.dart';
import '../../data/models/forum_topic.dart';

class CreateTopicSheet extends StatefulWidget {
  final ForumCategory? initialCategory;
  final List<ForumCategory> availableCategories;

  const CreateTopicSheet({
    super.key,
    this.initialCategory,
    this.availableCategories = const [],
  });

  static Future<ForumTopic?> show(
    BuildContext context, {
    ForumCategory? initialCategory,
    List<ForumCategory> availableCategories = const [],
  }) {
    return showModalBottomSheet<ForumTopic>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CreateTopicSheet(
        initialCategory: initialCategory,
        availableCategories: availableCategories,
      ),
    );
  }

  @override
  State<CreateTopicSheet> createState() => _CreateTopicSheetState();
}

class _CreateTopicSheetState extends State<CreateTopicSheet> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final _tagController = TextEditingController();

  ForumCategory? _selectedCategory;
  final List<String> _selectedTags = [];
  bool _isSubmitting = false;

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
    _selectedCategory = widget.initialCategory ??
        (widget.availableCategories.isNotEmpty ? widget.availableCategories.first : null);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _tagController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCategory == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a forum destination or category.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final topic = await ForumService().createTopic(
        categoryId: _selectedCategory!.id,
        title: _titleController.text.trim(),
        content: _contentController.text.trim(),
        tags: _selectedTags,
      );

      if (mounted) {
        Navigator.pop(context, topic);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error creating topic: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
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

                    // Question Title Input
                    const Text(
                      'QUESTION TITLE',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        color: Color(0xFF475569),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _titleController,
                      maxLines: 2,
                      minLines: 1,
                      textCapitalization: TextCapitalization.sentences,
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
                      'DETAILS & CONTEXT',
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
                      validator: (value) {
                        if (value == null || value.trim().length < 10) {
                          return 'Please provide more details (at least 10 characters)';
                        }
                        return null;
                      },
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
