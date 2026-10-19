import chapter1 from '../../data/chapter1.json';
import survivors from '../../data/survivors.json';
import professions from '../../data/professions.json';
import rv from '../../data/rv.json';

export interface MapNode {
  id: string;
  name: string;
  x: number;
  y: number;
  eventId?: string;
}

export interface EventEffects {
  food?: number;
  stamina?: number;
  morale?: number;
  fuel?: number;
  /** 维修套件增减 */
  repairKit?: number;
  /** 车辆耐久增减 */
  durability?: number;
  /** 游戏内小时增减（休息/绕路） */
  hour?: number;
}

export interface EventChoice {
  text: string;
  effects?: EventEffects;
  recruit?: string;
  /** 直接修复耐久（如拆铁皮修车） */
  repair?: number;
}

export interface GameEvent {
  id: string;
  title: string;
  text: string;
  image?: string;
  character?: string;
  choices: EventChoice[];
}

export interface Survivor {
  id: string;
  name: string;
  title: string;
  desc: string;
  skill: string;
  atk: number;
  med: number;
  /** 是否会开车：会开车的队友入队后可替玩家驾驶 */
  driver?: boolean;
  avatar?: string;
}

export interface Profession {
  id: string;
  name: string;
  desc: string;
  bonus: { food?: number; stamina?: number; morale?: number };
}

export interface Facility {
  id: string;
  name: string;
  desc: string;
  w: number;
  h: number;
  effect: { staminaMax?: number; foodMax?: number; staminaPerMove?: number };
}

export interface Edge {
  from: string;
  to: string;
  km: number;
}

interface ChapterData {
  id: string;
  name: string;
  nodes: MapNode[];
  fuelPerKm: number;
  edges: Edge[];
  events: Record<string, GameEvent>;
}

interface RvConfig {
  gridWidth: number;
  gridHeight: number;
  facilities: Record<string, Facility>;
  initialLayout: { facilityId: string; x: number; y: number }[];
}

export class DataLoader {
  private static chapter: ChapterData = chapter1 as ChapterData;
  private static survivorMap: Record<string, Survivor> = survivors as Record<string, Survivor>;
  private static professionMap: Record<string, Profession> = professions as Record<string, Profession>;
  private static rv: RvConfig = rv as RvConfig;

  static getChapter(): ChapterData {
    return this.chapter;
  }

  static getEvent(id: string): GameEvent | null {
    return this.chapter.events[id] ?? null;
  }

  static getSurvivor(id: string): Survivor | null {
    return this.survivorMap[id] ?? null;
  }

  static getProfessions(): Profession[] {
    return Object.values(this.professionMap);
  }

  static getProfession(id: string): Profession | null {
    return this.professionMap[id] ?? null;
  }

  static getRvConfig(): RvConfig {
    return this.rv;
  }

  static getFacility(id: string): Facility | null {
    return this.rv.facilities[id] ?? null;
  }

  static getNode(id: string): MapNode | null {
    return this.chapter.nodes.find((n) => n.id === id) ?? null;
  }

  static getFuelPerKm(): number {
    return this.chapter.fuelPerKm;
  }

  static getOutgoing(id: string): Edge[] {
    return this.chapter.edges.filter((e) => e.from === id);
  }

  static getEdge(from: string, to: string): Edge | null {
    return this.chapter.edges.find((e) => e.from === from && e.to === to) ?? null;
  }
}
