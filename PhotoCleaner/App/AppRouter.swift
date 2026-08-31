import Observation

@MainActor
@Observable
final class AppRouter {
    var path: [AppRoute] = []

    func navigate(to route: AppRoute) {
        path.append(route)
    }

    func popToRoot() {
        path.removeAll()
    }
}
