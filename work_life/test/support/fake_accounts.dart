import 'package:work_life/accounts/account_service.dart';

class FakeAccounts extends AccountService {
  AccountIdentity? current;
  bool recovery = false, available = true, failSignIn = false;
  int googleRequests = 0, resets = 0, signups = 0;
  String? updatedPassword;
  @override bool get configured => available;
  @override String get namespace => 'test-project';
  @override AccountIdentity? get user => current;
  @override bool get recovering => recovery;
  @override String? get notice => null;
  void setUser(String? id, {bool recovering = false}) {
    current = id == null ? null : AccountIdentity(id: id, email: '$id@example.com');
    recovery = recovering;
    notifyListeners();
  }
  @override Future<void> signIn(String email, String password) async {
    if (failSignIn) throw const AccountFailure('Email or password is incorrect.');
    setUser('alice');
  }
  @override Future<bool> signUp(String email, String password) async { signups++; return false; }
  @override Future<void> google() async { googleRequests++; }
  @override Future<void> resendConfirmation(String email) async {}
  @override Future<void> resetPassword(String email) async { resets++; }
  @override Future<void> updatePassword(String password) async { updatedPassword = password; recovery = false; notifyListeners(); }
  @override Future<void> signOut() async => setUser(null);
}
