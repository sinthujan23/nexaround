import '../../domain/entities/budget.dart';

class BudgetModel extends Budget {
  const BudgetModel({
    required super.id,
    required super.userId,
    required super.name,
    required super.totalAmount,
    required super.currency,
    required super.startDate,
    required super.endDate,
    required super.isActive,
    required super.expenses,
  });

  factory BudgetModel.fromJson(Map<String, dynamic> json) {
    return BudgetModel(
      id: json['id'],
      userId: json['user_id'],
      name: json['name'] ?? 'My Budget',
      totalAmount: (json['total_amount'] as num).toDouble(),
      currency: json['currency'],
      startDate: DateTime.parse(json['start_date']),
      endDate: DateTime.parse(json['end_date']),
      isActive: json['is_active'] ?? true,
      expenses: (json['expenses'] as List?)
          ?.map((e) => ExpenseModel.fromJson(e))
          .toList() ?? [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'name': name,
      'total_amount': totalAmount,
      'currency': currency,
      'start_date': startDate.toIso8601String(),
      'end_date': endDate.toIso8601String(),
      'is_active': isActive,
    };
  }
}

class BudgetSummaryModel extends BudgetSummary {
  const BudgetSummaryModel({
    required super.id,
    required super.userId,
    required super.name,
    required super.totalAmount,
    required super.currency,
    required super.startDate,
    required super.endDate,
    required super.isActive,
    required super.totalSpent,
  });

  factory BudgetSummaryModel.fromJson(Map<String, dynamic> json) {
    return BudgetSummaryModel(
      id: json['id'],
      userId: json['user_id'],
      name: json['name'] ?? 'My Budget',
      totalAmount: (json['total_amount'] as num).toDouble(),
      currency: json['currency'],
      startDate: DateTime.parse(json['start_date']),
      endDate: DateTime.parse(json['end_date']),
      isActive: json['is_active'] ?? true,
      totalSpent: (json['total_spent'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class ExpenseModel extends Expense {
  const ExpenseModel({
    required super.id,
    required super.budgetId,
    required super.amount,
    required super.category,
    super.description,
    required super.spentAt,
  });

  factory ExpenseModel.fromJson(Map<String, dynamic> json) {
    return ExpenseModel(
      id: json['id'],
      budgetId: json['budget_id'],
      amount: (json['amount'] as num).toDouble(),
      category: json['category'],
      description: json['description'],
      spentAt: DateTime.parse(json['spent_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'amount': amount,
      'category': category,
      'description': description,
      'spent_at': spentAt.toIso8601String(),
    };
  }
}
