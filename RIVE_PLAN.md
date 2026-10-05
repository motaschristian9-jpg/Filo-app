# Rive animation plan for Filo

Prepared: 2026-10-05

Implementation status: initial mascot asset and Flutter integration completed on
2026-10-05, followed by user-approved broader page/success/loading placements.
LearningArt defaults to Rive; see MASCOT.md for current placements.
User explicitly allowed Rive export and PNG previews for asset creation.
All five expression previews were rendered/visually reviewed; Flutter runtime and
device behavior still require the user's manual review. Dependencies resolved,
but no Flutter builds/tests/analysis/device checks run. Runtime/manual layout review
remains with the user. See HANDOFF.md for current details.

## Goal and scope

Move Filo's original folded-file mascot to Rive in small stages. Keep the lime
paper shape, folded corner, bookmark, teal limbs, face and palette described in
MASCOT.md. Improve expression transitions and motion without changing screens,
adding extra copy, or changing Firebase/Supabase behavior.

The planning turn prepared tooling only; implementation was subsequently requested.
The user manually
reviews work; do not run tests, static analysis, animation/app builds, browser
automation or device checks unless explicitly requested.

## Tooling

- Official Windows x64 Rive CLI release selected: 1.3.0.
- Workspace-local executable: artifacts/rive/cli-1.3.0/rive.exe.
- Installation uses the official release archive and its SHA-256 manifest value.
  No global PATH or system-wide configuration change is needed.
- Run from PowerShell using:
  `& 'C:\Codex\Filo\artifacts\rive\cli-1.3.0\rive.exe' --help`
- Keep downloaded tooling/archives out of version control; commit mascot source
  and approved runtime assets. CLI project docs/AGENTS.md must be read after
  scaffolding, before editing the animation source.

## Stage 1: recreate the mascot

1. Create an editable project at animations/filo_mascot using the CLI.
2. Read the generated project instructions and installed RML documentation.
3. Recreate the existing artwork with separate paper, fold, face, cheeks, arms,
   boots, bookmark and shadow layers. Use basic vector shapes initially, avoiding
   scripts and shaders. Preserve the silhouette at both 96px and onboarding sizes.
4. Supply friendly, curious, proud, excited and wink poses, matching current
   MascotExpression values. Agree on their visual appearance before replacing UI.

Checkpoint: manually review the mascot's appearance. No borrowed mascot or new
character design. A Rive login is unnecessary for local script-free authoring;
remote publishing/editor synchronization is a separate optional step.

## Stage 2: motion and interaction

Create a proposed artboard named FiloMascot and state machine named Mascot.
Confirm exact names/input types against the actual exported file before Flutter
wiring. Use a small numeric expression input matching the five existing poses,
and a motion-enabled switch. Add subtle idle breathing/bobbing, occasional blink,
a short greeting wave and a restrained proud/celebration reaction.

| Existing state | Proposed mascot behavior |
| --- | --- |
| Greeting | Friendly pose and one short wave |
| Instructor searching | Curious pose |
| Instructor with current classes | Proud pose |
| Onboarding welcome | Excited pose and brief celebration |
| Reduced motion | Correct still pose without decorative loops/transitions |

Keep motion small and slow around classroom work. Pause offscreen and when the
app is backgrounded. Do not add a student greeting mascot as part of this work.

Checkpoint: user reviews motion manually. CLI preview and export/build commands
require explicit authorization under the project's no-build/no-device-check rule.

## Stage 3: Flutter integration

1. Check the current published rive package and Flutter/platform compatibility;
   use the current runtime API rather than copying legacy RiveAnimation examples.
   Adding/resolving dependencies is implementation work, deferred for now.
2. Export the approved file to assets/animations/filo_mascot.riv and register it
   in pubspec.yaml. Keep editable source in animations/filo_mascot.
3. Preserve LearningArt's public compact/expression API as the shared entry point.
   Add a Rive implementation behind it, initially for one existing placement.
4. Cache the loaded file appropriately and create/dispose controllers per widget.
   Respect MediaQuery.disableAnimations and avoid duplicate Flutter/Rive loops.
5. Retain the CustomPainter mascot as a loading/failure/reduced-motion fallback
   until the Rive asset can provide equivalent still poses reliably.
6. Keep decorative art excluded from screen-reader semantics and important text
   outside the animation. Asset loading must not block login or classroom actions.

Checkpoint: user manually compares the original and new rendering on Android.
Then extend to current onboarding/empty-state placements and review web behavior.
Native runtime dependencies may require the user's fresh app restart/build.

## Stage 4: finish and document

- User reviews small-screen sizing, clipping, background/resume, repeated
  navigation, expression changes, offline asset loading and reduced motion.
- Resolve any platform/runtime issue before expanding placements. Do not assume
  Rive improves performance without measurement.
- Record runtime/CLI versions, artboard/input names, asset export command and
  remaining limitations in HANDOFF.md and MASCOT.md.
- Preserve onboarding preview/data isolation and all student/instructor actions.

## Official references

- [Rive CLI installation and local authoring](https://github.com/rive-app/rive-docs/blob/main/cli/getting-started.mdx)
- [Rive Flutter runtime](https://github.com/rive-app/rive-flutter)
- [Published Flutter package](https://pub.dev/packages/rive)

The CLI creates assets; the Flutter runtime plays them in Filo. Rive does not
replace Flutter, Firebase or Supabase. Avoid scripts in the first asset so local
export does not introduce web script-signing/publishing requirements.
