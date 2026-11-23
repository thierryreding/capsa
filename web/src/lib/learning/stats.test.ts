import { describe, expect, it } from 'vitest';
import type { ProfileDocument } from '../api/client';
import type { AnswerEvent, LeitnerConfig } from './leitner';
import { learningStats, type LearningStats } from './stats';
import { loadJson, loadProfile } from './testing';

const vectors = loadJson<{
  profile: string;
  now: number;
  config: LeitnerConfig;
  events: AnswerEvent[];
  expected: LearningStats;
}>('vectors/stats.json');
const demo = loadProfile(vectors.profile) as unknown as ProfileDocument;

describe('learningStats', () => {
  it('shared vector (vectors/stats.json), as on the server', () => {
    expect(learningStats(demo, vectors.events, vectors.now, vectors.config)).toEqual(
      vectors.expected,
    );
  });

  it('no events', () => {
    const s = learningStats(demo, [], vectors.now, vectors.config);
    expect(s.total_answers).toBe(0);
    expect(s.last_answer_at).toBeNull();
    expect(s.units.map((u) => u.fresh)).toEqual([10, 9]);
    expect(s.days).toHaveLength(14);
  });
});
