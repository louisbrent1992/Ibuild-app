import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibuild/app/app_controller.dart';
import 'package:ibuild/models/project.dart';
import 'package:ibuild/services/account_service.dart';

Project _p(String id, {String branch = 'main'}) => Project(
      id: id,
      name: id,
      codemagicAppId: 'app',
      workflowId: 'ios-release',
      branch: branch,
    );

/// An account backend that lives in memory, standing in for Firebase.
class _FakeAccounts implements AccountService {
  final _events = StreamController<Account?>.broadcast();
  final Map<String, Project> remote = {};
  bool failSaves = false;
  Account? _current;

  void signInAs(String uid) {
    _current = Account(uid: uid, username: 'tester');
    _events.add(_current);
  }

  @override
  Account? get current => _current;
  @override
  Stream<Account?> changes() => _events.stream;
  @override
  Future<List<Project>> loadProjects() async => remote.values.toList();
  @override
  Future<void> saveProject(Project project) async {
    if (failSaves) throw Exception('offline');
    remote[project.id] = project;
  }
  @override
  Future<void> deleteProject(String id) async => remote.remove(id);
  @override
  Future<void> signOut() async {
    _current = null;
    _events.add(null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('usernames', () {
    test('accepts letters, numbers and underscores, case-insensitively', () {
      expect(usernameError('Louis_Brent1'), isNull);
      expect(normalizeUsername('  Louis_Brent1 '), 'louis_brent1');
    });

    test('rejects bad lengths and characters', () {
      expect(usernameError('ab'), isNotNull);
      expect(usernameError('a' * 21), isNotNull);
      expect(usernameError('no spaces'), isNotNull);
      expect(usernameError('dash-ed'), isNotNull);
    });
  });

  test('mergeProjects keeps both sides and prefers the device on a clash', () {
    final merged = mergeProjects(
      [_p('a', branch: 'device'), _p('b')],
      [_p('a', branch: 'cloud'), _p('c')],
    );
    expect(merged.map((p) => p.id).toSet(), {'a', 'b', 'c'});
    expect(merged.firstWhere((p) => p.id == 'a').branch, 'device');
  });

  group('AppController sync', () {
    setUp(() => FlutterSecureStorage.setMockInitialValues({'demo_mode': 'false'}));

    test('signing in merges both ways; changes after that are mirrored', () async {
      final accounts = _FakeAccounts()..remote['cloud'] = _p('cloud');
      final app = AppController(accounts: accounts);
      await app.load();
      await app.addProject(_p('local'));
      expect(accounts.remote.containsKey('local'), isFalse,
          reason: 'signed out: nothing leaves the device');

      accounts.signInAs('u1');
      await pumpEventQueue();
      expect(app.projects.map((p) => p.id).toSet(), {'local', 'cloud'});
      expect(accounts.remote.keys.toSet(), {'local', 'cloud'});

      await app.deleteProject('cloud');
      await pumpEventQueue();
      expect(accounts.remote.containsKey('cloud'), isFalse);

      await accounts.signOut();
      await pumpEventQueue();
      expect(app.account, isNull);
      expect(app.projects.map((p) => p.id), ['local'],
          reason: 'signing out keeps the device copy');
    });

    test('refreshing takes the account\'s list, unless a push failed', () async {
      final accounts = _FakeAccounts()
        ..remote['a'] = _p('a')
        ..remote['b'] = _p('b');
      final app = AppController(accounts: accounts);
      await app.load();
      accounts.signInAs('u1');
      await pumpEventQueue();

      // Deleted and added on another device.
      accounts.remote.remove('b');
      accounts.remote['c'] = _p('c');
      await app.refreshAccount();
      expect(app.projects.map((p) => p.id).toSet(), {'a', 'c'});
      expect(accounts.remote.keys.toSet(), {'a', 'c'},
          reason: 'the deleted project is not pushed back');

      // Offline here: the new project never reached the account.
      accounts.failSaves = true;
      await app.addProject(_p('d'));
      await pumpEventQueue();
      accounts.failSaves = false;
      await app.refreshAccount();
      expect(app.projects.map((p) => p.id).toSet(), {'a', 'c', 'd'});
      expect(accounts.remote.containsKey('d'), isTrue);
    });
  });
}
