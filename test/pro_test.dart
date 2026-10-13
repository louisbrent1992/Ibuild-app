import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibuild/app/app_controller.dart';
import 'package:ibuild/models/project.dart';
import 'package:ibuild/services/account_service.dart';
import 'package:ibuild/services/pro_service.dart';

class _FakePro implements ProService {
  final _changes = StreamController<bool>.broadcast();
  bool pro = false;
  final List<String?> identified = [];

  void grant() {
    pro = true;
    _changes.add(true);
  }

  @override
  bool get isPro => pro;
  @override
  Stream<bool> changes() => _changes.stream;
  @override
  Future<void> identify(String? uid) async => identified.add(uid);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Accounts implements AccountService {
  final _events = StreamController<Account?>.broadcast();
  void emit(Account? a) => _events.add(a);
  @override
  Stream<Account?> changes() => _events.stream;
  @override
  Future<List<Project>> loadProjects() async => const [];
  @override
  Future<void> saveProject(Project project) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Project _p(String id) => Project(
    id: id, name: id, codemagicAppId: 'a', workflowId: 'ios-release', branch: 'main');

void main() {
  test('free tier fits one real project; demo and Pro are unlimited', () {
    expect(fitsFreeTier(isPro: false, demoMode: false, projects: 0), isTrue);
    expect(fitsFreeTier(isPro: false, demoMode: false, projects: 1), isFalse);
    expect(fitsFreeTier(isPro: true, demoMode: false, projects: 9), isTrue);
    expect(fitsFreeTier(isPro: false, demoMode: true, projects: 9), isTrue);
  });

  group('AppController', () {
    setUp(() => FlutterSecureStorage.setMockInitialValues({'demo_mode': 'false'}));

    test('second project needs Pro, and buying it lifts the limit live', () async {
      final pro = _FakePro();
      final app = AppController(pro: pro);
      await app.load();
      expect(app.canAddProject, isTrue);
      await app.addProject(_p('one'));
      expect(app.canAddProject, isFalse);

      var notified = false;
      app.addListener(() => notified = true);
      pro.grant();
      await pumpEventQueue();
      expect(notified, isTrue);
      expect(app.canAddProject, isTrue);
    });

    test('Pro follows the account: linked on sign-in, released on sign-out', () async {
      final pro = _FakePro();
      final accounts = _Accounts();
      final app = AppController(pro: pro, accounts: accounts);
      await app.load();
      accounts.emit(const Account(uid: 'u1'));
      await pumpEventQueue();
      accounts.emit(null);
      await pumpEventQueue();
      expect(pro.identified, ['u1', null]);
    });
  });
}
