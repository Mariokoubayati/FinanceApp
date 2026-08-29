import Foundation
import Supabase

// MARK: - Fill in your Supabase project credentials below
// Find them at: https://supabase.com/dashboard/project/<your-project>/settings/api
private enum SupabaseConfig {
    static let url     = "https://ejgjgqeksfqkffmvkqkj.supabase.co"
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVqZ2pncWVrc2Zxa2ZmbXZrcWtqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzc2Mjk3OTAsImV4cCI6MjA5MzIwNTc5MH0.bFUBpjGXnBGgsItSXpZ3LgCDcWsRouSDwMMhKYC6eTw"
}

let supabase = SupabaseClient(
    supabaseURL: URL(string: SupabaseConfig.url)!,
    supabaseKey: SupabaseConfig.anonKey
)
