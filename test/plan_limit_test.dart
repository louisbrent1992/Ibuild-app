import 'package:flutter_test/flutter_test.dart';
import 'package:ibuild/models/build.dart';

void main() {
  group('isCodemagicPlanLimit', () {
    test('recognises plan and minutes messages', () {
      // Real response from a free-plan account asking for a Linux machine.
      expect(
          isCodemagicPlanLimit(
              'The selected instance type is not available with the current billing plan.'),
          isTrue);
      expect(isCodemagicPlanLimit('You have used all your build minutes for this month'), isTrue);
      expect(isCodemagicPlanLimit('Monthly build minutes limit reached'), isTrue);
    });

    test('leaves ordinary failures alone', () {
      // Real failures from builds whose cause was the code or the config.
      expect(isCodemagicPlanLimit('Step 3 script `Dependencies` exited with status code 1'), isFalse);
      expect(
          isCodemagicPlanLimit(
              'Codemagic.yaml references to unknown variable group(s): asc_credentials'),
          isFalse);
      expect(isCodemagicPlanLimit(null), isFalse);
    });
  });

  test('Build reads Codemagic\'s reason apart from the commit message', () {
    final build = Build.fromCodemagic({
      'build': {
        '_id': 'b1',
        'appId': 'a1',
        'status': 'failed',
        'message': 'The selected instance type is not available with the current billing plan.',
        'commit': {'commitMessage': 'Fix login'},
      },
    });
    expect(build.message, 'Fix login');
    expect(build.hitPlanLimit, isTrue);
  });
}
