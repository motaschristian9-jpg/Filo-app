export const types = ['multiple_choice', 'true_false', 'identification', 'enumeration', 'essay'];
export const normalize = (s: string) => s.trim().toLowerCase().replace(/\s+/g, ' ');
export function decode(v: any): any {
  if ('stringValue' in v) return v.stringValue;
  if ('integerValue' in v) return Number(v.integerValue);
  if ('doubleValue' in v) return v.doubleValue;
  if ('booleanValue' in v) return v.booleanValue;
  if ('timestampValue' in v) return v.timestampValue;
  if ('nullValue' in v) return null;
  if ('arrayValue' in v) return (v.arrayValue.values ?? []).map(decode);
  return Object.fromEntries(Object.entries(v.mapValue.fields ?? {}).map(([k, value]) => [k, decode(value)]));
}
export function encode(v: any): any {
  if (v === null) return { nullValue: null };
  if (typeof v === 'string') return { stringValue: v };
  if (typeof v === 'number') return Number.isInteger(v) ? { integerValue: String(v) } : { doubleValue: v };
  if (typeof v === 'boolean') return { booleanValue: v };
  if (Array.isArray(v)) return { arrayValue: { values: v.map(encode) } };
  return { mapValue: { fields: Object.fromEntries(Object.entries(v).map(([k, value]) => [k, encode(value)])) } };
}
export function validQuestion(q: any) {
  const type = q.type ?? 'multiple_choice';
  const points = q.points ?? 1;
  const strings = (a: any, max = 20) => Array.isArray(a) && a.length > 0 && a.length <= max &&
    a.every((s: any) => typeof s === 'string' && s.trim().length > 0 && s.length <= 500);
  if (!types.includes(type) || typeof q.prompt !== 'string' || !q.prompt.trim() || q.prompt.length > 1000 ||
      !Number.isInteger(points) || points < 1 || points > 100) return false;
  if (type === 'multiple_choice' || type === 'true_false') {
    const count = type === 'true_false' ? 2 : 4;
    return strings(q.options, count) && q.options.length === count &&
      new Set(q.options.map(normalize)).size === count && Number.isInteger(q.answer) && q.answer >= 0 && q.answer < count &&
      (type !== 'true_false' || q.options[0] === 'True' && q.options[1] === 'False');
  }
  if (type === 'identification') return strings(q.acceptedAnswers);
  if (type === 'enumeration') return strings(q.expectedAnswers) && typeof q.ordered === 'boolean' &&
    new Set(q.expectedAnswers.map(normalize)).size === q.expectedAnswers.length;
  return typeof q.rubric === 'string' && q.rubric.trim().length > 0 && q.rubric.length <= 5000;
}
export const emptyAnswer = (q: any) => {
  const type = q.type ?? 'multiple_choice';
  return ['multiple_choice', 'true_false'].includes(type) ? -1 : type === 'enumeration'
    ? { entries: Array(q.entryCount).fill('') } : '';
};
export function validAnswer(q: any, a: any) {
  const type = q.type ?? 'multiple_choice';
  if (['multiple_choice', 'true_false'].includes(type)) return Number.isInteger(a) && a >= -1 && a < q.options.length;
  if (type === 'enumeration') return a && Array.isArray(a.entries) && a.entries.length === q.entryCount &&
    a.entries.every((s: any) => typeof s === 'string' && s.length <= 500);
  return typeof a === 'string' && a.length <= (type === 'essay' ? 10000 : 500);
}
export function grade(q: any, a: any): number | null {
  const points = q.points ?? 1, type = q.type ?? 'multiple_choice';
  if (type === 'essay') return null;
  if (['multiple_choice', 'true_false'].includes(type)) return a === q.answer ? points : 0;
  if (type === 'identification') return q.acceptedAnswers.map(normalize).includes(normalize(a)) ? points : 0;
  const expected = q.expectedAnswers.map(normalize);
  const entries = a.entries.map(normalize);
  const matched = q.ordered ? expected.filter((s: string, i: number) => s === entries[i]).length
    : expected.filter((s: string) => new Set(entries).has(s)).length;
  return Math.round(points * matched / expected.length * 100) / 100;
}
