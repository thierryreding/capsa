/**
 * Installation and storage persistence (SPEC 9). The decision what to show is a pure
 * function; the browser checks are thin wrappers around it.
 */

export const IOS_WARN_AFTER_MS = 5 * 24 * 60 * 60 * 1000;

export type InstallAdvice =
  | 'none'
  /** iOS, not installed: explain "Share → Add to Home Screen". */
  | 'ios-hint'
  /** iOS, not installed and not synced for days: Safari may delete the data. */
  | 'ios-warning'
  /** Chrome/Android offered its install prompt. */
  | 'prompt';

export interface InstallSituation {
  ios: boolean;
  standalone: boolean;
  canPrompt: boolean;
  lastSyncAt: number | null;
  now: number;
}

export function installAdvice(s: InstallSituation): InstallAdvice {
  if (s.standalone) return 'none';
  if (s.ios) {
    const stale = s.lastSyncAt !== null && s.now - s.lastSyncAt > IOS_WARN_AFTER_MS;
    return stale ? 'ios-warning' : 'ios-hint';
  }
  return s.canPrompt ? 'prompt' : 'none';
}

export function isStandalone(): boolean {
  return (
    window.matchMedia('(display-mode: standalone)').matches ||
    (navigator as Navigator & { standalone?: boolean }).standalone === true
  );
}

/** iPhone, iPod, and iPad (which reports itself as a Mac with touch). */
export function isIOS(): boolean {
  const ua = navigator.userAgent;
  return /iPhone|iPad|iPod/.test(ua) || (ua.includes('Macintosh') && navigator.maxTouchPoints > 1);
}

/** Ask the browser not to evict our data (Chrome/Android; iOS relies on installation). */
export async function requestPersistentStorage(): Promise<boolean> {
  try {
    if (!navigator.storage?.persist) return false;
    if (await navigator.storage.persisted()) return true;
    return await navigator.storage.persist();
  } catch {
    return false;
  }
}

/** The `beforeinstallprompt` event (Chromium only, not in the DOM typings). */
export interface InstallPromptEvent extends Event {
  prompt(): Promise<void>;
  userChoice: Promise<{ outcome: 'accepted' | 'dismissed' }>;
}
