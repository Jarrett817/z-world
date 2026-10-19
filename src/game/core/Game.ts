import { DataLoader, GameEvent, Survivor } from './DataLoader';
import { SaveManager } from './SaveManager';

export interface PlacedFacility {
  facilityId: string;
  x: number;
  y: number;
}

export type Phase = 'profession' | 'event' | 'route' | 'driving' | 'finished';
export type Weather = 'clear' | 'rain' | 'fog' | 'snow';

export interface Travel {
  from: string;
  to: string;
  km: number;
  done: number;
}

export interface GameState {
  profession: string | null;
  phase: Phase;
  currentNode: string;
  visited: string[];
  food: number;
  stamina: number;
  morale: number;
  fuel: number;
  team: Survivor[];
  currentEvent: GameEvent | null;
  finished: boolean;
  travel: Travel | null;
  rvLayout: PlacedFacility[];
  weather: Weather;
}

type Listener = () => void;

const BASE_CAPS = { food: 20, stamina: 10, fuel: 12 };

const INITIAL: GameState = {
  profession: null,
  phase: 'profession',
  currentNode: 'start',
  visited: ['start'],
  food: 8,
  stamina: 8,
  morale: 5,
  fuel: 8,
  team: [],
  currentEvent: null,
  finished: false,
  travel: null,
  rvLayout: [...DataLoader.getRvConfig().initialLayout],
  weather: 'clear',
};

class GameClass {
  private state: GameState;
  private listeners = new Set<Listener>();

  constructor() {
    const saved = SaveManager.load<GameState>();
    if (saved) {
      // 旧存档兼容：补充缺失字段
      this.state = { ...INITIAL, ...saved, weather: saved.weather ?? 'clear' };
    } else {
      this.state = { ...INITIAL };
    }
  }

  subscribe = (fn: Listener): (() => void) => {
    this.listeners.add(fn);
    return () => this.listeners.delete(fn);
  };

  getState = (): GameState => this.state;

  private emit(): void {
    SaveManager.save(this.state);
    this.listeners.forEach((fn) => fn());
  }

  private set(patch: Partial<GameState>): void {
    this.state = { ...this.state, ...patch };
    this.emit();
  }

  // ---- 资源上限（基础 + 设施加成） ----
  getCaps(): { food: number; stamina: number; fuel: number } {
    let food = BASE_CAPS.food;
    let stamina = BASE_CAPS.stamina;
    for (const p of this.state.rvLayout) {
      const f = DataLoader.getFacility(p.facilityId);
      if (!f) continue;
      food += f.effect.foodMax ?? 0;
      stamina += f.effect.staminaMax ?? 0;
    }
    return { food, stamina, fuel: BASE_CAPS.fuel };
  }

  private clamp(food: number, stamina: number, morale: number, fuel: number) {
    const caps = this.getCaps();
    return {
      food: Math.min(caps.food, Math.max(0, food)),
      stamina: Math.min(caps.stamina, Math.max(0, stamina)),
      morale: Math.max(0, morale),
      fuel: Math.min(caps.fuel, Math.max(0, fuel)),
    };
  }

  // ---- 职业选择（开局） ----
  chooseProfession(id: string): void {
    const p = DataLoader.getProfession(id);
    if (!p || this.state.profession) return;
    const startNode = DataLoader.getNode('start');
    const ev = startNode?.eventId ? DataLoader.getEvent(startNode.eventId) : null;
    const r = this.clamp(
      this.state.food + (p.bonus.food ?? 0),
      this.state.stamina + (p.bonus.stamina ?? 0),
      this.state.morale + (p.bonus.morale ?? 0),
      this.state.fuel,
    );
    this.set({ profession: id, ...r, currentEvent: ev, phase: ev ? 'event' : 'route' });
  }

  // ---- 驾驶逻辑 ----
  private lastEmittedDone = 0;

  /** 当前节点可选的未访问路线 */
  getRoutes(): { to: string; km: number }[] {
    if (this.state.phase !== 'route') return [];
    return DataLoader.getOutgoing(this.state.currentNode)
      .filter((e) => !this.state.visited.includes(e.to))
      .map((e) => ({ to: e.to, km: e.km }));
  }

  chooseRoute(to: string): boolean {
    if (this.state.phase !== 'route') return false;
    const edge = DataLoader.getEdge(this.state.currentNode, to);
    if (!edge || this.state.visited.includes(to)) return false;
    this.lastEmittedDone = 0;
    this.set({
      travel: { from: edge.from, to: edge.to, km: edge.km, done: 0 },
      phase: 'driving',
    });
    return true;
  }

  /** 场景每帧调用；deltaKm 为本帧行驶里程。React 同步按 0.1km 节流 */
  driveTick(deltaKm: number): void {
    const t = this.state.travel;
    if (this.state.phase !== 'driving' || !t || deltaKm <= 0) return;

    const done = Math.min(t.km, t.done + deltaKm);
    const fuel = Math.max(0, this.state.fuel - deltaKm * DataLoader.getFuelPerKm());

    // 天气随机切换：每 0.5km 有 15% 概率变天
    let weather = this.state.weather;
    if (done - this.lastEmittedDone >= 0.5 && Math.random() < 0.15) {
      const pool: Weather[] = ['clear', 'rain', 'fog', 'snow'];
      weather = pool[Math.floor(Math.random() * pool.length)];
    }

    if (fuel <= 0) {
      this.lastEmittedDone = done;
      this.set({
        fuel: 0,
        travel: { ...t, done },
        currentEvent: DataLoader.getEvent('ev_stall'),
        phase: 'event',
        weather,
      });
      return;
    }

    if (done >= t.km) {
      this.arrive(t.to, fuel);
      return;
    }

    if (done - this.lastEmittedDone >= 0.1) {
      this.lastEmittedDone = done;
      this.set({ fuel, travel: { ...t, done }, weather });
    } else {
      this.state = { ...this.state, fuel, travel: { ...t, done }, weather };
    }
  }

  private arrive(to: string, fuel: number): void {
    const node = DataLoader.getNode(to);
    let stamina = this.state.stamina;
    for (const p of this.state.rvLayout) {
      stamina += DataLoader.getFacility(p.facilityId)?.effect.staminaPerMove ?? 0;
    }
    const r = this.clamp(this.state.food, stamina, this.state.morale, fuel);
    this.lastEmittedDone = 0;

    const patch: Partial<GameState> = {
      currentNode: to,
      visited: [...this.state.visited, to],
      travel: null,
      ...r,
    };
    if (to === 'end') {
      patch.phase = 'finished';
      patch.finished = true;
    } else if (node?.eventId) {
      const ev = DataLoader.getEvent(node.eventId);
      patch.currentEvent = ev;
      patch.phase = 'event';
    } else {
      patch.phase = 'route';
    }
    this.set(patch);
  }

  // ---- 事件 ----
  applyChoice(index: number): void {
    const ev = this.state.currentEvent;
    if (!ev) return;
    const choice = ev.choices[index];
    if (!choice) return;

    const patch: Partial<GameState> = { currentEvent: null };

    const e = choice.effects ?? {};
    Object.assign(
      patch,
      this.clamp(
        this.state.food + (e.food ?? 0),
        this.state.stamina + (e.stamina ?? 0),
        this.state.morale + (e.morale ?? 0),
        this.state.fuel + (e.fuel ?? 0),
      ),
    );

    if (choice.recruit) {
      const s = DataLoader.getSurvivor(choice.recruit);
      if (s && !this.state.team.some((m) => m.id === s.id)) {
        patch.team = [...this.state.team, s];
      }
    }

    // 抛锚事件选完继续赶路；普通事件后进选路/终局
    if (ev.id === 'ev_stall' && this.state.travel) {
      patch.phase = 'driving';
    } else {
      const hasNext = DataLoader.getOutgoing(this.state.currentNode).some(
        (e) => !this.state.visited.includes(e.to),
      );
      patch.phase = hasNext ? 'route' : 'finished';
      if (!hasNext) patch.finished = true;
    }

    this.set(patch);
  }

  // ---- 丧尸袭击 ----
  zombieAttack(): void {
    const s = this.state;
    if (s.phase !== 'driving') return;
    // 丧尸拍打车门：随机损失一项资源
    const roll = Math.random();
    let food = s.food;
    let stamina = s.stamina;
    let morale = s.morale;
    if (roll < 0.4) stamina -= 2;
    else if (roll < 0.7) food -= 1;
    else morale -= 1;
    const r = this.clamp(food, stamina, morale, s.fuel);
    this.set({ ...r });
  }

  // ---- 房车布局 ----
  canPlace(facilityId: string, x: number, y: number): boolean {
    const f = DataLoader.getFacility(facilityId);
    if (!f) return false;
    const cfg = DataLoader.getRvConfig();
    if (x < 0 || y < 0 || x + f.w > cfg.gridWidth || y + f.h > cfg.gridHeight) return false;
    for (const p of this.state.rvLayout) {
      const pf = DataLoader.getFacility(p.facilityId);
      if (!pf) continue;
      const overlap = x < p.x + pf.w && x + f.w > p.x && y < p.y + pf.h && y + f.h > p.y;
      if (overlap) return false;
    }
    return true;
  }

  placeFacility(facilityId: string, x: number, y: number): boolean {
    if (!this.canPlace(facilityId, x, y)) return false;
    this.set({ rvLayout: [...this.state.rvLayout, { facilityId, x, y }] });
    return true;
  }

  removeFacilityAt(x: number, y: number): void {
    const next = this.state.rvLayout.filter((p) => {
      const f = DataLoader.getFacility(p.facilityId);
      if (!f) return true;
      return !(x >= p.x && x < p.x + f.w && y >= p.y && y < p.y + f.h);
    });
    if (next.length !== this.state.rvLayout.length) this.set({ rvLayout: next });
  }

  // ---- 重置 ----
  reset(): void {
    SaveManager.clear();
    this.state = {
      ...INITIAL,
      team: [],
      visited: ['start'],
      rvLayout: [...DataLoader.getRvConfig().initialLayout],
    };
    this.emit();
  }
}

export const Game = new GameClass();
