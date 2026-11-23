/** Account helpers for the UI. Pure functions. */
import type { Me } from './store/db';

/** The display name if set, otherwise the username. */
export function greetingName(me: Pick<Me, 'username' | 'display_name'>): string {
  return me.display_name?.trim() || me.username;
}

export const DISPLAY_NAME_MAX = 64;

/** Mirrors the server's rules: trimmed, at most 64 characters, no control characters.
 * Returns the value to send (null clears the name), or 'invalid'. */
export function displayNameInput(raw: string): string | null | 'invalid' {
  const name = raw.trim();
  if (!name) return null;
  if ([...name].length > DISPLAY_NAME_MAX || /[\u0000-\u001f\u007f-\u009f]/.test(name)) {
    return 'invalid';
  }
  return name;
}
