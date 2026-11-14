/// The mouth shapes the avatar blends between.
///
/// Each carries its articulation target, in face units so any face can use
/// it: [gap] and [widthChange] in neutral mouth widths (W), [jaw] in
/// nose-to-chin distances (H). The numbers follow measured speech geometry
/// (JALI; the Oculus and Rhubarb viseme sets), checked against photos of
/// one face holding each vowel: an "a" parts the lips about 0.4 W and drops
/// the chin about 0.16 H (posed, 0.22 H; speech opens less), an "o" pulls
/// the corners in by about 30% and a "u" barely parts the lips but rounds
/// them as much.
///
/// [attack] and [release] are how fast a shape takes over and lets go:
/// rounding lingers into the next sound (coarticulation), fricatives come
/// and go quickly. A shape's [index] is the value of the Rive `viseme` input.
enum Viseme {
  /// Closed, relaxed mouth (silence).
  rest(gap: 0, jaw: 0, widthChange: 0, round: 0, attack: 0.05, release: 0.12),

  /// Wide open (a).
  a(
    gap: 0.40,
    jaw: 0.16,
    widthChange: 0,
    round: 0,
    attack: 0.05,
    release: 0.12,
  ),

  /// Open and spread (e).
  e(
    gap: 0.20,
    jaw: 0.08,
    widthChange: 0.10,
    round: 0,
    attack: 0.05,
    release: 0.12,
  ),

  /// Narrow and spread (i).
  i(
    gap: 0.11,
    jaw: 0.03,
    widthChange: 0.18,
    round: 0,
    attack: 0.05,
    release: 0.12,
  ),

  /// Rounded and open (o).
  o(
    gap: 0.25,
    jaw: 0.12,
    widthChange: -0.30,
    round: 0.7,
    attack: 0.06,
    release: 0.18,
  ),

  /// Small and rounded (u).
  u(
    gap: 0.08,
    jaw: 0.06,
    widthChange: -0.30,
    round: 1,
    attack: 0.06,
    release: 0.2,
  ),

  /// Teeth almost together, lips apart (s, f, ch).
  fricative(
    gap: 0.03,
    jaw: 0.02,
    widthChange: 0.05,
    round: 0,
    attack: 0.03,
    release: 0.06,
  );

  Viseme({
    required this.gap,
    required this.jaw,
    required this.widthChange,
    required this.round,
    required this.attack,
    required this.release,
  });

  /// Lip opening at full loudness, in mouth widths.
  final double gap;

  /// Chin drop at full loudness, in nose-to-chin distances.
  final double jaw;

  /// Mouth width change, in mouth widths (positive spreads).
  final double widthChange;

  /// Lip rounding, 0..1.
  final double round;

  /// Time constant (seconds) for this shape to take over.
  final double attack;

  /// Time constant (seconds) for this shape to let go.
  final double release;
}
