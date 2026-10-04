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
      if (size > 1024) { await reader.cancel(); return reply({}, 413); }
      text += decoder.decode(value, { stream: true });
    }
    text += decoder.decode();
    let code: unknown;
    try { code = JSON.parse(text).code; } catch { return reply({}, 400); }
    if (typeof code !== 'string' || !/^[A-HJ-KM-NP-Z2-9]{6}$/.test(code)) return reply({}, 400);
    const adminToken = await accessToken();
    const profile = await read(`users/${encodeURIComponent(uid)}`, adminToken);
    if (profile?.fields?.role?.stringValue !== 'student') return reply({}, 403);
    const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
    const limit = await db.rpc('allow_class_join', { p_uid: uid });
    if (limit.error) throw Error();
    if (!limit.data) return reply({}, 429);
    const match = await db.from('class_codes').select('class_id').eq('code', code).maybeSingle();
    if (match.error) throw Error();
    if (!match.data) return reply({}, 404);
    const classId = match.data.class_id;
    const course = await read(`classes/${classId}`, adminToken);
    if (!course || course.fields?.code?.stringValue !== code) return reply({}, 404);
    const enrollmentPath = `classes/${classId}/enrollments/${encodeURIComponent(uid)}`;
    const existing = await read(enrollmentPath, adminToken);
    if (existing) return reply({ classId, alreadyJoined: true });
    if (course.fields?.archived?.booleanValue === true) return reply({}, 409);
    // Atomic class-version precondition rejects an archive or code change that
    // happens during joining. Enrollment create is idempotent across retries.
    const name = `${root.replace('https://firestore.googleapis.com/v1/', '')}/${enrollmentPath}`;
    const saved = await fetch(`${root}:commit`, {
      method: 'POST', headers: { Authorization: `Bearer ${adminToken}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ writes: [
        { verify: course.name, currentDocument: { updateTime: course.updateTime } },
        { update: { name, fields: { studentId: { stringValue: uid } } },
          currentDocument: { exists: false },
          updateTransforms: [{ fieldPath: 'joinedAt', setToServerValue: 'REQUEST_TIME' }] },
      ] }), signal: AbortSignal.timeout(15000),
    });
    if (!saved.ok) {
      if (await read(enrollmentPath, adminToken)) return reply({ classId, alreadyJoined: true });
      return reply({}, 503);
    }
    return reply({ classId, alreadyJoined: false });
  } catch { return reply({}, 503); }
});
