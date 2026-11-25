class AuthSession {
  const AuthSession({required this.userId, this.email});

  final String userId;
  final String? email;

  @override
  bool operator ==(Object other) =>
      other is AuthSession && other.userId == userId && other.email == email;

  @override
  int get hashCode => Object.hash(userId, email);
}
