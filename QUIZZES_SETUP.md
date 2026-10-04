# Instructor quizzes and exams

## Lesson text reuse (performance Batch 4)

Apply `supabase/migrations/202610040004_quiz_lesson_cache.sql` in the Supabase
SQL Editor for project `pvcereixbqctjrxsalhd`, then deploy:

```powershell
npx supabase functions deploy quiz-generate --project-ref pvcereixbqctjrxsalhd
```

This adds server-only extracted lesson text, scoped to instructor, class,
immutable upload path, size, MIME type, model and extraction version. Each
generation still checks current class ownership and reads material metadata.
Changed/replaced sources or a different model cause a cache miss. Questions,
answer keys and additional instructor notes are never cached here.

UTF-8 lessons reuse decoded text. PDF/image misses request a faithful Gemini
transcription before fresh question generation; first use can be slower and
uses additional provider tokens/requests. A shared 20-second extraction budget
limits this extra stage. Rejected, incomplete, oversized or failed extraction
falls back to the original file. AI-reported completeness is not a guarantee
of accurate transcription, especially for diagrams; instructors must review
generated questions. Generation quotas still apply even on cache hits.

Entries expire after seven days and are capped at 30 per instructor. Writes
purge expired entries and evict the oldest above that cap. Expired rows are
ineligible immediately but remain stored until a later cache write. Deleting
a lesson blocks reuse through the required metadata read; its cached text may
remain until expiration/eviction. No new files or public URLs are stored.
If the migration is absent or cache access fails, original file processing
remains available. Activated on 2026-10-04: this migration was applied to
`pvcereixbqctjrxsalhd` and `quiz-generate` deployed successfully. Read-only schema
inspection confirmed RLS, no client access, and service-role access. No sample
data, tests, analysis, builds or live AI generation requests were made.
Manual review: generate from a lesson, then generate another assessment from the
same unchanged file. Review both question sets; the first PDF/image extraction
may be slower. No Flutter rebuild is required for this backend-only activation.

## Mixed question types

Questions support Multiple choice, True or false, Identification, Enumeration,
and Essay. Set 1–100 points per question. Identification accepts alternative
answers (one per line); grading ignores case and repeated whitespace. Enumeration
uses distinct expected items (one per line, up to 20) with optional order checking
and proportional partial credit rounded to two decimals. Essays require a rubric.

Generate with AI now accepts a separate count for each type, up to 20 generated
questions in total. Selected files and notes remain the lesson source. Review
question wording, correct answers, points, and rubric before publishing. Existing
AI quotas and attempt limits remain unchanged.

Students use appropriate choice/text/entry fields with online saving and the same
server deadline and Android capture protection. Essays show Awaiting review after
submission. Open **Quizzes & exams → Published → an assessment** to see student
results. Open a submitted result to score essays and leave feedback. Save review
calculates the final total on the server; students reopen their result to see it.
Existing multiple-choice questions and attempts remain compatible.

No tests, static analysis, builds, or automated device checks were run.

Open an instructor class, choose **Quizzes & exams**, then **Create assessment**.
Choose Quiz or Exam, enter a title, and set a time limit from 1 to 180 minutes.
Each multiple-choice question has four options and one selected correct answer.
Save draft and reopen it to edit. Up to 50 questions are supported.

Drafts and answer keys live in instructor-only
`classes/{classId}/assessmentDrafts/{assessmentId}`. Archived classes are read-only.
Choose **Publish** when ready to make the assessment visible to class members.
Published assessments are immutable and their private drafts are locked. Correct
answers are excluded from the student-readable copy. Existing drafts must be
opened and published; generation alone does not publish.
Students see published cards in the class room's Classwork section. Android
students can start/resume one timed attempt, save answers online, and submit.
The private assessment-attempt backend enforces deadlines and grades without
exposing correct answers. Expired attempts finalize on the next request using
only saved answers. Leaving the page does not pause the timer. An internet
connection is required to save and submit; late new choices are not accepted.

Android answering uses FLAG_SECURE to block normal screenshots/screen recording
and non-selectable text. Full app relaunch from the IDE is needed for the native
change. Other platforms cannot take attempts yet. Protection cannot prevent
external cameras or modified clients/devices; enrolled members still have
authenticated read access to published questions. Instructor result-list UI
is not implemented yet. No automated app or device checks were run.

## AI setup

No AI provider credential was configured when this feature was added. Gemini is
the prepared default; no key is stored in Flutter. Privately add `GEMINI_API_KEY`
to Supabase Edge Function secrets for project `pvcereixbqctjrxsalhd`. Do not paste
the key into chat or commit it. Optional `GEMINI_QUIZ_MODEL` changes the model;
the default is `gemini-2.5-flash`.

`quiz-generate` verifies Firebase login and live instructor ownership before
calling Gemini. SQL migration `202610040003_quiz_generation.sql` limits generation
to ten attempts per instructor per database day. Provider quotas also apply.
No billing settings were changed.

Choose **Generate with AI**, select uploaded lesson files from this class's
Materials, optionally add notes, and request 1–20 questions. Selected file content
and notes are sent to Gemini. Questions are
appended to the editor for review and correction; generation does not save or
publish automatically. Gemini reads PDF pages and images directly; TXT, Markdown,
and CSV are read as UTF-8 text. Up to three files totaling 8 MB are supported;
each text file must be at most 200 KB. Convert DOCX/PPTX and other unsupported
formats to PDF and post them in Materials first. The backend verifies class
ownership and each material's private storage path; clients send material IDs only.
Empty/truncated/invalid output shows an error and preserves existing questions.

The endpoint and private draft rules are deployed. AI requires the key above.
No tests, static analysis, builds, or automated UI checks were run.

API reference: [Gemini structured outputs](https://ai.google.dev/gemini-api/docs/generate-content/structured-output).
