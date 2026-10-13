import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../models/project.dart';

/// A signed-in iBuild user. Connection tokens are deliberately not part of
/// an account: they stay in each device's secure storage.
class Account {
  const Account({
    required this.uid,
    this.email,
    this.username,
    this.providers = const [],
  });

  final String uid;
  final String? email;
  final String? username;

  /// Firebase provider IDs, e.g. `password`, `google.com`, `apple.com`.
  final List<String> providers;
}

/// Thrown when Firebase wants a fresh sign-in before a sensitive change
/// (deleting the account). The UI asks the user to sign in again and retries.
class RecentLoginRequired implements Exception {
  const RecentLoginRequired();
}

class AccountException implements Exception {
  const AccountException(this.message);
  final String message;
  @override
  String toString() => message;
}

final _usernamePattern = RegExp(r'^[a-z0-9_]{3,20}$');

/// Usernames are case-insensitive: stored and compared in lower case.
String normalizeUsername(String raw) => raw.trim().toLowerCase();

/// Null when [raw] is a valid username, otherwise why not.
String? usernameError(String raw) {
  final name = normalizeUsername(raw);
  if (name.length < 3) return 'Use at least 3 characters.';
  if (name.length > 20) return 'Use at most 20 characters.';
  if (!_usernamePattern.hasMatch(name)) {
    return 'Use letters, numbers and underscores only.';
  }
  return null;
}

/// Projects on this device plus projects in the account, by ID. On a clash
/// the device copy wins: it is what the user is looking at, and it is pushed
/// back up straight after the merge.
List<Project> mergeProjects(List<Project> local, List<Project> remote) {
  final byId = {for (final p in remote) p.id: p};
  for (final p in local) {
    byId[p.id] = p;
  }
  return byId.values.toList();
}

abstract class AccountService {
  Account? get current;
  Stream<Account?> changes();

  Future<void> signUp({
    required String username,
    required String email,
    required String password,
  });
  Future<void> signIn({required String email, required String password});
  Future<void> signInWithApple();
  Future<void> signInWithGoogle();
  Future<void> signInWithGitHub();
  Future<void> sendPasswordReset(String email);
  Future<void> setUsername(String username);
  Future<void> signOut();

  /// Deletes the profile, username, synced projects and the sign-in itself.
  /// Throws [RecentLoginRequired] when Firebase needs a fresh sign-in first.
  Future<void> deleteAccount();

  /// Signs in again with the account's own provider, for [deleteAccount].
  Future<void> reauthenticate({String? password});

  Future<List<Project>> loadProjects();
  Future<void> saveProject(Project project);
  Future<void> deleteProject(String id);
}

class FirebaseAccountService implements AccountService {
  FirebaseAccountService({FirebaseAuth? auth, FirebaseFirestore? db})
      : _auth = auth ?? FirebaseAuth.instance,
        _db = db ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _db;
  final Map<String, String?> _usernames = {};
  bool _googleReady = false;

  DocumentReference<Map<String, dynamic>> _profile(String uid) =>
      _db.collection('users').doc(uid);
  CollectionReference<Map<String, dynamic>> _projects(String uid) =>
      _profile(uid).collection('projects');
  DocumentReference<Map<String, dynamic>> _claim(String name) =>
      _db.collection('usernames').doc(name);

  String get _uid {
    final user = _auth.currentUser;
    if (user == null) throw const AccountException('You are not signed in.');
    return user.uid;
  }

  Account _toAccount(User user) => Account(
        uid: user.uid,
        email: user.email,
        username: _usernames[user.uid],
        providers: user.providerData.map((p) => p.providerId).toList(),
      );

  @override
  Account? get current {
    final user = _auth.currentUser;
    return user == null ? null : _toAccount(user);
  }

  @override
  Stream<Account?> changes() => _auth.userChanges().asyncMap((user) async {
        if (user == null) return null;
        if (!_usernames.containsKey(user.uid)) {
          final snap = await _profile(user.uid).get();
          _usernames[user.uid] = snap.data()?['username'] as String?;
        }
        return _toAccount(user);
      });

  /// Claims [username] and writes the profile in one transaction, so two
  /// people can never end up with the same name.
  Future<void> _claimUsername(User user, String username) async {
    final name = normalizeUsername(username);
    final problem = usernameError(name);
    if (problem != null) throw AccountException(problem);
    await _db.runTransaction((tx) async {
      final claim = await tx.get(_claim(name));
      if (claim.exists && claim.data()?['uid'] != user.uid) {
        throw const AccountException('That username is taken.');
      }
      final profile = await tx.get(_profile(user.uid));
      final previous = profile.data()?['username'] as String?;
      if (previous != null && previous != name) tx.delete(_claim(previous));
      // Claims are create-only in the security rules; re-saving the same
      // name must not rewrite it.
      if (!claim.exists) tx.set(_claim(name), {'uid': user.uid});
      tx.set(
        _profile(user.uid),
        {
          'username': name,
          'email': user.email,
          if (!profile.exists) 'createdAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
    _usernames[user.uid] = name;
  }

  Future<void> _ensureProfile(User user) async {
    final ref = _profile(user.uid);
    final snap = await ref.get();
    if (!snap.exists) {
      await ref.set({
        'email': user.email,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    _usernames[user.uid] = snap.data()?['username'] as String?;
  }

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') throw const RecentLoginRequired();
      throw AccountException(_authMessage(e));
    } on FirebaseException catch (e) {
      throw AccountException(e.message ?? 'Something went wrong (${e.code}).');
    }
  }

  static String _authMessage(FirebaseAuthException e) => switch (e.code) {
        'email-already-in-use' => 'An account already uses that email. Sign in instead.',
        'invalid-email' => 'That email address is not valid.',
        'weak-password' => 'Use a password of at least 8 characters.',
        'invalid-credential' ||
        'wrong-password' ||
        'user-not-found' =>
          'That email and password do not match an account.',
        'account-exists-with-different-credential' =>
          'This email already has an account with another sign-in method. Use that one.',
        'user-disabled' => 'This account has been disabled.',
        'too-many-requests' => 'Too many attempts. Try again in a few minutes.',
        'network-request-failed' => 'No connection. Check your network and try again.',
        'web-context-canceled' || 'canceled' => 'Sign-in was cancelled.',
        _ => e.message ?? 'Sign-in failed (${e.code}).',
      };

  @override
  Future<void> signUp({
    required String username,
    required String email,
    required String password,
  }) =>
      _guard(() async {
        final problem = usernameError(username);
        if (problem != null) throw AccountException(problem);
        if (password.length < 8) {
          throw const AccountException('Use a password of at least 8 characters.');
        }
        final taken = await _claim(normalizeUsername(username)).get();
        if (taken.exists) throw const AccountException('That username is taken.');
        final cred = await _auth.createUserWithEmailAndPassword(
            email: email.trim(), password: password);
        try {
          await _claimUsername(cred.user!, username);
        } catch (_) {
          // Lost a race for the name: undo the sign-up so it can be retried.
          await cred.user!.delete();
          rethrow;
        }
      });

  @override
  Future<void> signIn({required String email, required String password}) =>
      _guard(() async {
        final cred = await _auth.signInWithEmailAndPassword(
            email: email.trim(), password: password);
        await _ensureProfile(cred.user!);
      });

  @override
  Future<void> signInWithApple() => _guard(() async {
        final cred = await _auth.signInWithProvider(
            AppleAuthProvider()..addScope('email'));
        await _ensureProfile(cred.user!);
      });

  @override
  Future<void> signInWithGitHub() => _guard(() async {
        final cred = await _auth.signInWithProvider(
            GithubAuthProvider()..addScope('read:user')..addScope('user:email'));
        await _ensureProfile(cred.user!);
      });

  Future<OAuthCredential> _googleCredential() async {
    final google = GoogleSignIn.instance;
    if (!_googleReady) {
      await google.initialize();
      _googleReady = true;
    }
    try {
      final account = await google.authenticate();
      return GoogleAuthProvider.credential(
          idToken: account.authentication.idToken);
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        throw const AccountException('Sign-in was cancelled.');
      }
      throw AccountException(e.description ?? 'Google sign-in failed.');
    }
  }

  @override
  Future<void> signInWithGoogle() => _guard(() async {
        final cred = await _auth.signInWithCredential(await _googleCredential());
        await _ensureProfile(cred.user!);
      });

  @override
  Future<void> sendPasswordReset(String email) =>
      _guard(() => _auth.sendPasswordResetEmail(email: email.trim()));

  @override
  Future<void> setUsername(String username) =>
      _guard(() => _claimUsername(_auth.currentUser!, username));

  @override
  Future<void> signOut() async {
    if (_googleReady) await GoogleSignIn.instance.signOut();
    await _auth.signOut();
  }

  @override
  Future<void> reauthenticate({String? password}) => _guard(() async {
        final user = _auth.currentUser!;
        final provider = user.providerData.map((p) => p.providerId).firstOrNull;
        switch (provider) {
          case 'password':
            if (password == null || password.isEmpty) {
              throw const AccountException('Enter your password to continue.');
            }
            await user.reauthenticateWithCredential(EmailAuthProvider.credential(
                email: user.email!, password: password));
          case 'google.com':
            await user.reauthenticateWithCredential(await _googleCredential());
          case 'apple.com':
            await user.reauthenticateWithProvider(AppleAuthProvider());
          case 'github.com':
            await user.reauthenticateWithProvider(GithubAuthProvider());
          default:
            throw const AccountException('Sign out and sign in again, then retry.');
        }
      });

  @override
  Future<void> deleteAccount() => _guard(() async {
        final user = _auth.currentUser!;
        // Data before the sign-in: the security rules only let a signed-in
        // user delete their own documents.
        final projects = await _projects(user.uid).get();
        final profile = await _profile(user.uid).get();
        final username = profile.data()?['username'] as String?;
        final batch = _db.batch();
        for (final doc in projects.docs) {
          batch.delete(doc.reference);
        }
        if (username != null) batch.delete(_claim(username));
        batch.delete(_profile(user.uid));
        await batch.commit();
        try {
          await user.delete();
        } on FirebaseAuthException catch (e) {
          if (e.code == 'requires-recent-login') {
            // The data is already deleted. After re-authenticating, the
            // caller runs deleteAccount again; it finds no data and only
            // deletes the sign-in.
            throw const RecentLoginRequired();
          }
          rethrow;
        }
        _usernames.remove(user.uid);
        if (_googleReady) await GoogleSignIn.instance.signOut();
      });

  @override
  Future<List<Project>> loadProjects() => _guard(() async {
        final snap = await _projects(_uid).get();
        return snap.docs.map((d) => Project.fromJson(d.data())).toList();
      });

  @override
  Future<void> saveProject(Project project) =>
      _guard(() => _projects(_uid).doc(project.id).set(project.toJson()));

  @override
  Future<void> deleteProject(String id) =>
      _guard(() => _projects(_uid).doc(id).delete());
}

/// Used when Firebase is unavailable (tests, Linux desktop): accounts are
/// simply off and everything stays on the device.
class NoAccounts implements AccountService {
  const NoAccounts();
  static Never _off() =>
      throw const AccountException('Accounts are not available on this device.');

  @override
  Account? get current => null;
  @override
  Stream<Account?> changes() => const Stream.empty();
  @override
  Future<void> signUp({required String username, required String email, required String password}) async => _off();
  @override
  Future<void> signIn({required String email, required String password}) async => _off();
  @override
  Future<void> signInWithApple() async => _off();
  @override
  Future<void> signInWithGoogle() async => _off();
  @override
  Future<void> signInWithGitHub() async => _off();
  @override
  Future<void> sendPasswordReset(String email) async => _off();
  @override
  Future<void> setUsername(String username) async => _off();
  @override
  Future<void> signOut() async {}
  @override
  Future<void> deleteAccount() async => _off();
  @override
  Future<void> reauthenticate({String? password}) async => _off();
  @override
  Future<List<Project>> loadProjects() async => const [];
  @override
  Future<void> saveProject(Project project) async {}
  @override
  Future<void> deleteProject(String id) async {}
}
