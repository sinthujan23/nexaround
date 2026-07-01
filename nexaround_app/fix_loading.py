import re

with open(r"d:\Github\nexaround\nexaround_app\lib\features\food_radar\presentation\pages\discover_page.dart", "r", encoding="utf-8") as f:
    content = f.read()

# 1. Remove the LinearProgressIndicator
content = re.sub(
    r'if\s*\(isLoading\)\s*LinearProgressIndicator\([\s\S]*?valueColor:[^\)]*\),\s*\),',
    '',
    content
)

# 2. Update _buildTabContent to pass isLoading
content = content.replace(
    '''  Widget _buildTabContent() {
    switch (_tabs[_selectedTab]) {
      case 'Food': return _buildFoodTab();
      case 'Experiences': return _buildExperiencesTab();
      case 'Shopping': return _buildShoppingTab();
      case 'Medical': return _buildMedicalTab();
      case 'Hospital': return _buildHospitalTab();
      case 'Budget': return _buildBudgetTab();
      case 'Emergency': return _buildEmergencyTab();
      default: return _buildFoodTab();
    }
  }''',
    '''  Widget _buildTabContent(bool isLoading) {
    switch (_tabs[_selectedTab]) {
      case 'Food': return _buildFoodTab(isLoading);
      case 'Experiences': return _buildExperiencesTab(isLoading);
      case 'Shopping': return _buildShoppingTab(isLoading);
      case 'Medical': return _buildMedicalTab(isLoading);
      case 'Hospital': return _buildHospitalTab(isLoading);
      case 'Budget': return _buildBudgetTab();
      case 'Emergency': return _buildEmergencyTab();
      default: return _buildFoodTab(isLoading);
    }
  }'''
)

# Replace the call in build method: child: _buildTabContent() -> child: _buildTabContent(isLoading)
content = content.replace('child: _buildTabContent(),', 'child: _buildTabContent(isLoading),')

# Add _buildShimmerItemCard
shimmer_card = '''  Widget _buildShimmerItemCard() {
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: Colors.grey[200],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(width: double.infinity, height: 16, color: Colors.grey[200]),
                const SizedBox(height: 8),
                Container(width: 100, height: 12, color: Colors.grey[200]),
                const SizedBox(height: 12),
                Container(width: 60, height: 12, color: Colors.grey[200]),
              ],
            ),
          ),
        ],
      ),
    ).animate(onPlay: (controller) => controller.repeat()).shimmer(duration: 1200.ms, color: Colors.white54);
  }
'''

content = content.replace('  Widget _buildRestaurantCard(AttractionEntity a, int index) {', shimmer_card + '\n  Widget _buildRestaurantCard(AttractionEntity a, int index) {')

# 3. Update all tab builders

def update_tab(tab_name, list_var):
    global content
    
    # 1. Signature
    content = content.replace(f'Widget _build{tab_name}Tab() {{', f'Widget _build{tab_name}Tab(bool isLoading) {{')
    
    # 2. Logic: if (list_var.isEmpty) ... else ...
    old_pattern = f'''if ({list_var}.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: Text('''
            
    new_pattern = f'''if (isLoading)
          ...List.generate(5, (index) => _buildShimmerItemCard())
        else if ({list_var}.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: Text('''
            
    content = content.replace(old_pattern, new_pattern)

update_tab('Food', '_foodList')
update_tab('Experiences', '_expList')
update_tab('Shopping', '_shoppingList')
update_tab('Medical', '_medicalList')
update_tab('Hospital', '_hospitalList')

with open(r"d:\Github\nexaround\nexaround_app\lib\features\food_radar\presentation\pages\discover_page.dart", "w", encoding="utf-8") as f:
    f.write(content)

print("Done")
