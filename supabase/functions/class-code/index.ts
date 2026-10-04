import { createClient } from 'npm:@supabase/supabase-js@2';
import { createRemoteJWKSet, jwtVerify } from 'npm:jose@6';

const project = 'filo-app-1a2a5';
const root = `https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents`;
const keys = createRemoteJWKSet(new URL(
  'https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com'));
const headers = { 'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS', 'Cache-Control': 'no-store' };
const reply = (body: unknown, status = 200) => Response.json(body, { status, headers });

Deno.serve(async request => {
  if (request.method === 'OPTIONS') return new Response(null, { headers });
  if (request.method !== 'POST') return reply({ error: 'method_not_allowed' }, 405);
  try {
    const token = request.headers.get('authorization')?.match(/^Bearer (\S+)$/i)?.[1];
    if (!token) return reply({ error: 'unauthenticated' }, 401);
    let uid: string;
    try {
      const { payload } = await jwtVerify(token, keys, {
        issuer: `https://securetoken.google.com/${project}`, audience: project,
        algorithms: ['RS256'], requiredClaims: ['sub', 'exp', 'iat'],
      });
      if (!payload.sub || typeof payload.iat !== 'number' ||
          payload.iat > Date.now() / 1000 + 30) throw Error();
      uid = payload.sub;
    } catch { return reply({ error: 'unauthenticated' }, 401); }
    const reader = request.body?.getReader();
    if (!reader) return reply({ error: 'invalid_request' }, 400);
    const chunks: Uint8Array[] = [];
    let length = 0;
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      length += value.length;
      if (length > 1024) { await reader.cancel(); return reply({}, 413); }
      chunks.push(value);
    }
    const bytes = new Uint8Array(length);
    let offset = 0;
    for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
    const { classId } = JSON.parse(new TextDecoder().decode(bytes));
    if (typeof classId !== 'string' || !/^[A-Za-z0-9_-]{1,128}$/.test(classId)) {
      return reply({ error: 'invalid_class' }, 400);
    }
    const auth = { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' };
    const url = `${root}/classes/${classId}`;
    const course = await fetch(url, { headers: auth, signal: AbortSignal.timeout(15000) });
    if (!course.ok) return reply({ error: 'class_unavailable' }, course.status === 404 ? 404 : 403);
    const data = await course.json();
    if (data.fields?.instructorId?.stringValue !== uid) return reply({}, 403);
    const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
    let code = '';
    const alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
    for (let attempt = 0; attempt < 12; attempt++) {
      const current = await db.from('class_codes').select('code').eq('class_id', classId).maybeSingle();
      if (current.error) throw Error();
      if (current.data) { code = current.data.code; break; }
      const random = crypto.getRandomValues(new Uint32Array(6));
      const candidate = Array.from(random, n => alphabet[n % alphabet.length]).join('');
      const inserted = await db.from('class_codes').insert({ class_id: classId, code: candidate });
      if (!inserted.error) { code = candidate; break; }
      if (inserted.error.code !== '23505') throw Error();
    }
    if (!code) throw Error();
    // Firebase evaluates the caller's live ownership again on this write.
    // Retries always copy the same reserved code; existing class IDs never move.
    const saved = await fetch(url + '?updateMask.fieldPaths=code', {
      method: 'PATCH', headers: auth,
      body: JSON.stringify({ fields: { code: { stringValue: code } } }),
      signal: AbortSignal.timeout(15000),
    });
    if (!saved.ok) return reply({ error: 'could_not_save_code' }, saved.status === 403 ? 403 : 503);
    return reply({ code });
  } catch { return reply({ error: 'code_unavailable' }, 503); }
});

