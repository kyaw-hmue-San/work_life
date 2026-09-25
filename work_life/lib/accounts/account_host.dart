import 'dart:async';

import 'package:flutter/material.dart';

import '../app.dart';
import '../notifications/reminder_notifications.dart';
import '../workspace/workspace_repository.dart';
import 'account_config.dart';
import 'account_screen.dart';
import 'account_service.dart';

class AccountHost extends StatefulWidget {
  const AccountHost({
    super.key,
    required this.accounts,
    this.repositoryFactory,
    this.notifications,
  });
  final AccountService accounts;
  final ReminderNotifications? notifications;
  final WorkspaceRepository Function(String databaseName)? repositoryFactory;
  @override
  State<AccountHost> createState() => _AccountHostState();
}

class _AccountHostState extends State<AccountHost> {
  late WorkspaceRepository repository;
  late String databaseName;
  @override
  void initState() {
    super.initState();
    databaseName = _name();
    repository = _make(databaseName);
    widget.accounts.addListener(_changed);
  }

  String _name() =>
      accountDatabaseName(widget.accounts.namespace, widget.accounts.user?.id);
  WorkspaceRepository _make(String name) =>
      widget.repositoryFactory?.call(name) ??
      SqliteWorkspaceRepository(databaseName: name);
  void _close(WorkspaceRepository old) {
    if (old is SqliteWorkspaceRepository) {
      unawaited(
        (widget.notifications?.idle ?? Future<void>.value())
            .then((_) => old.close())
            .catchError((Object _) {}),
      );
    }
  }

  void _changed() {
    if (!mounted) return;
    final next = _name();
    if (databaseName != next) {
      final old = repository;
      repository = _make(next);
      databaseName = next;
      WidgetsBinding.instance.addPostFrameCallback((_) => _close(old));
    }
    setState(() {});
  }

  @override
  void dispose() {
    widget.accounts.removeListener(_changed);
    _close(repository);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => WorkLifeApp(
    // Changing identity destroys the entire Navigator, including old details/forms.
    key: ValueKey('$databaseName:${widget.accounts.recovering}'),
    repository: repository,
    notifications: widget.notifications,
    notificationScope: databaseName,
    accountBuilder: (_) => AccountScreen(accounts: widget.accounts),
    accountLabel: widget.accounts.user?.email ?? 'Guest workspace',
    accountNotice: widget.accounts.notice,
    homeOverride: widget.accounts.recovering
        ? AccountScreen(accounts: widget.accounts)
        : null,
  );
}
