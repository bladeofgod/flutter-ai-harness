/// Feature、跨 Feature API、Controller、页面与路由的公共入口。
library;

export 'api/auth_api.dart' show AuthApi;
export 'api/current_user_provider.dart' show CurrentUserProvider;
export 'api/profile_dashboard_api.dart' show ProfileDashboardApi;
export 'feature_auth/routes.dart'
    show
        buildLoginRoutes,
        buildRegistrationRoutes,
        loginRoutePath,
        passwordRoutePath,
        recoveryRoutePath,
        registrationRoutePath;
export 'feature_profile/routes.dart' show buildProfileRoutes, profileRoutePath;
export 'feature_welcome/routes.dart' show buildWelcomeRoutes, welcomeRoutePath;
export 'features_registry.dart' show FeaturesRegistry;
