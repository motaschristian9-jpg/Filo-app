import { decode, encode, emptyAnswer, validAnswer, grade } from '../_shared/assessment_types.ts';
import { createClient } from 'npm:@supabase/supabase-js@2';
import { createRemoteJWKSet, importPKCS8, jwtVerify, SignJWT } from 'npm:jose@6';

const project = 'filo-app-1a2a5';
const root = `https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents`;
const keys = createRemoteJWKSet(new URL(
  'https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com'));
const headers = { 'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS', 'Cache-Control': 'no-store' };
const reply = (body: unknown, status = 200) => Response.json(body, { status, headers });
let googleToken = '', expiry = 0;
async function accessToken() {
  if (googleToken && expiry > Date.now() + 60000) return googleToken;
  const account = JSON.parse(Deno.env.get('FIREBASE_SERVICE_ACCOUNT_JSON') ?? '{}');
  if (account.project_id !== project) throw Error();
  const assertion = await new SignJWT({ scope: 'https://www.googleapis.com/auth/datastore' })
    .setProtectedHeader({ alg: 'RS256' }).setIssuer(account.client_email)
    .setAudience('https://oauth2.googleapis.com/token').setIssuedAt().setExpirationTime('1h')
    .sign(await importPKCS8(account.private_key, 'RS256'));
  const response = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST', body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion }),
    signal: AbortSignal.timeout(15000),
  });
  if (!response.ok) throw Error();
  const data = await response.json();
  if (typeof data.access_token !== 'string') throw Error();
  googleToken = data.access_token;
  expiry = Date.now() + Number(data.expires_in ?? 3600) * 1000;
  return googleToken;
}
async function read(path: string, token: string) {
  const response = await fetch(`${root}/${path}`, {
    headers: { Authorization: `Bearer ${token}` }, signal: AbortSignal.timeout(15000) });
  if (response.status === 404) return null;
  if (!response.ok) throw Error();
  return response.json();
}

Deno.serve(async request => {
  if (request.method === 'OPTIONS') return new Response(null, { headers });
  if (request.method !== 'POST') return reply({}, 405);
  try {
    const token = request.headers.get('authorization')?.match(/^Bearer (\S+)$/i)?.[1];
    if (!token) return reply({}, 401);
    let uid: string;
    try {
      const { payload } = await jwtVerify(token, keys, {
        issuer: `https://securetoken.google.com/${project}`, audience: project,
        algorithms: ['RS256'], requiredClaims: ['sub', 'exp', 'iat'],
      });
      if (!payload.sub || typeof payload.iat !== 'number' || payload.iat > Date.now() / 1000 + 30) throw Error();
      uid = payload.sub;
    } catch { return reply({}, 401); }
    const reader = request.body?.getReader();
    if (!reader) return reply({}, 400);
    let text = '', size = 0;
    const decoder = new TextDecoder();
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.length;
      if (size > 600000) { await reader.cancel(); return reply({}, 413); }
      text += decoder.decode(value, { stream: true });
    }
    text += decoder.decode();
    const { classId, assessmentId, action, answers } = JSON.parse(text);
    if (![classId, assessmentId].every(id => typeof id === 'string' && /^[A-Za-z0-9_-]{1,128}$/.test(id)) ||
        !['status', 'start', 'save', 'submit'].includes(action)) return reply({}, 400);
    const adminToken = await accessToken();
    const profile = await read(`users/${encodeURIComponent(uid)}`, adminToken);
    if (profile?.fields?.role?.stringValue !== 'student' ||
        !await read(`classes/${classId}/enrollments/${encodeURIComponent(uid)}`, adminToken)) return reply({}, 403);
    const course = await read(`classes/${classId}`, adminToken);
    const assessment = await read(`classes/${classId}/assessments/${assessmentId}`, adminToken);
    if (!assessment) return reply({}, 404);
    const questions = decode(assessment.fields.questions);
    const path = `classes/${classId}/assessments/${assessmentId}/attempts/${encodeURIComponent(uid)}`;
    const name = root.replace('https://firestore.googleapis.com/v1/', '') + '/' + path;
    let now = Date.now();
    let attempt = await read(path, adminToken);
    if (!attempt && action === 'status') return reply({ status: 'not_started' });
    if (!attempt) {
      if (action !== 'start' || course?.fields?.archived?.booleanValue === true || assessment.fields.hidden?.booleanValue === true) return reply({}, 409);
      const fields = { startedAt: { timestampValue: new Date(now).toISOString() },
        deadline: { timestampValue: new Date(now + Number(assessment.fields.minutes.integerValue) * 60000).toISOString() },
        status: { stringValue: 'active' }, answers: encode(questions.map(emptyAnswer)) };
      const created = await fetch(`${root}:commit`, { method: 'POST',
        headers: { Authorization: `Bearer ${adminToken}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ writes: [{ verify: course.name, currentDocument: { updateTime: course.updateTime } },
          { update: { name, fields }, currentDocument: { exists: false } }] }), signal: AbortSignal.timeout(15000) });
      attempt = await read(path, adminToken);
      if (!attempt) return reply({}, created.ok ? 503 : 409);
    }
    const fields = attempt.fields;
    now = Date.now();
    const deadline = Date.parse(fields.deadline.timestampValue);
    if (fields.status.stringValue === 'active' &&
        (['save', 'submit'].includes(action) || now >= deadline)) {
      if (now < deadline) {
        if (!Array.isArray(answers) || answers.length !== questions.length ||
            answers.some((a, i) => !validAnswer(questions[i], a))) return reply({}, 400);
        fields.answers = encode(answers);
      }
      if (action === 'submit' || now >= deadline) {
        const draft = await read(`classes/${classId}/assessmentDrafts/${assessmentId}`, adminToken);
        if (!draft) return reply({}, 503);
        const keys = decode(draft.fields.questions);
        const saved = decode(fields.answers);
        const grades = keys.map((q: any, i: number) => grade(q, saved[i]));
        const score = Math.round(grades.reduce((sum: number, value: number | null) => sum + (value ?? 0), 0) * 100) / 100;
        fields.status = { stringValue: 'submitted' };
        fields.score = encode(score);
        fields.grades = encode(grades);
        fields.needsReview = encode(grades.some((value: any) => value === null));
        fields.totalPoints = encode(keys.reduce((sum: number, q: any) => sum + (q.points ?? 1), 0));        fields.submittedAt = { timestampValue: new Date(now).toISOString() };
      }
      const updated = await fetch(`${root}:commit`, { method: 'POST',
        headers: { Authorization: `Bearer ${adminToken}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ writes: [{ update: { name, fields },
          currentDocument: { updateTime: attempt.updateTime } }] }), signal: AbortSignal.timeout(15000) });
      if (!updated.ok) return reply({}, 409);
    }
    return reply({ status: fields.status.stringValue, deadline: fields.deadline.timestampValue,
      serverNow: new Date().toISOString(), answers: decode(fields.answers),
      score: fields.score ? decode(fields.score) : null,
      needsReview: fields.needsReview ? decode(fields.needsReview) : false,
      totalPoints: fields.totalPoints ? decode(fields.totalPoints) : questions.reduce((n: number, q: any) => n + (q.points ?? 1), 0),
      feedback: fields.feedback ? decode(fields.feedback) : '', questions });  } catch { return reply({}, 503); }
});
