import { DataLoader, GameEvent, Survivor } from './DataLoader';
import { SaveManager } from './SaveManager';

export interface PlacedFacility {
  facilityId: string;
  x: number;
  y: number;
}

export type Phase = 'profession' | 'event' | 'route' | 'driving' | 'dead' | 'finished';
export type Weather = 'clear' | 'rain' | 'fog' | 'snow';

export interface Travel {
  from: string;
  to: string;
  km: number;
  done: number;
}

/** 路边遭遇类型：补给点 / 废弃车堆(可维修) / 求助幸存者 / 堵路 */
export type RoadKind = 'supply' | 'wreck' | 'survivor' | 'block';

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
  /** 车辆耐久 0-100，撞丧尸/路障扣减，降到 0 车毁人亡重开 */
  durability: number;
  /** 生存天数（1 起） */
  day: number;
  /** 游戏内小时 0-24 */
  hour: number;
  /** 维修套件数量 */
  repairKit: number;
  /** 停车状态（驾驶中按 P 切换，停车后可经营/休息） */
  parked: boolean;
}

type Listener = () => void;

const BASE_CAPS = { food: 20, stamina: 10, fuel: 12 };

/** 时钟速率：1 现实秒 = 3 游戏分钟（0.05 小时），约 8 分钟现实 = 1 游戏日 */
const CLOCK_RATE = 0.05;

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
  durability: 100,
  day: 1,
  hour: 8,
  repairKit: 2,
  parked: false,
};

class GameClass {
  private state: GameState;
  private listeners = new Set<Listener>();

  constructor() {
    const saved = SaveManager.load<GameState>();
    if (saved) {
      // 旧存档兼容：补充缺失字段
      this.state = {
        ...INITIAL,
        ...saved,
        weather: saved.weather ?? 'clear',
        durability: saved.durability ?? 100,
      };
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

    const e = choice.effects ?? {};
    // 时间流逝（休息/绕路类选项）
    let hour = this.state.hour + (e.hour ?? 0);
    let day = this.state.day;
    while (hour >= 24) {
      hour -= 24;
      day += 1;
    }

    const patch: Partial<GameState> = {
      currentEvent: null,
      ...this.clamp(
        this.state.food + (e.food ?? 0),
        this.state.stamina + (e.stamina ?? 0),
        this.state.morale + (e.morale ?? 0),
        this.state.fuel + (e.fuel ?? 0),
      ),
      repairKit: Math.max(0, this.state.repairKit + (e.repairKit ?? 0)),
      durability: Math.min(100, Math.max(0, this.state.durability + (e.durability ?? 0) + (choice.repair ?? 0))),
      hour,
      day,
    };

    if (choice.recruit) {
      const s = DataLoader.getSurvivor(choice.recruit);
      if (s && !this.state.team.some((m) => m.id === s.id)) {
        patch.team = [...this.state.team, s];
      }
    }

    // 路边遭遇：处理完继续赶路（travel 保持）
    if (ev.id.startsWith('road_')) {
      patch.phase = 'driving';
      patch.parked = false;
      this.set(patch);
      return;
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

  // ---- 车辆耐久 ----
  /** 撞丧尸/路障扣耐久；耐久归零车毁人亡（重开） */
  damageVehicle(amount: number): void {
    const s = this.state;
    if (s.phase !== 'driving') return;
    const durability = Math.max(0, s.durability - amount);
    if (durability <= 0) {
      this.set({ durability: 0, phase: 'dead' });
      return;
    }
    this.set({ durability });
  }

  /** 维修恢复耐久（车内经营/营地/事件调用） */
  repairVehicle(amount: number): void {
    const s = this.state;
    if (s.phase !== 'driving' && s.phase !== 'event' && s.phase !== 'route') return;
    const durability = Math.min(100, s.durability + amount);
    this.set({ durability });
  }

  // ---- 丧尸撞击 ----
  /** 撞上丧尸：主扣车辆耐久 + 小概率拍窗损失体力；伤害随天数增强（由 Drive3D 传入） */
  zombieHit(amount = 3): void {
    const s = this.state;
    if (s.phase !== 'driving') return;
    this.damageVehicle(amount);
    if (Math.random() < 0.2) {
      const stamina = Math.max(0, s.stamina - 1);
      this.set({ stamina });
    }
  }

  // ---- 时钟 / 生存天数 ----
  /** 每帧由 Drive3D 调用推进游戏时间；现实 1 秒 = 3 游戏分钟 */
  advanceClock(realDtSec: number): void {
    const s = this.state;
    if (s.phase !== 'driving' && s.phase !== 'event') return;
    let hour = s.hour + realDtSec * CLOCK_RATE;
    let day = s.day;
    if (hour >= 24) {
      hour -= 24;
      day += 1;
    }
    this.state = { ...this.state, hour, day };
    this.emit();
  }

  /** 丧尸强度等级：随生存天数线性增长（day1=0 级） */
  getZombieLevel(): number {
    return Math.max(0, this.state.day - 1);
  }

  // ---- 停车与车内经营 ----
  /** 驾驶中按 P 切换停车/行驶；停车后速度归零、可经营 */
  togglePark(): void {
    const s = this.state;
    if (s.phase !== 'driving' || s.currentEvent) return;
    this.set({ parked: !s.parked });
  }

  /** 做饭：消耗 2 食物 → 体力+3 士气+1 */
  cookMeal(): boolean {
    const s = this.state;
    if (s.food < 2) return false;
    const r = this.clamp(s.food - 2, s.stamina + 3, s.morale + 1, s.fuel);
    this.set({ ...r });
    return true;
  }

  /** 休息：体力+4，耗时 6 小时 */
  restInRv(): void {
    let hour = this.state.hour + 6;
    let day = this.state.day;
    while (hour >= 24) {
      hour -= 24;
      day += 1;
    }
    const r = this.clamp(this.state.food, this.state.stamina + 4, this.state.morale, this.state.fuel);
    this.set({ ...r, hour, day });
  }

  /** 维修：耗 1 维修套件 → 耐久+25 */
  repairWithKit(): boolean {
    const s = this.state;
    if (s.repairKit < 1 || s.durability >= 100) return false;
    this.set({ repairKit: s.repairKit - 1, durability: Math.min(100, s.durability + 25) });
    return true;
  }

  // ---- 路边遭遇 ----
  /** 接近遭遇点时由 Drive3D 调用，弹出对应事件对话框（复用事件系统） */
  openRoadEvent(kind: RoadKind): boolean {
    const s = this.state;
    if (s.phase !== 'driving') return false;
    const ev = this.buildRoadEvent(kind);
    if (!ev) return false;
    this.set({ currentEvent: ev, phase: 'event' });
    return true;
  }

  private buildRoadEvent(kind: RoadKind): GameEvent | null {
    switch (kind) {
      case 'supply':
        return {
          id: 'road_supply',
          title: '路边补给点',
          text: '一辆翻倒的补给车横在路边，物资散落一地，四周安静得可怕。',
          choices: [
            { text: '停车搜刮（食物+3，燃料+2）', effects: { food: 3, fuel: 2 } },
            { text: '停车搜刮（维修套件+1，体力-1）', effects: { repairKit: 1, stamina: -1 } },
            { text: '可疑，继续赶路' },
          ],
        };
      case 'wreck':
        return {
          id: 'road_wreck',
          title: '废弃车堆',
          text: '几辆锈透的废车堆在路边，铁皮还能拆下来补补车身。',
          choices: [
            { text: '拆铁皮修车（耐久+25，耗1维修套件）', effects: { repairKit: -1 }, repair: 25 },
            { text: '搜刮车内物资（食物+2，燃料+1）', effects: { food: 2, fuel: 1 } },
            { text: '继续赶路' },
          ],
        };
      case 'survivor': {
        const pool = ['lin_wan', 'chen_mo', 'ivory'].filter((id) => !this.state.team.some((m) => m.id === id));
        if (pool.length === 0) return null;
        const pick = pool[Math.floor(Math.random() * pool.length)];
        const s = DataLoader.getSurvivor(pick);
        return {
          id: 'road_survivor',
          title: '路边的求救',
          text: `远处有人挥手——${s?.desc ?? ''}`,
          choices: [
            { text: `停车搭救（招募「${s?.name ?? '幸存者'}」，体力-1，士气+2）`, recruit: pick, effects: { stamina: -1, morale: 2 } },
            { text: '危险，继续赶路' },
          ],
        };
      }
      case 'block':
        return {
          id: 'road_block',
          title: '道路被堵',
          text: '废弃车辆横在路中央，绕行要费时间，硬闯要伤车。',
          choices: [
            { text: '硬闯过去（耐久-15）', effects: { durability: -15 } },
            { text: '绕路（燃料-1，耗时2小时）', effects: { fuel: -1, hour: 2 } },
          ],
        };
    }
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
