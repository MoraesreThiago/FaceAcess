enum UserProfile { admin, porta }

extension UserProfileExtension on UserProfile {
  String get label {
    switch (this) {
      case UserProfile.admin:
        return 'Administrador';
      case UserProfile.porta:
        return 'Acesso - Porta';
    }
  }
}
