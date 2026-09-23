import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:nexaround_app/features/auth/presentation/pages/login_page.dart';
import 'package:nexaround_app/features/auth/presentation/pages/register_page.dart';
import 'package:nexaround_app/features/auth/presentation/pages/home_page.dart';
import 'package:nexaround_app/features/onboarding/presentation/pages/onboarding_page.dart';
import 'package:nexaround_app/features/onboarding/presentation/pages/splash_screen.dart';
import 'package:nexaround_app/features/manual_mode/presentation/pages/map_page.dart';
import 'package:nexaround_app/features/travel_stories/presentation/pages/travel_journal_page.dart';
import 'package:nexaround_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:nexaround_app/features/auth/presentation/bloc/auth_state.dart';
import 'package:nexaround_app/core/utils/go_router_refresh_stream.dart';
import 'package:nexaround_app/core/services/cache_service.dart';
import 'package:nexaround_app/features/experiences/presentation/pages/experience_link_page.dart';

class AppRouter {
  static GoRouter createRouter(AuthBloc authBloc) {
    return GoRouter(
      initialLocation: '/',
      refreshListenable: GoRouterRefreshStream(authBloc.stream),
      redirect: (context, state) {
        final authState = authBloc.state;

        // A shared experience link, https://nexaround.com/e/<id>, which Android
        // App Links and iOS Universal Links hand to the router as /e/<id>. A
        // signed-in user gets it on top of Home, so Back returns to Home and a
        // link arriving while the app is open keeps Home's state. Anyone else
        // sees it on its own; the package endpoint needs no account.
        if (state.matchedLocation.startsWith('/e/') &&
            CacheService.isLoggedIn() &&
            authState is! AuthUnauthenticated) {
          return '/home${state.matchedLocation}';
        }

        // Define public routes that don't require authentication
        final bool isPublicRoute = state.matchedLocation == '/login' || 
                                  state.matchedLocation == '/register' || 
                                  state.matchedLocation == '/otp-verify' || 
                                  state.matchedLocation == '/' || 
                                  state.matchedLocation == '/onboarding' ||
                                  state.matchedLocation.startsWith('/e/');

        // 1. If not authenticated and trying to access a private route -> Go to Login
        if (authState is AuthUnauthenticated && !isPublicRoute) {
          return '/login';
        }
        
        // 2. If authenticated and trying to access login/register -> Go to Home
        if (authState is AuthAuthenticated && (state.matchedLocation == '/login' || state.matchedLocation == '/register')) {
          return '/home';
        }

        return null;
      },
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const AnimatedSplashScreen(),
        ),
        GoRoute(
          path: '/login',
          pageBuilder: (context, state) => CustomTransitionPage(
            key: state.pageKey,
            child: const LoginPage(),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(opacity: animation, child: child);
            },
          ),
        ),
        GoRoute(
          path: '/register',
          pageBuilder: (context, state) => CustomTransitionPage(
            key: state.pageKey,
            child: const RegisterPage(),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(opacity: animation, child: child);
            },
          ),
        ),
        GoRoute(
          path: '/onboarding',
          pageBuilder: (context, state) => CustomTransitionPage(
            key: state.pageKey,
            child: const OnboardingPage(),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(opacity: animation, child: child);
            },
          ),
        ),
        GoRoute(
          path: '/home',
          pageBuilder: (context, state) => CustomTransitionPage(
            key: state.pageKey,
            child: HomePage(),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(opacity: animation, child: child);
            },
          ),
          routes: [
            GoRoute(
              path: 'e/:id',
              builder: (context, state) =>
                  ExperienceLinkPage(packageId: state.pathParameters['id']!),
            ),
          ],
        ),
        GoRoute(
          path: '/e/:id',
          builder: (context, state) => ExperienceLinkPage(
            packageId: state.pathParameters['id']!,
            standalone: true,
          ),
        ),
        GoRoute(
          path: '/map',
          pageBuilder: (context, state) => CustomTransitionPage(
            key: state.pageKey,
            child: const MapPage(),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(opacity: animation, child: child);
            },
          ),
        ),
        GoRoute(
          path: '/journal',
          pageBuilder: (context, state) => CustomTransitionPage(
            key: state.pageKey,
            child: const TravelJournalPage(),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(opacity: animation, child: child);
            },
          ),
        ),
      ],
    );
  }
}
