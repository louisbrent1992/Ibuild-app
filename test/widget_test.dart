import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibuild/models/build.dart';
import 'package:ibuild/models/pipeline.dart';
import 'package:ibuild/widgets/transit_line.dart';

void main() {
  testWidgets('transit line labels every station', (tester) async {
    final finished = Build(
      id: 'b1',
      appId: 'a1',
      status: BuildStatus.finished,
      createdAt: DateTime(2026, 9, 1),
      finishedAt: DateTime(2026, 9, 1, 0, 4, 32),
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TransitLine(
          snapshot: computePipeline(finished, testFlight: TestFlightState.ready),
        ),
      ),
    ));
    for (final station in Station.values) {
      expect(find.text(station.label), findsOneWidget);
    }
  });
}
