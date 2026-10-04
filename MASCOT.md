# Filo mascot

Filo's mascot is an original little folded-file character. It represents learning
materials brought to life: approachable, curious, and quietly proud of progress.
Its name has not been chosen yet.

## Appearance

- A rounded lime paper body with a slightly offset darker page behind it.
- A folded top-right corner and a pale curved highlight near the top edge.
- Dark teal eyes and mouth, peach cheeks, and a friendly expressive face.
- Flexible teal arms, short legs, and little teal boots.
- Two short document lines near the lower part of the body.
- A small teal bookmark with a notched end along the lower-right edge.
- A soft oval shadow underneath, with a pale circular backdrop.

The folded corner, document lines, and bookmark make the character recognizable
as a file. Preserve these features when creating new poses. The character is drawn
directly in Flutter with CustomPainter, so it stays sharp at different sizes.

### Character palette

| Feature | Color |
| --- | --- |
| Main paper | Lime `#E2F3A6` |
| Back page | Muted lime `#B9CE7C` |
| Folded corner | `#BFD487` |
| Arms, boots, bookmark | Teal `#246B58` |
| Eyes and mouth | Dark teal `#183D38` |
| Cheeks | Peach `#E8BCA4` |

Keep these colors and the folded-file silhouette consistent across screens.

## Personality and expressions

| Expression | Appearance and feeling |
| --- | --- |
| Friendly | Open eyes, a small smile, and a welcoming wave |
| Excited | Closed happy eyes, a wide open smile, raised arms, and small sparkles |
| Curious | Tilted head, uneven eye position, raised eyebrow, small round mouth, and a thinking pose |
| Proud | Closed smiling eyes, a bigger curved smile, and small sparkles |
| Wink | One closed eye, a smile, and a playful wave |

The mascot encourages without judging. Use a curious expression during searching,
a friendly expression when welcoming someone, and a proud expression around
their work. Avoid guilt, exaggerated sadness, or distracting reactions to errors.

## Movement

The character gently bobs and waves. Expression changes crossfade and head tilts
ease into position. Flutter's reduced-motion preference stops decorative movement.
The illustration is excluded from screen-reader semantics because surrounding
UI already communicates the screen's purpose.

## Instructor placement

The instructor dashboard has a compact mascot beside Your classes and the
personal greeting. It stays present when classes exist, rather than appearing
only on an empty dashboard. It looks curious during a search, proud when viewing
existing active classes, and friendly otherwise.

Keep the mascot small around working tools and larger in onboarding or a dedicated
celebration. Use one illustration in a local section so the class list stays clear.
Student mascot placement is deferred until that interface is developed further.

## Reusing the artwork

Use the shared `LearningArt` widget instead of drawing a separate character:

```dart
SizedBox(
  width: 96,
  height: 96,
  child: LearningArt(
    compact: true,
    expression: MascotExpression.friendly,
  ),
)
```

Choose expressions from the actual screen state. Keep actions and important
information outside the illustration; the mascot is decorative and never blocks
a task. Leave space for its wave and avoid adding speech bubbles or extra copy
just to explain its presence.

## Design influence

Duolingo inspires the idea of a character giving a learning app personality.
Filo's paper shape, face, palette, and artwork are original. Use Filo's existing
character rather than importing another app's character or inventing a new one
for each screen. Let expression and motion carry personality with minimal copy.

Source: [illustrations.dart](lib/onboarding/illustrations.dart). Shared palette:
[design.dart](lib/onboarding/design.dart). Overall direction: [DESIGN.md](DESIGN.md).
