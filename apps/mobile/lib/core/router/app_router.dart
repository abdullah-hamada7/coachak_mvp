import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/register_screen.dart';
import '../../features/coach/presentation/coach_screen.dart';
import '../../features/food/presentation/food_log_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/onboarding/presentation/onboarding_screen.dart';
import '../../features/onboarding/presentation/welcome_screen.dart';
import '../../features/plans/presentation/plans_screen.dart';
import '../../features/progress/presentation/progress_screen.dart';
import '../../features/reminders/presentation/reminders_screen.dart';
import '../../features/shell/presentation/main_shell.dart';
import '../../features/subscription/presentation/paywall_screen.dart';
import '../../features/workout_cv/presentation/form_session_summary.dart';
import '../../features/workout_cv/presentation/therapist_summary_screen.dart';
import '../../features/workout_cv/presentation/workout_cv_screen.dart';
import 'router_refresh.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/login',
    refreshListenable: RouterRefresh.instance,
    redirect: (context, state) => routerRedirect(state.matchedLocation),
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, _) => const RegisterScreen()),
      GoRoute(path: '/welcome', builder: (_, _) => const WelcomeScreen()),
      GoRoute(path: '/onboarding', builder: (_, _) => const OnboardingScreen()),
      GoRoute(path: '/workout-cv', builder: (_, _) => const WorkoutCvScreen()),
      GoRoute(
        path: '/therapist-summary',
        builder: (context, state) {
          final summary = state.extra;
          if (summary is! FormSessionSummary) {
            return const Scaffold(
              body: Center(child: Text('لا توجد بيانات جلسة')),
            );
          }
          return TherapistSummaryScreen(summary: summary);
        },
      ),
      GoRoute(path: '/food', builder: (_, _) => const FoodLogScreen()),
      GoRoute(path: '/reminders', builder: (_, _) => const RemindersScreen()),
      GoRoute(
        path: '/paywall',
        builder: (context, state) => PaywallScreen(highlightTier: state.extra as String?),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) => MainShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/coach', builder: (_, _) => const CoachScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/plans', builder: (_, _) => const PlansScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/progress', builder: (_, _) => const ProgressScreen()),
          ]),
        ],
      ),
    ],
  );
});
