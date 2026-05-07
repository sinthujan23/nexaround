import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/repositories/budget_repository.dart';
import 'budget_event.dart';
import 'budget_state.dart';

class BudgetBloc extends Bloc<BudgetEvent, BudgetState> {
  final BudgetRepository _repository;

  BudgetBloc(this._repository) : super(BudgetInitial()) {
    on<FetchBudget>(_onFetchBudget);
    on<FetchBudgetHistory>(_onFetchBudgetHistory);
    on<FetchBudgetById>(_onFetchBudgetById);
    on<SetupBudgetEvent>(_onSetupBudget);
    on<CloseBudgetEvent>(_onCloseBudget);
    on<AddExpenseEvent>(_onAddExpense);
  }

  Future<void> _onFetchBudget(FetchBudget event, Emitter<BudgetState> emit) async {
    emit(BudgetLoading());
    try {
      final budget = await _repository.getMyBudget();
      emit(BudgetLoaded(budget));
    } catch (e) {
      if (e.toString().contains('404')) {
        emit(NoBudgetFound());
      } else {
        emit(BudgetError(e.toString()));
      }
    }
  }

  Future<void> _onFetchBudgetHistory(FetchBudgetHistory event, Emitter<BudgetState> emit) async {
    emit(BudgetHistoryLoading());
    try {
      final budgets = await _repository.getBudgetHistory();
      emit(BudgetHistoryLoaded(budgets));
    } catch (e) {
      emit(BudgetError(e.toString()));
    }
  }

  Future<void> _onFetchBudgetById(FetchBudgetById event, Emitter<BudgetState> emit) async {
    emit(BudgetDetailLoading());
    try {
      final budget = await _repository.getBudgetById(event.budgetId);
      emit(BudgetDetailLoaded(budget));
    } catch (e) {
      emit(BudgetError(e.toString()));
    }
  }

  Future<void> _onSetupBudget(SetupBudgetEvent event, Emitter<BudgetState> emit) async {
    emit(BudgetLoading());
    try {
      final budget = await _repository.setupBudget(
        name: event.name,
        totalAmount: event.totalAmount,
        startDate: event.startDate,
        endDate: event.endDate,
        currency: event.currency,
      );
      emit(BudgetLoaded(budget));
    } catch (e) {
      emit(BudgetError(e.toString()));
    }
  }

  Future<void> _onCloseBudget(CloseBudgetEvent event, Emitter<BudgetState> emit) async {
    emit(BudgetLoading());
    try {
      final closedBudget = await _repository.closeBudget();
      emit(BudgetClosed(closedBudget));
    } catch (e) {
      emit(BudgetError(e.toString()));
    }
  }

  Future<void> _onAddExpense(AddExpenseEvent event, Emitter<BudgetState> emit) async {
    if (state is BudgetLoaded) {
      try {
        await _repository.addExpense(
          amount: event.amount,
          category: event.category,
          description: event.description,
        );
        final updatedBudget = await _repository.getMyBudget();
        emit(BudgetLoaded(updatedBudget));
      } catch (e) {
        emit(BudgetError(e.toString()));
      }
    }
  }
}
