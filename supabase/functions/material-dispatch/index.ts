import { createClient } from 'npm:@supabase/supabase-js@2';
import { createRemoteJWKSet, importPKCS8, jwtVerify, SignJWT } from 'npm:jose@6';

const project = 'filo-app-1a2a5';
const root = `https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents`;
const keys = createRemoteJWKSet(new URL(
  'https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com'));
const headers = { 'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, apikey, content-type, x-worker-secret',
  'Access-Control-Allow-Methods': 'POST, OPTIONS', 'Cache-Control': 'no-store' };
class Failure extends Error { constructor(public status: number) { super('Dispatch failed'); } }
const reply = (body: unknown, status = 200) => Response.json(body, { status, headers });
const admin = () => createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  { auth: { persistSession: false, autoRefreshToken: false } });
type Admin = ReturnType<typeof admin>;
let googleToken = '', googleExpiry = 0;

async function accessToken() {
  if (googleToken && googleExpiry > Date.now() + 60000) return googleToken;
  const account = JSON.parse(Deno.env.get('FIREBASE_SERVICE_ACCOUNT_JSON') ?? '{}');
  if (account.project_id !== project || typeof account.client_email !== 'string' ||
      typeof account.private_key !== 'string') throw new Failure(503);
  const assertion = await new SignJWT({ scope:
    'https://www.googleapis.com/auth/datastore https://www.googleapis.com/auth/firebase.messaging' })
    .setProtectedHeader({ alg: 'RS256' }).setIssuer(account.client_email)
    .setAudience('https://oauth2.googleapis.com/token').setIssuedAt().setExpirationTime('1h')
    .sign(await importPKCS8(account.private_key, 'RS256'));
  const response = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST', body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion }),
    signal: AbortSignal.timeout(15000),
  });
  if (!response.ok) throw new Failure(503);
  const data = await response.json();
  if (typeof data.access_token !== 'string') throw new Failure(503);
  googleToken = data.access_token;
  googleExpiry = Date.now() + Number(data.expires_in ?? 3600) * 1000;
  return googleToken;
}
async function read(path: string, token: string) {
  const response = await fetch(`${root}/${path}`, {
    headers: { Authorization: `Bearer ${token}` }, signal: AbortSignal.timeout(15000) });
  if (response.status === 404) return null;
  if (!response.ok) throw new Failure(response.status === 403 ? 403 : 503);
  return await response.json();
}
async function page(path: string, token: string, cursor: string, size: number) {
  const params = new URLSearchParams({ pageSize: String(size), orderBy: '__name__' });
  if (cursor) params.set('pageToken', cursor);
  return await read(`${path}?${params}`, token) ?? { documents: [] };
}

async function send(token: string, uid: string, device: any, job: any) {
  // Recheck membership and the exact registration before every send. Never take
  // recipient IDs, notification text, or device tokens from the posting client.
  const enrollment = await read(`classes/${job.class_id}/enrollments/${encodeURIComponent(uid)}`, token);
  if (!enrollment) return;
  const devicePath = device.name.split('/documents/')[1];
  const current = await read(devicePath, token);
  const registration = current?.fields?.token?.stringValue;
  if (!registration) return;
  const response = await fetch(`https://fcm.googleapis.com/v1/projects/${project}/messages:send`, {
    method: 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ message: {
      token: registration,
      notification: { title: 'New class material', body: 'Open Filo to see what is new.' },
      data: { uid, classId: job.class_id, materialId: job.material_id },
      android: { priority: 'high', ttl: '86400s',
        notification: { tag: `${job.class_id}_${job.material_id}`, sound: 'default' } },
    } }), signal: AbortSignal.timeout(15000),
  });
  if (response.ok) return;
  const error = await response.json().catch(() => ({}));
  const unregistered = error.error?.details?.some((detail: any) =>
    detail['@type'] === 'type.googleapis.com/google.firebase.fcm.v1.FcmError' &&
    detail.errorCode === 'UNREGISTERED');
  if (unregistered) {
    // Conditional deletion cannot remove a refreshed registration.
    const params = new URLSearchParams({ 'currentDocument.updateTime': current.updateTime });
    const removed = await fetch(`${root}/${devicePath}?${params}`, {
      method: 'DELETE', headers: { Authorization: `Bearer ${token}` },
      signal: AbortSignal.timeout(15000) });
    if (![200, 404, 409, 412].includes(removed.status)) throw new Failure(503);
    return;
  }
  throw new Failure(503);
}

async function drain(db: Admin, classId?: string, materialId?: string) {
  const deadline = Date.now() + 45000;
  const { data, error } = await db.rpc('claim_material_dispatch', {
    p_class: classId ?? null, p_material: materialId ?? null });
  if (error) throw new Failure(503);
  const job = data?.[0];
  if (!job) return;
  async function save(values: Record<string, unknown>) {
    const result = await db.from('material_dispatch_jobs').update(values)
      .eq('class_id', job.class_id).eq('material_id', job.material_id).eq('lease_id', job.lease_id)
      .select('class_id');
    if (result.error || result.data?.length !== 1) throw new Failure(503);
  }
  try {
    const token = await accessToken();
    const post = await read(`classes/${job.class_id}/materials/${job.material_id}`, token);
    if (!post) {
      await save({ available_at: new Date(Date.now() + 60000).toISOString(), lease_until: null, lease_id: null });
      return;
    }
    if (post.fields?.authorId?.stringValue !== job.author_id ||
        post.fields?.classId?.stringValue !== job.class_id) {
      await save({ finished_at: new Date().toISOString(), lease_until: null, lease_id: null });
      return;
    }
    while (Date.now() < deadline) {
      const students = await page(`classes/${job.class_id}/enrollments`, token, job.enrollment_page, 1);
      const student = students.documents?.[0];
      if (!student) {
        await save({ finished_at: new Date().toISOString(), lease_until: null, lease_id: null });
        return;
      }
      const uid = student.name.split('/').pop();
      const devices = await page(`users/${encodeURIComponent(uid)}/devices`, token, job.device_page, 5);
      const results = await Promise.allSettled((devices.documents ?? []).map((device: any) => send(token, uid, device, job)));
      if (results.some((result) => result.status === 'rejected')) throw new Failure(503);
      job.device_page = devices.nextPageToken ?? '';
      if (!job.device_page) {
        job.enrollment_page = students.nextPageToken ?? '';
        if (!job.enrollment_page) {
          await save({ finished_at: new Date().toISOString(), lease_until: null, lease_id: null });
          return;
        }
      }
      await save({ enrollment_page: job.enrollment_page, device_page: job.device_page });
    }
    await save({ lease_until: null, lease_id: null, available_at: new Date().toISOString() });
  } catch {
    await save({ lease_until: null, lease_id: null,
      available_at: new Date(Date.now() + Math.min(900, 30 * job.attempts) * 1000).toISOString() });
    // No credentials, signed URLs, device tokens, or raw provider errors in logs.
    console.warn('Material delivery deferred');
  }
}

Deno.serve(async (request: Request) => {
  if (request.method === 'OPTIONS') return new Response(null, { headers });
  if (request.method !== 'POST') return reply({ error: 'method_not_allowed' }, 405);
  try {
    const db = admin();
    const workerSecret = Deno.env.get('MATERIAL_WORKER_SECRET');
    if (workerSecret && request.headers.get('x-worker-secret') === workerSecret) {
      await drain(db);
      return reply({ ok: true });
    }
    const token = request.headers.get('authorization')?.match(/^Bearer (\S+)$/i)?.[1];
    if (!token) throw new Failure(401);
    let uid: string;
    try {
      const { payload } = await jwtVerify(token, keys, {
        issuer: `https://securetoken.google.com/${project}`, audience: project,
        algorithms: ['RS256'], requiredClaims: ['sub', 'iat', 'exp', 'auth_time'],
      });
      const now = Math.floor(Date.now() / 1000);
      if (!payload.sub || payload.sub.length > 128 || typeof payload.iat !== 'number' ||
          payload.iat > now + 30 || typeof payload.auth_time !== 'number' || payload.auth_time > now + 30) {
        throw new Failure(401);
      }
      uid = payload.sub;
    } catch { throw new Failure(401); }
    const reader = request.body?.getReader();
    if (!reader) throw new Failure(400);
    const chunks: Uint8Array[] = [];
    let size = 0;
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.length;
      if (size > 4096) { await reader.cancel(); throw new Failure(413); }
      chunks.push(value);
    }
    const bytes = new Uint8Array(size);
    let offset = 0;
    for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
    let body;
    try { body = JSON.parse(new TextDecoder().decode(bytes)); } catch { throw new Failure(400); }
    const { classId, materialId } = body ?? {};
    if (typeof classId !== 'string' || typeof materialId !== 'string' ||
        !/^[A-Za-z0-9_-]{1,128}$/.test(classId) || !/^[A-Za-z0-9_-]{1,128}$/.test(materialId)) {
      throw new Failure(400);
    }
    const course = await read(`classes/${classId}`, token);
    if (course?.fields?.instructorId?.stringValue !== uid) throw new Failure(403);
    // A retry after archiving may still confirm an existing, immutable post.
    const post = await read(`classes/${classId}/materials/${materialId}`, token);
    if (!post && course.fields?.archived?.booleanValue === true) throw new Failure(403);
    if (post && post.fields?.authorId?.stringValue !== uid) throw new Failure(403);
    if (!Deno.env.get('FIREBASE_SERVICE_ACCOUNT_JSON') || !workerSecret) throw new Failure(503);
    const { error } = await db.rpc('prepare_material_dispatch', {
      p_class: classId, p_material: materialId, p_author: uid });
    if (error) throw new Failure(503);
    if (post) {
      // Supabase keeps this task alive after returning the response; Cron retries
      // if the process is interrupted or another job was ahead in the queue.
      EdgeRuntime.waitUntil(drain(db, classId, materialId).catch(() => console.warn('Material worker unavailable')));
    }
    return reply({ queued: true });
  } catch (error) {
    return reply({ error: 'delivery_unavailable' }, error instanceof Failure ? error.status : 503);
  }
});
