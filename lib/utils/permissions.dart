/// У бизнесмена должен быть привязанный склад (`user.warehouse`), иначе доступен только профиль.
bool businessmanHasWarehouse(Map<String, dynamic>? user) {
  if ((user?['role'] as String?) != 'businessman') return true;
  final w = user!['warehouse'];
  if (w == null) return false;
  if (w is int) return w != 0;
  if (w is num) return w.toInt() != 0;
  final s = w.toString().trim();
  if (s.isEmpty || s == '0') return false;
  final parsed = int.tryParse(s);
  if (parsed != null) return parsed != 0;
  return true;
}

bool sectionIsAllowed(Map<String, dynamic>? perms, String sectionKey) {
  final a = perms?[sectionKey];
  if (a is! Map) return false;
  return (a['view'] == true) || (a['create'] == true) || (a['edit'] == true) || (a['delete'] == true);
}

bool sellerCanAccessSection(Map<String, dynamic> user, String sectionKey, Map<String, dynamic>? allowedPerms) {
  final perms = allowedPerms ?? (user['allowed_perms'] as Map<String, dynamic>?);
  if (sectionKey == 'history') {
    if (sectionIsAllowed(perms, 'history')) return true;
    return ['sales', 'returns', 'transfers', 'debts', 'expenses'].any((k) {
      final p = perms?[k];
      return p is Map && p['view'] == true;
    });
  }
  return sectionIsAllowed(perms, sectionKey);
}

const sellerMenuHiddenSectionKeys = <String>['stores'];
const nasiyaSectionKeys = <String>['debts', 'sales', 'history', 'referral'];
const clientSectionKeys = <String>['debts', 'history', 'referral'];

bool canAccessSection(Map<String, dynamic>? user, String sectionKey, Map<String, dynamic>? allowedPerms) {
  final role = user?['role'] as String?;
  // Profile should be accessible for any logged-in role.
  if (sectionKey == 'profile') return user != null;
  if (role == 'platform') return true;
  if (role == 'moderator' && (user?['moderator_scope'] as String?) == 'platform') return true;
  if (role == 'businessman') {
    if (!businessmanHasWarehouse(user)) return sectionKey == 'profile';
    return true;
  }
  if (role == 'moderator' && (user?['moderator_scope'] as String?) == 'business') {
    return clientSectionKeys.contains(sectionKey);
  }
  if (role == 'client') return clientSectionKeys.contains(sectionKey);
  if (role == 'nasiya') return nasiyaSectionKeys.contains(sectionKey);
  if (role == 'seller') {
    return sellerCanAccessSection(user ?? const {}, sectionKey, allowedPerms);
  }
  return false;
}

