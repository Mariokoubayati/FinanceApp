import SwiftUI
import Supabase

@Observable
@MainActor
final class AppState {
    var session: Session?
    var profile: Profile?
    var isLoading = true

    var isAuthenticated: Bool { session != nil }
    var userId: UUID?          { session?.user.id }

    func restoreSession() async {
        do {
            session = try await supabase.auth.session
            if let uid = userId { await loadProfile(userId: uid) }
        } catch {
            session = nil
        }
        isLoading = false
    }

    func loadProfile(userId: UUID) async {
        profile = try? await supabase
            .from("profiles")
            .select()
            .eq("id", value: userId)
            .single()
            .execute()
            .value
    }

    func signOut() async {
        try? await supabase.auth.signOut()
        session = nil
        profile = nil
    }
}
