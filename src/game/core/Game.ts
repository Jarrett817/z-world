import { DataLoader, GameEvent, Survivor } from './DataLoader';
import { SaveManager } from './SaveManager';

export interface GameState {
  currentNode: string;
  visited: string[];
  food: number;
  stamina: number;
  morale: number;
  team: Survivor[];
  currentEvent: GameEvent | null;
  finished: boolean;
}

type Listener = () => void;

const INITIAL: GameState = {
  currentNode: 'start',
  visited: ['start'],
  food: 10,
  stamina: 10,
  morale: 5,
  team: [],
  currentEvent: null,
  finished: false,
};

class GameClass {
  private state: GameState;
  private listeners = new Set<Listener>();

  constructor() {
    const saved = SaveManager.load<GameState>();
    this.state = saved ?? { ...INITIAL };
  }

  // ---- 订阅（供 React useSyncExternalStore） ----
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

  // ---- 地图逻辑 ----
  getReachable(): string[] {
    if (this.state.finished || this.state.currentEvent) return [];
    return DataLoader.getNeighbors(this.state.currentNode).filter(
      (id) => !this.state.visited.includes(id),
    );
  }

  moveTo(nodeId: string): boolean {
    if (!this.getReachable().includes(nodeId)) return false;
    const node = DataLoader.getNode(nodeId);
    if (!node) return false;

    const patch: Partial<GameState> = {
      currentNode: nodeId,
      visited: [...this.state.visited, nodeId],
      stamina: Math.max(0, this.state.stamina - 1),
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

    if (choice.effects) {
      const e = choice.effects;
      patch.food = Math.max(0, this.state.food + (e.food ?? 0));
      patch.stamina = Math.max(0, this.state.stamina + (e.stamina ?? 0));
      patch.morale = Math.max(0, this.state.morale + (e.morale ?? 0));
    }

    if (choice.recruit) {
      const s = DataLoader.getSurvivor(choice.recruit);
      if (s && !this.state.team.some((m) => m.id === s.id)) {
        patch.team = [...this.state.team, s];
      }
    }

    this.set(patch);
  }

  // ---- 重置 ----
  reset(): void {
    SaveManager.clear();
    this.state = { ...INITIAL, team: [], visited: ['start'] };
    this.emit();
  }
}

export const Game = new GameClass();
