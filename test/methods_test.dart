import 'package:coach_plan/methods.dart';
import 'package:coach_plan/velocity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Methoden', () {
    test('Grundset ist in sich stimmig', () {
      expect(grundset.map((m) => m.id).toSet().length, grundset.length);
      for (final m in grundset) {
        expect(m.sets, isNotEmpty, reason: m.id);
        expect(m.source, isNotEmpty, reason: m.id);
        for (final s in m.sets) {
          expect(s.percent, inInclusiveRange(40, 100), reason: m.id);
          expect(s.reps.every((r) => r > 0), isTrue, reason: m.id);
          expect(s.isCluster, m.kind == MethodKind.cluster, reason: m.id);
          if (s.isCluster) expect(s.intraRestSec, isNotNull, reason: m.id);
        }
      }
    });

    test('Welle 5/3/1 bei 125 kg', () {
      final m = grundset.firstWhere((m) => m.id == 'welle-531');
      final sets = resolveMethod(m, 125);
      expect(sets.map((s) => s.weightKg), [100, 112.5, 120, 100, 112.5, 120]);
      expect(sets.map((s) => s.spec.repsLabel), ['5', '3', '1', '5', '3', '1']);
      expect(sets.first.toString(), '5 × 100 kg');
    });

    test('Rundung auf ladbare Stufen', () {
      expect(roundLoad(101.2), 100);
      expect(roundLoad(101.3), 102.5);
      expect(roundLoad(137, step: 5), 135);
      expect(roundLoad(101.2, step: 0), 101.2);
      final m = grundset.firstWhere((m) => m.id == 'welle-321');
      expect(resolveMethod(m, 140, step: 5).first.weightKg, 120);
    });

    test('Cluster-Satz', () {
      final m = grundset.firstWhere((m) => m.id == 'cluster-221');
      final s = resolveMethod(m, 100).first;
      expect(s.spec.repsLabel, '2+2+1');
      expect(s.spec.totalReps, 5);
      expect(s.weightKg, 90);
    });

    test('1RM-Schätzung nach Epley', () {
      expect(estimateOneRm(100, 1), 100);
      expect(estimateOneRm(100, 6), closeTo(120, 0.001));
      expect(estimateOneRm(0, 5), isNull);
      expect(estimateOneRm(100, 0), isNull);
    });
  });

  group('Geschwindigkeit', () {
    test('aus Bildern', () {
      // 0,45 m Hub in 90 Bildern bei 120 B/s = 0,75 s → 0,6 m/s.
      expect(
        velocityFromFrames(romM: 0.45, startFrame: 10, endFrame: 100, fps: 120),
        closeTo(0.6, 1e-9),
      );
      expect(
        velocityFromFrames(romM: 0.45, startFrame: 10, endFrame: 10, fps: 120),
        isNull,
      );
      expect(
        frameCountingError(durationSec: 0.5, fps: 120),
        closeTo(0.0333, 0.0001),
      );
      expect(
        frameCountingError(durationSec: 0.5, fps: 30),
        closeTo(0.1333, 0.0001),
      );
    });

    test('Geschwindigkeitsverlust', () {
      expect(velocityLoss([0.60, 0.58, 0.54, 0.48]), closeTo(0.2, 1e-9));
      expect(velocityLoss([]), isNull);
    });

    test('Bereiche', () {
      expect(VelocityZone.of(0.3), VelocityZone.absolutkraft);
      expect(VelocityZone.of(0.5), VelocityZone.beschleunigungskraft);
      expect(VelocityZone.of(0.9), VelocityZone.kraftSchnelligkeit);
      expect(VelocityZone.of(1.1), VelocityZone.schnellkraft);
      expect(VelocityZone.of(1.6), VelocityZone.startkraft);
    });

    test('1RM aus zwei Punkten', () {
      // 60 kg bei 1,0 m/s, 100 kg bei 0,5 m/s → Gerade trifft 0,3 m/s bei 116 kg.
      expect(
        oneRmFromTwoPoints(
          lightKg: 60,
          lightVelocity: 1.0,
          heavyKg: 100,
          heavyVelocity: 0.5,
          mvt: 0.3,
        ),
        closeTo(116, 1e-9),
      );
      expect(
        oneRmFromTwoPoints(
          lightKg: 60,
          lightVelocity: 0.5,
          heavyKg: 100,
          heavyVelocity: 0.6,
          mvt: 0.3,
        ),
        isNull,
      );
    });
  });
}
