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
  /// A shared package (nexaround.com/e/<id>) opened while signed out. Held
  /// until sign-in completes, then opened over Home. In memory only: if the
  /// app is killed during sign-in, the user lands on Home as usual.
  static String? _pendingPackageId;

  /// The package id in /e/<id> or /home/e/<id>.
  static String? _sharedPackageId(GoRouterState state) {
    final segments = state.uri.pathSegments;
    final i = segments.indexOf('e');
    return (i >= 0 && i + 1 < segments.length) ? segments[i + 1] : null;
  }

  static GoRouter createRouter(AuthBloc authBloc) {
    return GoRouter(
      initialLocation: '/',
      refreshListenable: GoRouterRefreshStream(authBloc.stream),
      redirect: (context, state) {
        final authState = authBloc.state;

        final location = state.matchedLocation;

        // A shared experience link, https://nexaround.com/e/<id>, which Android
        // App Links and iOS Universal Links hand to the router as /e/<id>.
        if (location.startsWith('/e/')) {
          // Signed in: open it on top of Home, so Back returns to Home and a
          // link arriving while the app is open keeps Home's state.
          if (CacheService.isLoggedIn() && authState is! AuthUnauthenticated) {
            return '/home$location';
          }
          // Signed out: sign in first, then it opens (below). A first-time
          // user sees onboarding, which hands over to the login screen.
          _pendingPackageId = _sharedPackageId(state);
          return CacheService.isFirstTime() ? '/onboarding' : '/login';
        }

        // Just signed in with a shared package waiting: open it over Home.
        // The OTP and social sign-in screens are pushed on top of these
        // routes, so the router still reports login, register or onboarding.
        if (authState is AuthAuthenticated &&
            _pendingPackageId != null &&
            (location == '/login' ||
                location == '/register' ||
                location == '/onboarding')) {
          final id = _pendingPackageId;
          _pendingPackageId = null;
          return '/home/e/$id';
        }

        // Define public routes that don't require authentication
        final bool isPublicRoute = location == '/login' ||
                                  location == '/register' ||
                                  location == '/otp-verify' ||
                                  location == '/' ||
                                  location == '/onboarding';

        // 1. If not authenticated and trying to access a private route -> Go to Login
        if (authState is AuthUnauthenticated && !isPublicRoute) {
          // A session that ran out under an open shared package: reopen it
          // once the user signs back in.
          if (location.startsWith('/home/e/')) {
            _pendingPackageId = _sharedPackageId(state);
          }
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
        // Matched so the redirect above can act on /e/<id>; it always sends
        // the user on (to /home/e/<id>, or to sign in), so this page is a
        // fallback only.
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
