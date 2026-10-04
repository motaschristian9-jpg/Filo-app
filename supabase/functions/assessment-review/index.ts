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
    const { classId, assessmentId, action, studentUid, essayGrades, feedback, cursor } = JSON.parse(text);
    if (![classId, assessmentId].every(id => typeof id === 'string' && /^[A-Za-z0-9_-]{1,128}$/.test(id)) ||
        !['list', 'review'].includes(action)) return reply({}, 400);
    const adminToken = await accessToken();
    const course = await read(`classes/${classId}`, adminToken);
    if (course?.fields?.instructorId?.stringValue !== uid) return reply({}, 403);
    const draft = await read(`classes/${classId}/assessmentDrafts/${assessmentId}`, adminToken);
    if (!draft) return reply({}, 404);
    const questions = decode(draft.fields.questions);
    const base = `classes/${classId}/assessments/${assessmentId}/attempts`;
    if (action === 'list') {
      if (cursor && (typeof cursor !== 'string' || cursor.length > 4000)) return reply({}, 400);
      const params = new URLSearchParams({ pageSize: '30' });
      if (cursor) params.set('pageToken', cursor);
      const result = await read(`${base}?${params}`, adminToken) ?? {};
      const attempts = await Promise.all((result.documents ?? []).map(async (doc: any) => {
        const student = doc.name.split('/').pop();
        const profile = await read(`users/${encodeURIComponent(student)}`, adminToken);
        return { uid: student, name: profile?.fields?.name?.stringValue ?? 'Student',
          ...decode({ mapValue: { fields: doc.fields } }) };
      }));
      return reply({ attempts, questions, cursor: result.nextPageToken ?? null });
    }
    if (typeof studentUid !== 'string' || studentUid.length > 128 || !studentUid ||
        typeof feedback !== 'string' || feedback.length > 2000 || !essayGrades || Array.isArray(essayGrades)) return reply({}, 400);
    const path = `${base}/${encodeURIComponent(studentUid)}`;
    const attempt = await read(path, adminToken);
    if (!attempt || attempt.fields.status.stringValue !== 'submitted') return reply({}, 409);
    const answers = decode(attempt.fields.answers);
    const essayIndices = questions.map((q: any, i: number) => q.type === 'essay' ? String(i) : null).filter(Boolean);
    if (Object.keys(essayGrades).length !== essayIndices.length ||
        essayIndices.some((i: string) => typeof essayGrades[i] !== 'number' || !Number.isFinite(essayGrades[i]) ||
          essayGrades[i] < 0 || essayGrades[i] > questions[Number(i)].points)) return reply({}, 400);
    const grades = questions.map((q: any, i: number) => q.type === 'essay' ? essayGrades[String(i)] : grade(q, answers[i]));
    const fields = { ...attempt.fields, grades: encode(grades),
      score: encode(Math.round(grades.reduce((sum: number, n: number) => sum + n, 0) * 100) / 100),
      totalPoints: encode(questions.reduce((sum: number, q: any) => sum + (q.points ?? 1), 0)),
      needsReview: encode(false), feedback: encode(feedback),
      reviewedAt: { timestampValue: new Date().toISOString() }, reviewerId: encode(uid) };
    const saved = await fetch(`${root}:commit`, { method: 'POST',
      headers: { Authorization: `Bearer ${adminToken}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ writes: [{ update: { name: attempt.name, fields },
        currentDocument: { updateTime: attempt.updateTime } }] }), signal: AbortSignal.timeout(15000) });
    return saved.ok ? reply({ saved: true }) : reply({}, 409);
  } catch { return reply({}, 503); }
});
