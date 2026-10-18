const KEY = 'zworld_save_v2';

export class SaveManager {
  static load<T>(): T | null {
    try {
      const raw = window.localStorage.getItem(KEY);
      return raw ? (JSON.parse(raw) as T) : null;
    } catch {
      return null;
    }
  }

  static save<T>(data: T): void {
    try {
      window.localStorage.setItem(KEY, JSON.stringify(data));
    } catch {
      // 存储失败静默忽略（隐私模式等）
    }
  }

  static clear(): void {
    try {
      window.localStorage.removeItem(KEY);
    } catch {
      // 同上
    }
  }
}
