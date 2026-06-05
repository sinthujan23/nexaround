import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nexaround_app/core/network/api_client.dart';
import '../models/budget_model.dart';
import '../../domain/entities/budget.dart';
import '../../domain/repositories/budget_repository.dart';

class BudgetRepositoryImpl implements BudgetRepository {
  final Dio _dio = ApiClient.instance;
  static const String _budgetCacheKey = 'cached_budget';

  Future<Budget?> getCachedBudget() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_budgetCacheKey);
      if (raw == null) return null;
      return BudgetModel.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  Future<void> _cacheBudget(Budget budget) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final model = budget as BudgetModel;
      await prefs.setString(_budgetCacheKey, jsonEncode(model.toJson()));
    } catch (_) {}
  }

  @override
  Future<Budget> getMyBudget() async {
    try {
      final response = await _dio.get('/api/v1/budget/');
      final budget = BudgetModel.fromJson(response.data);
      await _cacheBudget(budget);
      return budget;
    } catch (e) {
      rethrow;
    }
  }

  @override
  Future<List<BudgetSummary>> getBudgetHistory() async {
    try {
      final response = await _dio.get('/api/v1/budget/history');
      return (response.data as List)
          .map((e) => BudgetSummaryModel.fromJson(e))
          .toList();
    } catch (e) {
      rethrow;
    }
  }

  @override
  Future<Budget> getBudgetById(String budgetId) async {
    try {
      final response = await _dio.get('/api/v1/budget/$budgetId');
      return BudgetModel.fromJson(response.data);
    } catch (e) {
      rethrow;
    }
  }

  @override
  Future<Budget> setupBudget({
    required String name,
    required double totalAmount,
    required DateTime startDate,
    required DateTime endDate,
    String currency = 'USD',
  }) async {
    try {
      final response = await _dio.post(
        '/api/v1/budget/',
        data: {
          'name': name,
          'total_amount': totalAmount,
          'start_date': startDate.toIso8601String().split('T')[0],
          'end_date': endDate.toIso8601String().split('T')[0],
          'currency': currency,
        },
      );
      final budget = BudgetModel.fromJson(response.data);
      await _cacheBudget(budget);
      return budget;
    } catch (e) {
      rethrow;
    }
  }

  @override
  Future<Budget> closeBudget() async {
    try {
      final response = await _dio.post('/api/v1/budget/close');
      final budget = BudgetModel.fromJson(response.data);
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_budgetCacheKey);
      return budget;
    } catch (e) {
      rethrow;
    }
  }

  @override
  Future<Expense> addExpense({
    required double amount,
    required String category,
    String? description,
  }) async {
    try {
      final response = await _dio.post(
        '/api/v1/budget/expense',
        data: {
          'amount': amount,
          'category': category,
          'description': description,
          'spent_at': DateTime.now().toIso8601String(),
        },
      );
      return ExpenseModel.fromJson(response.data);
    } catch (e) {
      rethrow;
    }
  }
}
