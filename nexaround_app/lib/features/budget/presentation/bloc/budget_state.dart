import 'package:equatable/equatable.dart';
import '../../domain/entities/budget.dart';

abstract class BudgetState extends Equatable {
  const BudgetState();

  @override
  List<Object?> get props => [];
}

class BudgetInitial extends BudgetState {}

class BudgetLoading extends BudgetState {}
class BudgetHistoryLoading extends BudgetState {}
class BudgetDetailLoading extends BudgetState {}

class BudgetLoaded extends BudgetState {
  final Budget budget;

  const BudgetLoaded(this.budget);

  @override
  List<Object?> get props => [budget];
}

class NoBudgetFound extends BudgetState {}

class BudgetClosed extends BudgetState {
  final Budget closedBudget;
  const BudgetClosed(this.closedBudget);

  @override
  List<Object?> get props => [closedBudget];
}

class BudgetHistoryLoaded extends BudgetState {
  final List<BudgetSummary> budgets;
  const BudgetHistoryLoaded(this.budgets);

  @override
  List<Object?> get props => [budgets];
}

class BudgetDetailLoaded extends BudgetState {
  final Budget budget;
  const BudgetDetailLoaded(this.budget);

  @override
  List<Object?> get props => [budget];
}

class BudgetError extends BudgetState {
  final String message;

  const BudgetError(this.message);

  @override
  List<Object?> get props => [message];
}
