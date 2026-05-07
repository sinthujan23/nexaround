import 'package:equatable/equatable.dart';

class Budget extends Equatable {
  final String id;
  final String userId;
  final String name;
  final double totalAmount;
  final String currency;
  final DateTime startDate;
  final DateTime endDate;
  final bool isActive;
  final List<Expense> expenses;

  const Budget({
    required this.id,
    required this.userId,
    required this.name,
    required this.totalAmount,
    required this.currency,
    required this.startDate,
    required this.endDate,
    required this.isActive,
    required this.expenses,
  });

  double get spentAmount => expenses.fold(0, (sum, e) => sum + e.amount);
  double get remainingAmount => totalAmount - spentAmount;
  double get spentPercentage => totalAmount > 0 ? (spentAmount / totalAmount) : 0;
  bool get isOverBudget => spentAmount > totalAmount;
  double get overAmount => isOverBudget ? spentAmount - totalAmount : 0;
  int get daysLeft {
    final now = DateTime.now();
    return endDate.difference(now).inDays;
  }
  bool get isExpired => DateTime.now().isAfter(endDate);

  @override
  List<Object?> get props => [id, userId, name, totalAmount, currency, startDate, endDate, isActive, expenses];
}

class BudgetSummary extends Equatable {
  final String id;
  final String userId;
  final String name;
  final double totalAmount;
  final String currency;
  final DateTime startDate;
  final DateTime endDate;
  final bool isActive;
  final double totalSpent;

  const BudgetSummary({
    required this.id,
    required this.userId,
    required this.name,
    required this.totalAmount,
    required this.currency,
    required this.startDate,
    required this.endDate,
    required this.isActive,
    required this.totalSpent,
  });

  bool get isOverBudget => totalSpent > totalAmount;
  double get spentPercentage => totalAmount > 0 ? (totalSpent / totalAmount) : 0;

  @override
  List<Object?> get props => [id, userId, name, totalAmount, currency, startDate, endDate, isActive, totalSpent];
}

class Expense extends Equatable {
  final String id;
  final String budgetId;
  final double amount;
  final String category;
  final String? description;
  final DateTime spentAt;

  const Expense({
    required this.id,
    required this.budgetId,
    required this.amount,
    required this.category,
    this.description,
    required this.spentAt,
  });

  @override
  List<Object?> get props => [id, budgetId, amount, category, description, spentAt];
}
