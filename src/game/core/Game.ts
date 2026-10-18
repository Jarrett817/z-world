import { DataLoader, GameEvent, Survivor } from './DataLoader';
import { SaveManager } from './SaveManager';

export interface PlacedFacility {
  facilityId: string;
  x: number;
  y: number;
}

export interface GameState {
  profession: string | null;
  currentNode: string;
  visited: string[];
  food: number;
  stamina: number;
  morale: number;
  fuel: number;
  team: Survivor[];
  currentEvent: GameEvent | null;
  finished: boolean;
  rvLayout: PlacedFacility[];
}

type Listener = () => void;

const BASE_CAPS = { food: 20, stamina: 10, fuel: 12 };

const INITIAL: GameState = {
  profession: null,
  currentNode: 'start',
  visited: ['start'],
  food: 8,
  stamina: 8,
  morale: 5,
  fuel: 8,
  team: [],
  currentEvent: null,
  finished: false,
  rvLayout: [...DataLoader.getRvConfig().initialLayout],
};

class GameClass {
  private state: GameState;
  private listeners = new Set<Listener>();

  constructor() {
    const saved = SaveManager.load<GameState>();
    this.state = saved ?? { ...INITIAL };
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
    this.set({ profession: id, ...r, currentEvent: ev });
  }

  // ---- 地图逻辑 ----
  getReachable(): string[] {
    if (this.state.finished || this.state.currentEvent || !this.state.profession) return [];
    if (this.state.fuel <= 0) return [];
    return DataLoader.getNeighbors(this.state.currentNode).filter(
      (id) => !this.state.visited.includes(id),
    );
  }

  moveTo(nodeId: string): boolean {
    if (!this.getReachable().includes(nodeId)) return false;
    const node = DataLoader.getNode(nodeId);
    if (!node) return false;

    // 医疗角：每次移动恢复体力
    let staminaRegen = 0;
    for (const p of this.state.rvLayout) {
      const f = DataLoader.getFacility(p.facilityId);
      staminaRegen += f?.effect.staminaPerMove ?? 0;
    }

    const r = this.clamp(
      this.state.food,
      this.state.stamina + staminaRegen,
      this.state.morale,
      this.state.fuel - 1,
    );

    const patch: Partial<GameState> = {
      currentNode: nodeId,
      visited: [...this.state.visited, nodeId],
      ...r,
    };

    if (nodeId === 'end') patch.finished = true;
    else if (node.eventId) {
      const ev = DataLoader.getEvent(node.eventId);
      if (ev) patch.currentEvent = ev;
    }

    this.set(patch);
    return true;
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

    this.set(patch);
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
