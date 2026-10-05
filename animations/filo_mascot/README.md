# Filo mascot authoring

Original Filo artwork recreated from lib/onboarding/illustrations.dart, with
palette and character decisions in MASCOT.md. No external character assets.

CLI: workspace-local Rive 1.3.0 at artifacts/rive/cli-1.3.0/rive.exe.
Runtime: rive 0.14.11 / rive_native 0.1.11.

- Artboard: FiloMascot, 380 x 350, transparent outside the circular backdrop.
- State machine: Mascot. View model: MascotData, exported Default instance.
- Number expression: 0 friendly, 1 excited, 2 curious, 3 proud, 4 wink.
- Boolean motionEnabled: decorative idle loop enabled/disabled.
- Numbers leftEyeOpen/rightEyeOpen (default 1): runtime-controlled eyelid openness.
  Flutter schedules randomized blinks/winks; wink pose is open-eyed between events.
  Excited/proud retain their happy curved eyes.
- Expressions crossfade over 180ms. Curious tilts the artwork. A separate motion
  layer selects six-second timelines: Friendly waves, Excited raises both arms
  in a small celebration, Curious thinks and glances, Proud brings a hand toward
  its chest with a tiny acknowledgment tilt, and Wink gently stretches both arms.
  Body has ±0.5px idle motion and under-one-degree centered gesture tilt.
  Still disables movement. No Luau/scripts/shaders.
- Arm lowering/raising morphs the curve's vertex positions and Bézier
  tangents, rather than rotating a rigid bent arm. Shoulder remains anchored.
- Flutter taps briefly select wink/excited, returning to screen pose after 1.5s.

scene.rml is the editable source. generate_source.py recreates the initial
geometry and rig; running it overwrites scene.rml, including any hand edits.
It uses only Python's standard library. The Rive CLI writes IDs back into RML.

When explicitly authorized to export:

```powershell
& 'C:\Codex\Filo\artifacts\rive\cli-1.3.0\rive.exe' animations/filo_mascot --once
Copy-Item animations/filo_mascot/build/filo_mascot.riv assets/animations/filo_mascot.riv
```

For a PNG preview, only when authorized:

```powershell
& 'C:\Codex\Filo\artifacts\rive\cli-1.3.0\rive.exe' animations/filo_mascot --screenshot=artifacts/rive/mascot-curious.png --data=expression=2 --advance=20 --fit=contain
```

LearningArt now uses Rive by default for all approved placements. Pass
useRive:false to opt into the original painter. Existing painter is the loading,
error and reduced-motion fallback. See MASCOT.md/HANDOFF.md for current placements.
No Rive login, upload/publish, or persistent preview window is required.
