import { nowIso } from './util.js';
export async function audit(env, actor, action, detail) {
  await env.DB.prepare('INSERT INTO audit_log (ts, actor, action, detail) VALUES (?,?,?,?)').bind(nowIso(), actor, action, detail === undefined ? null : JSON.stringify(detail).slice(0, 8000)).run();
}
