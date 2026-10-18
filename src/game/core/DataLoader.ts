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
}

export interface EventChoice {
  text: string;
  effects?: EventEffects;
  recruit?: string;
}

export interface GameEvent {
  id: string;
  title: string;
  text: string;
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

interface ChapterData {
  id: string;
  name: string;
  nodes: MapNode[];
  edges: string[][];
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

  static getNeighbors(id: string): string[] {
    const out: string[] = [];
    for (const [a, b] of this.chapter.edges) {
      if (a === id) out.push(b);
      else if (b === id) out.push(a);
    }
    return out;
  }
}
