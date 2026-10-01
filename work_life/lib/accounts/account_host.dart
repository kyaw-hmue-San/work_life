import 'dart:async';

import 'package:flutter/material.dart';

import '../app.dart';
import '../notifications/reminder_notifications.dart';
import '../sync/local_sync_store.dart';
import '../sync/supabase_workspace_remote.dart';
import '../sync/workspace_sync_coordinator.dart';
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
  WorkspaceSyncCoordinator? sync;
  late String databaseName;
  late String? userId;
  bool guestChosen = false;
  @override
  void initState() {
    super.initState();
    userId = widget.accounts.user?.id;
    databaseName = _name();
    repository = _make(databaseName);
    sync = _makeSync();
    widget.accounts.addListener(_changed);
  }

  String _name() =>
      accountDatabaseName(widget.accounts.namespace, widget.accounts.user?.id);
  WorkspaceRepository _make(String name) =>
      widget.repositoryFactory?.call(name) ??
      SqliteWorkspaceRepository(databaseName: name);
  WorkspaceSyncCoordinator? _makeSync() {
    final account = widget.accounts;
    final identity = account.user;
    final localRepository = repository;
    if (identity == null ||
        account is! SupabaseAccounts ||
        localRepository is! SqliteWorkspaceRepository) {
      return null;
    }
    return WorkspaceSyncCoordinator(
      workspaceId: identity.id,
      local: LocalSyncStore(localRepository.database),
      remote: SupabaseWorkspaceRemote(account.client),
    );
  }

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
    final nextUserId = widget.accounts.user?.id;
    if (userId != nextUserId) {
      // Account sign-out returns to the account-first gate. Guest mode must be
      // deliberately chosen for each signed-out app session.
      guestChosen = false;
      userId = nextUserId;
    }
    final next = _name();
    if (databaseName != next) {
      final old = repository;
      final oldSync = sync;
      repository = _make(next);
      sync = _makeSync();
      databaseName = next;
      oldSync?.dispose();
      WidgetsBinding.instance.addPostFrameCallback((_) => _close(old));
    }
    setState(() {});
  }

  @override
  void dispose() {
    widget.accounts.removeListener(_changed);
    sync?.dispose();
    _close(repository);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accountGate =
        widget.accounts.configured &&
        widget.accounts.user == null &&
        !guestChosen;
    return WorkLifeApp(
      // Changing identity destroys the entire Navigator, including old details/forms.
      key: ValueKey('$databaseName:${widget.accounts.recovering}:$accountGate'),
      repository: repository,
      sync: sync,
      notifications: widget.notifications,
      notificationScope: databaseName,
      accountBuilder: (_) => AccountScreen(accounts: widget.accounts),
      accountLabel: widget.accounts.user?.email ?? 'Offline guest workspace',
      accountNotice: widget.accounts.notice,
      homeOverride: widget.accounts.recovering
          ? AccountScreen(accounts: widget.accounts, startup: true)
          : accountGate
          ? AccountScreen(
              accounts: widget.accounts,
              startup: true,
              onContinueOffline: () => setState(() => guestChosen = true),
            )
          : null,
    );
  }
}
