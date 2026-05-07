import 'package:equatable/equatable.dart';

abstract class BudgetEvent extends Equatable {
  const BudgetEvent();

  @override
  List<Object?> get props => [];
}

class FetchBudget extends BudgetEvent {}

class FetchBudgetHistory extends BudgetEvent {}

class FetchBudgetById extends BudgetEvent {
  final String budgetId;
  const FetchBudgetById(this.budgetId);

  @override
  List<Object?> get props => [budgetId];
}

class SetupBudgetEvent extends BudgetEvent {
  final String name;
  final double totalAmount;
  final DateTime startDate;
  final DateTime endDate;
  final String currency;

  const SetupBudgetEvent({
    required this.name,
    required this.totalAmount,
    required this.startDate,
    required this.endDate,
    this.currency = 'LKR',
  });

  @override
  List<Object?> get props => [name, totalAmount, startDate, endDate, currency];
}

class CloseBudgetEvent extends BudgetEvent {}

class AddExpenseEvent extends BudgetEvent {
  final double amount;
  final String category;
  final String? description;

  const AddExpenseEvent({
    required this.amount,
    required this.category,
    this.description,
  });

  @override
  List<Object?> get props => [amount, category, description];
}
