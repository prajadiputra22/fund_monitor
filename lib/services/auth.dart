import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  final SupabaseClient _client = Supabase.instance.client;

  Future<AuthResponse> login({
    required String usernameOrEmail,
    required String password,
  }) async {
    String email = usernameOrEmail.trim();

    if (!email.contains('@')) {
      final result = await _client.rpc(
        'get_email_by_username',
        params: {'input_username': email},
      );

      if (result == null) {
        throw AuthException('Username tidak ditemukan');
      }
      email = result as String;
    }

    final response = await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );

    if (response.session == null) {
      throw AuthException('Login gagal, periksa kembali kredensial Anda');
    }

    final userId = response.user?.id;
    if (userId != null) {
      await _client
          .from('profiles')
          .update({'last_login_at': DateTime.now().toIso8601String()})
          .eq('id', userId);
    }

    return response;
  }

  Future<void> logout() async {
    await _client.auth.signOut();
  }

  bool get isLoggedIn => _client.auth.currentSession != null;

  Future<bool> isSessionExpired() async {
    final session = _client.auth.currentSession;
    if (session == null) return true;

    final userId = session.user.id;
    final data = await _client
        .from('profiles')
        .select('last_login_at')
        .eq('id', userId)
        .maybeSingle();

    final lastLoginStr = data?['last_login_at'] as String?;
    if (lastLoginStr == null) return true;

    final lastLogin = DateTime.parse(lastLoginStr);
    final expired = DateTime.now().difference(lastLogin).inHours >= 24;

    if (expired) {
      await logout();
    }
    return expired;
  }
}