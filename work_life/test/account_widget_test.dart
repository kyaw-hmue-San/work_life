import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:work_life/accounts/account_config.dart';
import 'package:work_life/accounts/account_host.dart';
import 'package:work_life/accounts/account_screen.dart';
import 'package:work_life/captures/capture.dart';
import 'support/fake_accounts.dart';
import 'support/memory_workspace.dart';

void main() {
  void roomy(WidgetTester tester) {
    tester.view.physicalSize = const Size(800,1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }
  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }
  testWidgets('signup confirms password, waits for email; Google launch is not login', (tester) async {
    roomy(tester);
    final accounts = FakeAccounts();
    await tester.pumpWidget(MaterialApp(home: AccountScreen(accounts: accounts)));
    await tap(tester, find.text('Continue with Google'));
    expect(accounts.googleRequests, 1);
    expect(accounts.user, isNull);
    await tap(tester, find.text('New here? Create an account'));
    await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'person@example.com');
    await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'safe-password');
    await tester.enterText(find.widgetWithText(TextFormField, 'Confirm password'), 'different');
    await tap(tester, find.text('Create account'));
    expect(find.text('Passwords do not match.'), findsOneWidget);
    expect(accounts.signups, 0);
    await tester.enterText(find.widgetWithText(TextFormField, 'Confirm password'), 'safe-password');
    await tap(tester, find.text('Create account'));
    expect(accounts.signups, 1);
    expect(accounts.user, isNull);
    expect(find.textContaining('Check your email for a confirmation link'), findsOneWidget);
    await tap(tester, find.text('Forgot password?'));
    expect(accounts.resets, 1);
  });
  testWidgets('failed sign-in retains email and can be retried', (tester) async {
    roomy(tester);
    final accounts = FakeAccounts()..failSignIn = true;
    await tester.pumpWidget(MaterialApp(home: AccountScreen(accounts: accounts)));
    await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'person@example.com');
    await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'wrong-password');
    await tap(tester, find.text('Sign in'));
    expect(find.text('Email or password is incorrect.'), findsOneWidget);
    expect(find.text('person@example.com'), findsOneWidget);
    accounts.failSignIn = false;
    await tap(tester, find.text('Sign in'));
    expect(accounts.user!.id, 'alice');
  });
  testWidgets('account changes destroy old routes and restore the right workspace', (tester) async {
    roomy(tester);
    final accounts = FakeAccounts();
    final repos = <String, MemoryWorkspace>{};
    repos[accountDatabaseName(accounts.namespace, null)] = MemoryWorkspace()..captures.add(Capture.create('Guest original note'));
    await tester.pumpWidget(AccountHost(accounts: accounts, repositoryFactory: (name) => repos.putIfAbsent(name, MemoryWorkspace.new)));
    await tester.pumpAndSettle();
    await tap(tester, find.widgetWithText(NavigationDestination, 'Inbox'));
    await tap(tester, find.text('Guest original note'));
    expect(find.text('Keep the original.'), findsOneWidget);
    accounts.setUser('alice');
    await tester.pumpAndSettle();
    expect(find.text('Keep the original.'), findsNothing);
    expect(find.text('Guest original note'), findsNothing);
    await tap(tester, find.widgetWithText(NavigationDestination, 'More'));
    await tap(tester, find.text('Account'));
    expect(find.text('alice@example.com'), findsOneWidget);
    await tap(tester, find.text('Sign out on this device'));
    expect(find.text('alice@example.com'), findsNothing);
    await tap(tester, find.widgetWithText(NavigationDestination, 'Inbox'));
    expect(find.text('Guest original note'), findsOneWidget);
    accounts.setUser('bob');
    await tester.pumpAndSettle();
    expect(find.text('Guest original note'), findsNothing);
    expect(repos[accountDatabaseName(accounts.namespace, 'bob')]!.captures, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('recovery uses its own form and exits after password update', (tester) async {
    roomy(tester);
    final accounts = FakeAccounts()..setUser('alice', recovering: true);
    await tester.pumpWidget(AccountHost(accounts: accounts, repositoryFactory: (_) => MemoryWorkspace()));
    await tester.pumpAndSettle();
    expect(find.text('Choose a new password'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    await tester.enterText(find.widgetWithText(TextFormField, 'New password'), 'new-safe-password');
    await tester.enterText(find.widgetWithText(TextFormField, 'Confirm password'), 'new-safe-password');
    await tap(tester, find.text('Save new password'));
    expect(accounts.updatedPassword, 'new-safe-password');
    expect(find.byType(NavigationBar), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
