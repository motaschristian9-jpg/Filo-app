# Filo design guide

Filo uses a playful learning style with its own folded-file mascot, warm surfaces,
rounded controls, and short, clear copy.

## Visual style

The shared theme is Flutter Material 3 with bundled Nunito typography. Headings
are bold and rounded. Cards have generous spacing and soft corners. Main actions
use the shared PrimaryButton with a teal fill and a small raised shadow.

| Color | Hex | Purpose |
| --- | --- | --- |
| Cream | #FAFBF6 | Main background |
| Ink | #183D38 | Headings and strong text |
| Teal | #246B58 | Primary buttons and icons |
| Mint | #E7EFE3 | Soft panels |
| Lime | #E2F3A6 | Playful accents |
| Muted | #66756E | Supporting text |
| Line | #DCE3D8 | Borders and dividers |

Let the original mascot express personality with friendly poses and gentle
animation. Keep UI text minimal. Honor reduced-motion settings and keep artwork
out of screen-reader descriptions when it is decorative.

## App inspirations

| App | Idea used in Filo |
| --- | --- |
| Duolingo | Welcoming onboarding, expressive motion, visible progress, approachable account settings |
| Google Classroom | Classes organize materials; compact posts open a full details page |
| Google Drive | In-app file previews and clear offline availability |
| Google Forms | Simple forms with clear questions and one main completion action |
| NotebookLM | Planned study features grounded in supplied learning materials |

Filo uses its own colors, mascot, layouts, and wording. Inspiration does not mean
reusing another app's characters, logos, artwork, or exact screens.

## Interface patterns

- Instructor content cards expose Edit/Delete in a three-dot menu. Deletion
  requires confirmation. Material edits preserve attached files; draft classwork
  is fully editable, while published questions stay locked and results are retained
  when an assessment is removed from classwork.

- Assessment questions use a type selector with only relevant fields visible.
  Multiple choice, True/false, Identification, Enumeration, and Essay share points
  and prompt fields. AI generation specifies the count per type. Essays show
  Awaiting review until instructor scores and feedback complete the final result.

- Files uses horizontal category chips for Images, PDFs, Documents, Presentations,
  Spreadsheets, and Other, with All selected initially.

- Announcements can include a file attachment. Stream shows the message and
  clickable attachment; Files exposes the same attachment without duplicating
  storage. Both open the original post details and file preview.

- Class rooms use bottom navigation: Stream (announcements and links), Files
  (uploaded lessons), and Classwork (assessments, with future assignments/activities).
  Section headings match the selected destination; instructor actions sit above
  navigation. This supersedes earlier five-tab room navigation.

- Tabs use shared FiloTabs: a rounded mint track, white bordered selection, and
  bold active labels. Long lists scroll horizontally; short Drafts/Published
  tabs share the available width. Use teal checkmarks for published assessments.

- Class rooms use All, Files, Links, Announcements, and Assessments tabs.
  Assessments covers quizzes and exams. Publish makes reviewed drafts visible
  to enrolled students; answer keys remain private. Published cards open details.

- Instructor quizzes/exams use one editor for manual and AI-generated questions.
  Time limits use minutes. AI output stays editable for review before Save draft.
  Drafts and answer keys remain private to the instructor.

- Student class rooms offer Leave class in the app-bar options menu. Confirm before
  removing membership and saved files; the student can rejoin with the code.
  Archiving is an instructor action affecting the class as a whole.

- Page and content loading use `FiloSkeleton`: rounded placeholders matching
  cards, details, profiles, previews, or list rows. Use Filo's soft border color
  and a gentle opacity pulse; disable the pulse when reduced motion is enabled.
  Keep loaded navigation and content visible during refreshes. Skeletons are
  decorative, announce "Loading content" once, and have no interactive actions.
- Saving, posting, signing in, and downloading keep action progress indicators;
  skeletons represent content that has not loaded yet.

- Onboarding uses short headings, one clear next action, and mascot animation.
- Tap the dashboard avatar to open Account. The page shows identity, Edit profile,
  and a separate Sign out action with confirmation.
- Edit profile saves the display name, school, bio, and chosen avatar. The Google
  email and saved account role are read-only.
- Materials use Files, Links, and Announcements tabs. Cards open full details;
  attachment tiles open private previews or links.
- Students use Your classes and a fixed Join class button. The join page has the
  original curious mascot, one six-character code field, and one primary action.
  Successful joining opens class materials through live membership discovery.
- Native offline indicators reflect an actual saved file in Filo's account and
  class storage. Previewing alone does not mean the file has been saved.
- Keep layouts scrollable on small screens and centered within a maximum width
  on larger screens. Use one main action and readable tap targets.

## Source files

- [design.dart](lib/onboarding/design.dart): theme, palette, buttons, avatars.
- [illustrations.dart](lib/onboarding/illustrations.dart): original mascot and motion.
- [account_screen.dart](lib/account/account_screen.dart): account and profile settings.
- [material_screen.dart](lib/materials/material_screen.dart): material tabs and cards.
- [HANDOFF.md](HANDOFF.md): product decisions and current implementation status.
