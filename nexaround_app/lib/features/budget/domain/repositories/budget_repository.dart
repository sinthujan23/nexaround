import '../entities/budget.dart';

abstract class BudgetRepository {
  Future<Budget> getMyBudget();
  Future<List<BudgetSummary>> getBudgetHistory();
  Future<Budget> getBudgetById(String budgetId);
  Future<Budget> setupBudget({
    required String name,
    required double totalAmount,
    required DateTime startDate,
    required DateTime endDate,
    String currency = 'USD',
  });
  Future<Budget> closeBudget();
  Future<Expense> addExpense({
    required double amount,
    required String category,
    String? description,
  });
}
