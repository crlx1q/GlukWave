export type TimedLine = { time: number | null; text: string };

/** Derive every lyric cue from the media clock; pausing/seeking needs no timer. */
export function lyricCue(lines: readonly TimedLine[], synchronized: boolean, position: number) {
  const sung = (line: TimedLine) => !!line.text.trim() && !/^[♪♫♬\s·.…-]+$/u.test(line.text);
  const active = synchronized ? lines.reduce((found, line, index) =>
    sung(line) && line.time !== null && Number.isFinite(line.time) && line.time <= position ? index : found, -1) : -1;
  const first = synchronized ? lines.find(line => sung(line) && line.time !== null && Number.isFinite(line.time))?.time : null;
  const remaining = first !== null && first !== undefined && first > 0 ? first - position : 0;
  const countdown = remaining > 0 && remaining <= 3 && active < 0 ? Math.ceil(remaining) : null;
  return { active, countdown, intro: synchronized && first !== null && first !== undefined && first > position, remaining };
}

export function lyricDefocus(distance: number, active: number) {
  return active < 0 || distance <= 1 ? 0 : Math.min(5, (distance - 1) * 1.15);
}
