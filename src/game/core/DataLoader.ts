import chapter1 from '../../data/chapter1.json';
import survivors from '../../data/survivors.json';

export interface MapNode {
  id: string;
  name: string;
  x: number;
  y: number;
  eventId?: string;
}

export interface EventChoice {
  text: string;
  effects?: { food?: number; stamina?: number; morale?: number };
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

interface ChapterData {
  id: string;
  name: string;
  nodes: MapNode[];
  edges: string[][];
  events: Record<string, GameEvent>;
}

export class DataLoader {
  private static chapter: ChapterData = chapter1 as ChapterData;
  private static survivorMap: Record<string, Survivor> = survivors as Record<string, Survivor>;

  static getChapter(): ChapterData {
    return this.chapter;
  }

  static getEvent(id: string): GameEvent | null {
    return this.chapter.events[id] ?? null;
  }

  static getSurvivor(id: string): Survivor | null {
    return this.survivorMap[id] ?? null;
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
