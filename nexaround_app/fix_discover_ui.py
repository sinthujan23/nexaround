import re

file_path = r"d:\Github\nexaround\nexaround_app\lib\features\food_radar\presentation\pages\discover_page.dart"
with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

# 1. Change _tabs array
content = content.replace(
    "final List<String> _tabs = ['Food', 'Experiences', 'Shopping', 'Medical', 'Hospital', 'Budget', 'Emergency'];",
    "final List<String> _tabs = ['Experiences', 'Food', 'Shopping', 'Medical', 'Hospital', 'Budget', 'Emergency'];"
)

# 2. Reduce card size in _buildShimmerItemCard
old_shimmer = '''  Widget _buildShimmerItemCard() {
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),'''
new_shimmer = '''  Widget _buildShimmerItemCard() {
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),'''
content = content.replace(old_shimmer, new_shimmer)

# 3. Reduce card size in _buildRestaurantCard
old_rest_1 = '''      child: GlassCard(
        margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: AppColors.primary.withOpacity(0.1),
              border: Border.all(color: AppColors.primary.withOpacity(0.2)),
            ),
            child: Center(
              child: Icon(
                _getFoodIcon(a.categoryName ?? 'Food', a.name, index),
                color: AppColors.primary,
                size: 28,
              ),
            ),
          ),'''
new_rest_1 = '''      child: GlassCard(
        margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: AppColors.primary.withOpacity(0.1),
              border: Border.all(color: AppColors.primary.withOpacity(0.2)),
            ),
            child: Center(
              child: Icon(
                _getFoodIcon(a.categoryName ?? 'Food', a.name, index),
                color: AppColors.primary,
                size: 22,
              ),
            ),
          ),'''
content = content.replace(old_rest_1, new_rest_1)

old_rest_2 = '''              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: AppColors.primaryGradient,
                  boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.3), blurRadius: 10)],
                ),
                child: const Icon(Icons.navigation_rounded, color: Colors.white, size: 18),
              ),'''
new_rest_2 = '''              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: AppColors.primaryGradient,
                  boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.3), blurRadius: 10)],
                ),
                child: const Icon(Icons.navigation_rounded, color: Colors.white, size: 16),
              ),'''
content = content.replace(old_rest_2, new_rest_2)

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)

print("Updated discover_page.dart successfully!")
