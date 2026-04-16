import 'package:flutter/material.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/features/attractions/domain/entities/attraction.dart';

class CategoryChips extends StatelessWidget {
  final List<CategoryEntity> categories;
  final String? selectedCategoryId;
  final Function(String?) onSelected;

  const CategoryChips({
    super.key,
    required this.categories,
    this.selectedCategoryId,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: categories.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          if (index == 0) {
            final isAllSelected = selectedCategoryId == null;
            return _CategoryChip(
              label: 'All',
              isSelected: isAllSelected,
              onTap: () => onSelected(null),
            );
          }
          
          final category = categories[index - 1];
          final isSelected = selectedCategoryId == category.id;
          
          return _CategoryChip(
            label: category.name,
            icon: _getIconData(category.icon),
            isSelected: isSelected,
            onTap: () => onSelected(category.id),
          );
        },
      ),
    );
  }

  IconData? _getIconData(String? iconName) {
    switch (iconName) {
      case 'place': return Icons.place_rounded;
      case 'restaurant': return Icons.restaurant_rounded;
      case 'hotel': return Icons.hotel_rounded;
      case 'shopping_bag': return Icons.shopping_bag_rounded;
      case 'explore': return Icons.explore_rounded;
      case 'directions_bus': return Icons.directions_bus_rounded;
      default: return null;
    }
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.label,
    this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: isSelected 
              ? AppColors.primary 
              : (isDark ? AppColors.darkSurface : Colors.white),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: isSelected 
                ? AppColors.primary 
                : (isDark ? Colors.white12 : AppColors.border),
          ),
          boxShadow: isSelected ? [
            BoxShadow(
              color: AppColors.primary.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            )
          ] : [],
        ),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 18,
                color: isSelected ? Colors.white : AppColors.textSecondary,
              ),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : AppColors.textSecondary,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
