import 'package:flutter/material.dart';

import 'account_service.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key, required this.accounts});
  final AccountService accounts;
  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final form = GlobalKey<FormState>();
  final email = TextEditingController();
  final password = TextEditingController();
  final confirmation = TextEditingController();
  bool creating = false, busy = false, showPassword = false;
  String? error, message;
  @override
  void dispose() {
    email.dispose();
    password.dispose();
    confirmation.dispose();
    super.dispose();
  }

  Future<void> request(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
      message = null;
    });
    try {
      await action();
    } on AccountFailure catch (failure) {
      if (mounted) setState(() => error = failure.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Couldn’t complete that request. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  bool validEmail() {
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email.text.trim())) {
      setState(() => error = 'Enter your email address first.');
      return false;
    }
    return true;
  }

  void info(String value) {
    if (mounted) setState(() => message = value);
  }

  Future<void> submit() async {
    if (!(form.currentState?.validate() ?? false)) return;
    await request(() async {
      final service = widget.accounts;
      if (service.recovering) {
        await service.updatePassword(password.text);
        if (!mounted) return;
        password.clear();
        confirmation.clear();
        info('Password updated.');
      } else if (creating) {
        final signedIn = await service.signUp(email.text.trim(), password.text);
        if (!mounted) return;
        password.clear();
        confirmation.clear();
        if (!signedIn) {
          info(
            'Check your email for a confirmation link. Open it on this device, then sign in. If you already have an account, sign in or reset your password.',
          );
        }
      } else {
        await service.signIn(email.text.trim(), password.text);
      }
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.accounts,
    builder: (context, _) {
      final service = widget.accounts;
      final recovery = service.recovering;
      final signedIn = service.user != null;
      return PopScope(
        canPop: !busy && !recovery,
        child: Scaffold(
          appBar: AppBar(
            title: Text(recovery ? 'Choose a new password' : 'Account'),
            automaticallyImplyLeading: !recovery,
          ),
          body: SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(
                        signedIn
                            ? Icons.account_circle_outlined
                            : Icons.spa_outlined,
                        size: 48,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        recovery
                            ? 'A fresh start for your sign-in.'
                            : signedIn
                            ? 'Your space, your account.'
                            : 'Make a space of your own.',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 16),
                      if (service.notice != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Text(service.notice!),
                        ),
                      if (!service.configured) ...[
                        const Text(
                          'Account sign-in is not available in this build yet. You can keep capturing, planning, and focusing in your guest workspace.',
                        ),
                        const SizedBox(height: 16),
                        OutlinedButton(
                          onPressed: () => Navigator.maybePop(context),
                          child: const Text('Continue with local workspace'),
                        ),
                      ] else if (signedIn && !recovery) ...[
                        SelectableText(
                          service.user!.email,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'This account has its own workspace on this device. Cloud backup and syncing are not connected yet.',
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Guest notes stay in the guest workspace. Sign out to return to them. Signing out keeps this account’s saved records on this device for your next sign-in.',
                        ),
                        const SizedBox(height: 24),
                        OutlinedButton(
                          onPressed: busy
                              ? null
                              : () => request(service.signOut),
                          child: const Text('Sign out on this device'),
                        ),
                      ] else ...[
                        if (!recovery) ...[
                          const Text(
                            'Sign in with Google or email. Your guest notes remain separate and will not be moved or uploaded.',
                          ),
                          const SizedBox(height: 20),
                          OutlinedButton(
                            onPressed: busy
                                ? null
                                : () => request(() async {
                                    await service.google();
                                    info(
                                      'Finish signing in through Google in your browser. If you close it, you can try again here.',
                                    );
                                  }),
                            child: const Padding(
                              padding: EdgeInsets.all(12),
                              child: Text('Continue with Google'),
                            ),
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            'Or use email',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 20),
                        ],
                        Form(
                          key: form,
                          child: AbsorbPointer(
                            absorbing: busy,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (!recovery) ...[
                                  TextFormField(
                                    controller: email,
                                    keyboardType: TextInputType.emailAddress,
                                    autofillHints: const [AutofillHints.email],
                                    autocorrect: false,
                                    decoration: const InputDecoration(
                                      labelText: 'Email',
                                    ),
                                    validator: (value) =>
                                        RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                                            .hasMatch((value ?? '').trim())
                                        ? null
                                        : 'Enter a valid email address.',
                                  ),
                                  const SizedBox(height: 16),
                                ],
                                TextFormField(
                                  controller: password,
                                  obscureText: !showPassword,
                                  autocorrect: false,
                                  enableSuggestions: false,
                                  autofillHints: [
                                    creating || recovery
                                        ? AutofillHints.newPassword
                                        : AutofillHints.password,
                                  ],
                                  decoration: InputDecoration(
                                    labelText: recovery
                                        ? 'New password'
                                        : 'Password',
                                    suffixIcon: IconButton(
                                      tooltip: showPassword
                                          ? 'Hide password'
                                          : 'Show password',
                                      onPressed: () => setState(
                                        () => showPassword = !showPassword,
                                      ),
                                      icon: Icon(
                                        showPassword
                                            ? Icons.visibility_off_outlined
                                            : Icons.visibility_outlined,
                                      ),
                                    ),
                                  ),
                                  validator: (value) => (value ?? '').isEmpty
                                      ? 'Enter your password.'
                                      : (creating || recovery) &&
                                            value!.length < 8
                                      ? 'Use at least 8 characters.'
                                      : null,
                                ),
                                if (creating || recovery) ...[
                                  const SizedBox(height: 16),
                                  TextFormField(
                                    controller: confirmation,
                                    obscureText: true,
                                    autocorrect: false,
                                    enableSuggestions: false,
                                    decoration: const InputDecoration(
                                      labelText: 'Confirm password',
                                    ),
                                    validator: (value) => value == password.text
                                        ? null
                                        : 'Passwords do not match.',
                                  ),
                                ],
                                const SizedBox(height: 20),
                                FilledButton(
                                  onPressed: busy ? null : submit,
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Text(
                                      busy
                                          ? 'Please wait…'
                                          : recovery
                                          ? 'Save new password'
                                          : creating
                                          ? 'Create account'
                                          : 'Sign in',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (!recovery) ...[
                          TextButton(
                            onPressed: busy
                                ? null
                                : () => setState(() {
                                    creating = !creating;
                                    password.clear();
                                    confirmation.clear();
                                    error = null;
                                    message = null;
                                  }),
                            child: Text(
                              creating
                                  ? 'Already have an account? Sign in'
                                  : 'New here? Create an account',
                            ),
                          ),
                          TextButton(
                            onPressed: busy
                                ? null
                                : () {
                                    if (validEmail()) {
                                      request(() async {
                                        await service.resetPassword(
                                          email.text.trim(),
                                        );
                                        info(
                                          'If this email can receive a reset link, one has been requested. Open the newest link on this device.',
                                        );
                                      });
                                    }
                                  },
                            child: const Text('Forgot password?'),
                          ),
                          TextButton(
                            onPressed: busy
                                ? null
                                : () {
                                    if (validEmail()) {
                                      request(() async {
                                        await service.resendConfirmation(
                                          email.text.trim(),
                                        );
                                        info(
                                          'If confirmation is needed, an email has been requested. Check your inbox and spam folder.',
                                        );
                                      });
                                    }
                                  },
                            child: const Text('Resend confirmation email'),
                          ),
                        ] else
                          TextButton(
                            onPressed: busy
                                ? null
                                : () => request(service.signOut),
                            child: const Text('Cancel and sign out'),
                          ),
                      ],
                      if (error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Semantics(
                            liveRegion: true,
                            child: Text(
                              error!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        ),
                      if (message != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Semantics(
                            liveRegion: true,
                            child: Text(message!),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
