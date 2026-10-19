import * as THREE from 'three';
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js';
import { Game, RoadKind, Weather } from '../core/Game';

const MAX_SPEED = 80; // km/h
const ACCEL = 40; // km/h 每秒
const BRAKE = 90;
const DRAG = 8;
const KMH_TO_UNITS = 0.5; // 驾驶尺度：km/h → 世界单位/秒
const GROUND_Y = -1.56; // 地面高度（glTF Y-up，车底贴地）
const Z_SPAWN = -260; // 世界对象生成/循环重置深度
const Z_LOOP = 40; // 对象越过此 Z 后循环回前方
const ROAD_HALF = 6.5; // 路面半宽

type CamMode = 'chase' | 'cockpit' | 'rooftop';

const CAM_HINT: Record<CamMode, string> = {
  chase: '追尾视角',
  cockpit: '舱内视角',
  rooftop: '车顶视角',
};

interface SideObj {
  group: THREE.Group;
  z: number;
  speed: number; // 仅丧尸使用（相对车的前进速度，m/s）
  kind: 'zombie' | 'prop';
  active: boolean;
  mixer?: THREE.AnimationMixer; // 丧尸动画
  hitDmg?: number; // 丧尸撞击伤害（随天数增强）
}

interface BlockObj {
  group: THREE.Object3D;
  z: number;
  x: number;
  kind: 'soft' | 'hard';
  active: boolean;
  hit: boolean; // 已撞击过（防重复扣耐久）
  flying: boolean; // 软路障被撞飞动画
  flyT: number;
}

/** 路边遭遇点：补给点 / 废车堆 / 求助者 / 堵路 */
interface RoadEventObj {
  group: THREE.Group;
  z: number;
  x: number;
  kind: RoadKind;
  active: boolean;
  done: boolean; // 已触发过（防重复触发）
  pulse: number; // 指示光脉冲相位
}

const WEATHER_LABEL: Record<Weather, string> = { clear: '晴', rain: '雨', fog: '雾', snow: '雪' };

function rng(a: number, b: number): number {
  return a + Math.random() * (b - a);
}

export class Drive3D {
  private container: HTMLElement;
  private renderer: THREE.WebGLRenderer;
  private scene = new THREE.Scene();
  private clock = new THREE.Clock();
  private raf = 0;
  private disposed = false;

  // 相机
  private camChase = new THREE.PerspectiveCamera(55, 1, 0.1, 600);
  private camCockpit = new THREE.PerspectiveCamera(72, 1, 0.1, 600);
  private camRooftop = new THREE.PerspectiveCamera(65, 1, 0.1, 600);
  private camInterior = new THREE.PerspectiveCamera(60, 1, 0.1, 100); // 车内画中画
  private camMode: CamMode = 'chase';

  // 主循环/光照
  private dayFactor = 0.5;
  private pendingRoad: RoadEventObj | null = null;

  // 房车
  private rv: THREE.Group | null = null;

  // 驾驶状态
  private speed = 0;
  private prevSpeed = 0;
  private boost = 0; // 推背感：+加速前倾 / -刹车前顶，快起慢落
  private gasHeld = false;
  private brakeHeld = false;
  private steerLeft = false;
  private steerRight = false;
  private offsetX = 0; // 车辆横向偏移（躲避路障）
  private spawnTimer = 0;
  private blockTimer = 0;

  // 撞击反馈
  private shakeTime = 0;
  private shakeIntensity = 0;

  // 世界对象
  private props: SideObj[] = [];
  private blocks: BlockObj[] = [];
  private roadEvents: RoadEventObj[] = [];
  private dashes: THREE.Mesh[] = [];

  // 模型源
  private zombieSource: THREE.Group | null = null;
  private zombieClips: THREE.AnimationClip[] = [];
  private softSources: THREE.Object3D[] = [];
  private hardSources: THREE.Object3D[] = [];
  /** 下载的场景模型源（枯树等） */
  private sceneSources: THREE.Object3D[] = [];
  /** 城市废墟环境（体积大，只作远景天际线） */
  private skylineSource: THREE.Group | null = null;
  /** container 包中的油桶/木箱（路边补给点造型） */
  private supplySources: THREE.Object3D[] = [];

  // 光照（昼夜）
  private sun!: THREE.DirectionalLight;
  private hemi!: THREE.HemisphereLight;
  private headlight!: THREE.SpotLight;

  // 遭遇/生成节奏
  private roadTimer = 0;
  private nightLamps: THREE.Mesh[] = []; // 路灯灯头（夜晚增强）

  // 天气
  private rain!: THREE.Points;
  private snow!: THREE.Points;
  private weather: Weather = 'clear';

  // HUD（Three 组件内部 DOM，React 只管顶层 UI）
  private telemetryEl: HTMLDivElement;
  private hintEl: HTMLDivElement;
  private pipEl: HTMLDivElement; // 车内画中画边框

  constructor(container: HTMLElement) {
    this.container = container;

    const w = container.clientWidth || 1280;
    const h = container.clientHeight || 720;
    this.renderer = new THREE.WebGLRenderer({ antialias: true });
    this.renderer.setSize(w, h);
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    this.renderer.toneMapping = THREE.ACESFilmicToneMapping;
    this.renderer.toneMappingExposure = 1.05;
    container.appendChild(this.renderer.domElement);
    this.renderer.domElement.style.width = '100%';
    this.renderer.domElement.style.height = '100%';

    this.scene.background = new THREE.Color(0x1c1a18);
    this.scene.fog = new THREE.Fog(0x24211e, 40, 260);

    // 光照：主光暖白（篝火橙系）+ 环境冷灰青；昼夜循环中动态调整
    this.sun = new THREE.DirectionalLight(0xd9c9a8, 2.2);
    this.sun.position.set(-20, 40, -30);
    this.scene.add(this.sun);
    this.hemi = new THREE.HemisphereLight(0x8a9aa8, 0x2a2320, 0.55);
    this.scene.add(this.hemi);
    // 车头灯（夜晚开启）：跟随车头朝前方照射
    this.headlight = new THREE.SpotLight(0xffe6b8, 0, 120, Math.PI / 5, 0.45, 0.9);
    this.headlight.position.set(0, 2.4, -6);
    this.headlight.target.position.set(0, 1.5, -30);
    this.scene.add(this.headlight);
    this.scene.add(this.headlight.target);

    // HUD
    this.telemetryEl = document.createElement('div');
    this.telemetryEl.style.cssText =
      'position:absolute;bottom:52px;left:50%;transform:translateX(-50%);font:bold 24px/1.2 monospace;color:#e8ded2;text-align:center;text-shadow:0 2px 6px rgba(0,0,0,.8);pointer-events:none;z-index:5';
    container.appendChild(this.telemetryEl);
    this.hintEl = document.createElement('div');
    this.hintEl.style.cssText =
      'position:absolute;bottom:18px;left:50%;transform:translateX(-50%);font:13px/1.4 monospace;color:#d4a05a;text-shadow:0 2px 6px rgba(0,0,0,.8);pointer-events:none;z-index:5;white-space:nowrap';
    container.appendChild(this.hintEl);
    this.pipEl = document.createElement('div');
    this.pipEl.style.cssText =
      'position:absolute;top:78px;left:14px;width:230px;height:161px;border:2px solid rgba(232,134,46,.6);border-radius:8px;pointer-events:none;z-index:4;display:none;box-shadow:0 0 12px rgba(0,0,0,.5)';
    container.appendChild(this.pipEl);

    this.buildRoad();
    this.buildSideProps();
    this.buildWeather();
    this.bindInput();
  }

  async start(): Promise<void> {
    await Promise.all([this.loadRV(), this.loadProps(), this.loadSceneModels()]);
    if (this.disposed) return;
    this.loop();
  }

  // ---- 模型加载 ----
  private async loadRV(): Promise<void> {
    const loader = new GLTFLoader();
    const gltf = await loader.loadAsync('/assets/rv/gs_001.glb');
    const rv = gltf.scene;
    // glTF Y-up：车长轴在 Y、车顶在 +Y。绕 X -90° 使车头朝 -Z 前进、车顶仍朝上
    rv.rotation.x = -Math.PI / 2;
    rv.position.y = GROUND_Y;
    rv.traverse((o) => {
      if ((o as THREE.Mesh).isMesh) {
        o.castShadow = false;
        o.receiveShadow = false;
      }
    });
    this.scene.add(rv);
    this.rv = rv;
  }

  // ---- 道具/丧尸模型加载 ----
  private async loadProps(): Promise<void> {
    const loader = new GLTFLoader();
    // 丧尸动画包
    const z = await loader.loadAsync('/assets/props/zmb.glb');
    const zscene = z.scene;
    zscene.traverse((o) => {
      if ((o as THREE.Mesh).isMesh) {
        o.castShadow = false;
        o.receiveShadow = false;
      }
    });
    this.zombieSource = zscene;
    this.zombieClips = z.animations;
    // 丧尸材质微绿自发光：暗夜中更显眼、更有丧尸感
    zscene.traverse((o) => {
      const mesh = o as THREE.Mesh;
      if (!mesh.isMesh) return;
      const mats = Array.isArray(mesh.material) ? mesh.material : [mesh.material];
      for (const m of mats) {
        const mat = m as THREE.MeshStandardMaterial;
        if (mat && 'emissive' in mat) {
          mat.emissive = new THREE.Color(0x1f4a2a);
          mat.emissiveIntensity = 0.35;
        }
      }
    });

    // 软路障（可撞飞）：路障/锥桶包
    const b = await loader.loadAsync('/assets/props/barriers.glb');
    b.scene.traverse((o) => {
      if ((o as THREE.Mesh).isMesh && o.visible) this.softSources.push(o);
    });

    // 硬路障：军用路障 + 废弃卡车 + 废弃轿车
    const bg = await loader.loadAsync('/assets/props/barricade.glb');
    bg.scene.traverse((o) => {
      if ((o as THREE.Mesh).isMesh && o.visible) this.hardSources.push(o);
    });
    const t = await loader.loadAsync('/assets/props/wtruck.glb');
    t.scene.traverse((o) => {
      if ((o as THREE.Mesh).isMesh && o.visible) this.hardSources.push(o);
    });
    const c = await loader.loadAsync('/assets/props/wcar.glb');
    c.scene.traverse((o) => {
      if ((o as THREE.Mesh).isMesh && o.visible) this.hardSources.push(o);
    });
  }

  /** 加载下载的场景模型（城市废墟作远景/工业杂物作补给点/枯树作路边）；文件未就绪时静默跳过，程序化元素兜底 */
  private async loadSceneModels(): Promise<void> {
    const loader = new GLTFLoader();
    const paths = [
      '/assets/props/scene_models/building/scene.gltf',
      '/assets/props/scene_models/container/scene.gltf',
      '/assets/props/scene_models/tree/scene.gltf',
    ];
    for (const p of paths) {
      try {
        const gltf = await loader.loadAsync(p);
        const isBuilding = p.includes('/building/');
        gltf.scene.traverse((o) => {
          if ((o as THREE.Mesh).isMesh) {
            o.castShadow = false;
            o.receiveShadow = false;
            const m = o as THREE.Mesh;
            const mats = Array.isArray(m.material) ? m.material : [m.material];
            for (const mat of mats) {
              const mm = mat as THREE.MeshStandardMaterial;
              if (mm && 'roughness' in mm) mm.roughness = Math.max(mm.roughness, 0.7);
            }
            // container 包：油桶/木箱/金属箱/麻袋 → 补给点造型源
            const name = (o.name ?? '').toLowerCase();
            if (!isBuilding && /barrel|crate|sack/.test(name) && o.visible) {
              this.supplySources.push(o);
            }
          }
        });
        if (isBuilding) {
          this.skylineSource = gltf.scene;
        } else {
          this.sceneSources.push(gltf.scene);
        }      } catch {
        // 模型尚未就绪：跳过
      }
    }
  }

  // ---- 公路骨架（静态） ----
  private buildRoad(): void {
    // 大地
    const ground = new THREE.Mesh(
      new THREE.PlaneGeometry(400, 900),
      new THREE.MeshStandardMaterial({ color: 0x191410, roughness: 1 }),
    );
    ground.rotation.x = -Math.PI / 2;
    ground.position.set(0, GROUND_Y - 0.02, -200);
    this.scene.add(ground);

    // 路面
    const road = new THREE.Mesh(
      new THREE.PlaneGeometry(ROAD_HALF * 2, 900),
      new THREE.MeshStandardMaterial({ color: 0x26201a, roughness: 0.95 }),
    );
    road.rotation.x = -Math.PI / 2;
    road.position.set(0, GROUND_Y + 0.01, -200);
    this.scene.add(road);

    // 路肩白线 x2
    for (const sx of [-ROAD_HALF + 0.25, ROAD_HALF - 0.25]) {
      const line = new THREE.Mesh(
        new THREE.PlaneGeometry(0.14, 900),
        new THREE.MeshStandardMaterial({ color: 0x8a7d6d, roughness: 0.9 }),
      );
      line.rotation.x = -Math.PI / 2;
      line.position.set(sx, GROUND_Y + 0.02, -200);
      this.scene.add(line);
    }

    // 中央虚线（可滚动单元）
    const dashMat = new THREE.MeshStandardMaterial({ color: 0x4a3f35, roughness: 0.9 });
    for (let z = -260; z < Z_LOOP; z += 12) {
      const dash = new THREE.Mesh(new THREE.BoxGeometry(0.5, 0.06, 3.2), dashMat);
      dash.position.set(0, GROUND_Y + 0.03, z);
      this.scene.add(dash);
      this.dashes.push(dash);
    }

    this.buildSkyline();
  }

  /** 远景天际线：城市废墟剪影挂在路两侧远处，随循环滚动 */
  private buildSkyline(): void {
    if (!this.skylineSource) return;
    for (let i = 0; i < 4; i++) {
      const side = i % 2 === 0 ? 1 : -1;
      const x = side * rng(48, 70);
      const z = -260 + i * 92;
      const m = this.skylineSource.clone();
      m.scale.setScalar(rng(0.35, 0.55));
      m.rotation.y = rng(0, Math.PI * 2);
      m.position.set(x, GROUND_Y + 9, z);
      this.scene.add(m);
      this.props.push({ group: m, z, speed: 0, kind: 'prop', active: true });
    }
  }

  // ---- 路边元素 + 丧尸池 ----
  private buildSideProps(): void {
    for (let i = 0; i < 26; i++) {
      const side = Math.random() > 0.5 ? 1 : -1;
      const x = side * rng(ROAD_HALF + 2, ROAD_HALF + 34);
      const z = rng(Z_SPAWN, Z_LOOP - 10);
      const g = this.makeProp(x);
      g.position.set(x, GROUND_Y, z);
      this.scene.add(g);
      this.props.push({ group: g, z, speed: 0, kind: 'prop', active: true });
    }
  }

  private makeProp(x: number): THREE.Group {
    const g = new THREE.Group();
    // 优先复用下载的场景模型（废弃建筑/集装箱/枯树等）
    if (this.sceneSources.length > 0 && Math.random() < 0.55) {
      const src = this.sceneSources[Math.floor(Math.random() * this.sceneSources.length)];
      const m = src.clone();
      m.scale.setScalar(rng(0.7, 1.5));
      m.rotation.y = rng(0, Math.PI * 2);
      g.add(m);
      return g;
    }
    const roll = Math.random();
    if (roll < 0.3) {
      // 枯树：柱 + 分枝
      const trunk = new THREE.Mesh(
        new THREE.CylinderGeometry(0.18, 0.3, 3 + Math.random() * 2, 5),
        new THREE.MeshStandardMaterial({ color: 0x2a2320, roughness: 1 }),
      );
      trunk.position.y = 1.5;
      g.add(trunk);
      const top = new THREE.Mesh(
        new THREE.IcosahedronGeometry(0.7, 1),
        new THREE.MeshStandardMaterial({ color: 0x3d332b, roughness: 1 }),
      );
      top.position.y = 3.4;
      top.scale.set(1, 0.8, 1);
      g.add(top);
    } else if (roll < 0.55) {
      // 废墟：碎 box 堆
      const n = 2 + Math.floor(Math.random() * 3);
      for (let i = 0; i < n; i++) {
        const b = new THREE.Mesh(
          new THREE.BoxGeometry(rng(1, 3), rng(0.6, 1.8), rng(1, 3)),
          new THREE.MeshStandardMaterial({ color: Math.random() > 0.5 ? 0x26201a : 0x3a2f26, roughness: 1 }),
        );
        b.position.set(rng(-1.5, 1.5), rng(0.3, 1.2), rng(-1.5, 1.5));
        b.rotation.y = rng(0, Math.PI);
        g.add(b);
      }
    } else if (roll < 0.75) {
      // 路灯：柱 + 灯头（自发光，夜晚增强）
      const pole = new THREE.Mesh(
        new THREE.CylinderGeometry(0.08, 0.08, 4.2, 6),
        new THREE.MeshStandardMaterial({ color: 0x1f1c1a, roughness: 0.8 }),
      );
      pole.position.y = 2.1;
      g.add(pole);
      const arm = new THREE.Mesh(
        new THREE.BoxGeometry(1.6, 0.08, 0.08),
        new THREE.MeshStandardMaterial({ color: 0x1f1c1a, roughness: 0.8 }),
      );
      arm.position.set(Math.sign(x) * -0.75, 4.2, 0);
      g.add(arm);
      const lamp = new THREE.Mesh(
        new THREE.SphereGeometry(0.16, 8, 8),
        new THREE.MeshStandardMaterial({ color: 0xe8a04c, emissive: 0xd98e2e, emissiveIntensity: 0.6 }),
      );
      lamp.position.set(Math.sign(x) * -1.5, 4.2, 0);
      g.add(lamp);
      this.nightLamps.push(lamp);
    } else if (roll < 0.9) {
      // 广告牌：立柱 + 残旧灯箱面板
      const pole = new THREE.Mesh(
        new THREE.CylinderGeometry(0.09, 0.12, 3.2, 6),
        new THREE.MeshStandardMaterial({ color: 0x24201c, roughness: 0.9 }),
      );
      pole.position.y = 1.6;
      g.add(pole);
      const panel = new THREE.Mesh(
        new THREE.BoxGeometry(3, 1.9, 0.14),
        new THREE.MeshStandardMaterial({ color: 0x3a2f26, roughness: 1 }),
      );
      panel.position.y = 3.1;
      g.add(panel);
      const glow = new THREE.Mesh(
        new THREE.PlaneGeometry(2.5, 1.4),
        new THREE.MeshStandardMaterial({
          color: 0x8a6a3a,
          emissive: 0x7a4a24,
          emissiveIntensity: 0.5,
          roughness: 0.8,
        }),
      );
      glow.position.set(0, 3.1, Math.sign(x) * 0.08);
      glow.rotation.y = 0;
      g.add(glow);
    } else {
      // 集装箱：锈蚀箱体 + 顶部细节
      const box = new THREE.Mesh(
        new THREE.BoxGeometry(rng(3.5, 4.5), 2.2, 2),
        new THREE.MeshStandardMaterial({ color: Math.random() > 0.5 ? 0x5a4a2e : 0x4a5a6b, roughness: 1 }),
      );
      box.position.y = 1.1;
      g.add(box);
      const rib = new THREE.Mesh(
        new THREE.BoxGeometry(3.5, 0.12, 0.14),
        new THREE.MeshStandardMaterial({ color: 0x3a3026, roughness: 1 }),
      );
      rib.position.y = 0.35;
      g.add(rib);
    }
    return g;
  }

  private spawnZombie(): void {
    if (!this.zombieSource) return;
    // 丧尸随生存天数增强：更快、更大、撞得更疼
    const level = Game.getZombieLevel();
    const side = Math.random() > 0.5 ? 1 : -1;
    const x = side * (Math.random() * 3 + 2);
    const g = this.zombieSource.clone(true);
    g.position.set(x, GROUND_Y, Z_SPAWN);
    const roll = Math.random();
    g.rotation.y = roll > 0.5 ? Math.PI : 0; // 面朝车
    g.scale.setScalar((1.05 + Math.random() * 0.3) * (1 + level * 0.04));
    // 随机挑一个走/跑动画
    const mixer = new THREE.AnimationMixer(g);
    const clip =
      this.zombieClips.find((c) => /walk|run/i.test(c.name)) ?? this.zombieClips[0];
    if (clip) mixer.clipAction(clip).play();
    this.scene.add(g);
    this.props.push({
      group: g,
      z: Z_SPAWN,
      speed: (1.4 + Math.random() * 1.2) * (1 + level * 0.12),
      kind: 'zombie',
      active: true,
      mixer,
      hitDmg: 3 + level * 2,
    });
  }

  // ---- 路边遭遇 ----
  private spawnRoadEvent(): void {
    const kinds: RoadKind[] = ['supply', 'wreck', 'survivor', 'block'];
    const kind = kinds[Math.floor(Math.random() * kinds.length)];
    const x = rng(-4.2, 4.2);
    const g = this.buildRoadEventVisual(kind);
    g.position.set(x, GROUND_Y, Z_SPAWN);
    this.scene.add(g);
    this.roadEvents.push({ group: g, z: Z_SPAWN, x, kind, active: true, done: false, pulse: Math.random() * 10 });
  }

  private buildRoadEventVisual(kind: RoadKind): THREE.Group {
    const g = new THREE.Group();
    if (kind === 'supply') {
      if (this.supplySources.length > 0) {
        // 用 container 包里的油桶/木箱堆做真实补给点
        const n = 2 + Math.floor(Math.random() * Math.min(3, this.supplySources.length));
        for (let i = 0; i < n; i++) {
          const src = this.supplySources[Math.floor(Math.random() * this.supplySources.length)];
          const m = src.clone();
          m.scale.setScalar(rng(0.9, 1.3));
          m.rotation.y = rng(0, Math.PI * 2);
          m.position.set(rng(-0.9, 0.9), 0, rng(-0.9, 0.9));
          g.add(m);
        }
      } else {
        const box = new THREE.Mesh(
          new THREE.BoxGeometry(1.6, 1.1, 1.6),
          new THREE.MeshStandardMaterial({ color: 0x8a5a2a, roughness: 0.9 }),
        );
        box.position.y = 0.55;
        g.add(box);
        const lid = new THREE.Mesh(
          new THREE.BoxGeometry(1.7, 0.12, 1.7),
          new THREE.MeshStandardMaterial({ color: 0x4a3a2a, roughness: 0.9 }),
        );
        lid.position.y = 1.15;
        g.add(lid);
      }
    } else if (kind === 'wreck' || kind === 'block') {
      const body = new THREE.Mesh(
        new THREE.BoxGeometry(kind === 'block' ? 4.4 : 2.2, 0.85, kind === 'block' ? 2.0 : 4.2),
        new THREE.MeshStandardMaterial({ color: 0x3a3128, roughness: 1 }),
      );
      body.position.y = 0.55;
      body.rotation.y = kind === 'block' ? 0 : rng(0, Math.PI);
      g.add(body);
      for (let i = 0; i < 4; i++) {
        const w = new THREE.Mesh(
          new THREE.CylinderGeometry(0.36, 0.36, 0.3, 10),
          new THREE.MeshStandardMaterial({ color: 0x1f1c1a, roughness: 1 }),
        );
        w.rotation.x = Math.PI / 2;
        w.position.set((i % 2 === 0 ? 1 : -1) * (kind === 'block' ? 1.4 : 0.8), 0.36, i < 2 ? 0.9 : -0.9);
        g.add(w);
      }
    } else {
      // 求助者：人形剪影占位（后续接入人物 3D 模型替换）
      const body = new THREE.Mesh(
        new THREE.CapsuleGeometry(0.26, 0.7, 4, 8),
        new THREE.MeshStandardMaterial({ color: 0x4a3f35, roughness: 1 }),
      );
      body.position.y = 0.85;
      g.add(body);
      const head = new THREE.Mesh(
        new THREE.SphereGeometry(0.2, 10, 8),
        new THREE.MeshStandardMaterial({ color: 0x6b5848, roughness: 1 }),
      );
      head.position.y = 1.62;
      g.add(head);
    }
    // 底部光环 + 竖直光柱（脉冲指示）
    const glowMat = new THREE.MeshStandardMaterial({
      color: 0xffb45e,
      emissive: 0xff8a2e,
      emissiveIntensity: 1.6,
      transparent: true,
      opacity: 0.85,
    });
    const ring = new THREE.Mesh(new THREE.TorusGeometry(1.1, 0.06, 6, 24), glowMat);
    ring.rotation.x = -Math.PI / 2;
    ring.position.y = 0.08;
    g.add(ring);
    const beam = new THREE.Mesh(
      new THREE.CylinderGeometry(0.1, 0.1, 5, 6, 1, true),
      glowMat.clone(),
    );
    const beamMat = beam.material as THREE.MeshStandardMaterial;
    beamMat.opacity = 0.3;
    beamMat.depthWrite = false;
    beam.position.y = 2.6;
    g.add(beam);
    return g;
  }

  private roadHint(kind: RoadKind): string {
    switch (kind) {
      case 'supply':
        return '路边补给点！空格停车搜刮';
      case 'wreck':
        return '废弃车堆！空格停车处理';
      case 'survivor':
        return '有人求救！空格停车搭救';
      case 'block':
        return '道路被堵！空格停车处理';
    }
  }

  // ---- 路障生成 ----
  private spawnBlock(): void {
    if (this.hardSources.length === 0 && this.softSources.length === 0) return;
    const roll = Math.random();
    const x = rng(-4, 4);
    if (roll < 0.5 && this.softSources.length > 0) {
      // 软路障：锥桶/矮栏（可撞飞）
      const src = this.softSources[Math.floor(Math.random() * this.softSources.length)];
      const m = src.clone();
      m.rotation.y = Math.random() * Math.PI * 2;
      m.scale.setScalar(0.8 + Math.random() * 0.4);
      m.position.set(x, GROUND_Y, Z_SPAWN);
      this.scene.add(m);
      this.blocks.push({ group: m, z: Z_SPAWN, x, kind: 'soft', active: true, hit: false, flying: false, flyT: 0 });
    } else if (this.hardSources.length > 0) {
      // 硬路障：军用路障/废弃车（横在路中，必须绕或硬撞）
      const src = this.hardSources[Math.floor(Math.random() * this.hardSources.length)];
      const m = src.clone();
      const isVehicle = /Object/.test(src.name);
      m.rotation.y = isVehicle ? Math.PI / 2 + rng(-0.3, 0.3) : rng(-0.2, 0.2);
      m.position.set(x, GROUND_Y, Z_SPAWN);
      this.scene.add(m);
      this.blocks.push({ group: m, z: Z_SPAWN, x, kind: 'hard', active: true, hit: false, flying: false, flyT: 0 });
    }
  }

  // ---- 天气粒子 ----
  private buildWeather(): void {
    // 雨
    const rainN = 500;
    const rp = new Float32Array(rainN * 3);
    for (let i = 0; i < rainN; i++) {
      rp[i * 3] = (Math.random() - 0.5) * 90;
      rp[i * 3 + 1] = Math.random() * 30;
      rp[i * 3 + 2] = Math.random() * -260;
    }
    const rainGeo = new THREE.BufferGeometry();
    rainGeo.setAttribute('position', new THREE.BufferAttribute(rp, 3));
    this.rain = new THREE.Points(
      rainGeo,
      new THREE.PointsMaterial({ color: 0x6a8aaa, size: 0.07, transparent: true, opacity: 0.55 }),
    );
    this.rain.visible = false;
    this.scene.add(this.rain);

    // 雪
    const snowN = 300;
    const sp = new Float32Array(snowN * 3);
    for (let i = 0; i < snowN; i++) {
      sp[i * 3] = (Math.random() - 0.5) * 90;
      sp[i * 3 + 1] = Math.random() * 30;
      sp[i * 3 + 2] = Math.random() * -260;
    }
    const snowGeo = new THREE.BufferGeometry();
    snowGeo.setAttribute('position', new THREE.BufferAttribute(sp, 3));
    this.snow = new THREE.Points(
      snowGeo,
      new THREE.PointsMaterial({ color: 0xe8e8f0, size: 0.14, transparent: true, opacity: 0.7 }),
    );
    this.snow.visible = false;
    this.scene.add(this.snow);
  }

  // ---- 输入 ----
  private bindInput(): void {
    window.addEventListener('keydown', this.onKeyDown);
    window.addEventListener('keyup', this.onKeyUp);
  }

  private onKeyDown = (e: KeyboardEvent): void => {
    if (e.key === 'd' || e.key === 'D' || e.key === 'ArrowRight') this.gasHeld = true;
    if (e.key === 'a' || e.key === 'A' || e.key === 'ArrowLeft') this.brakeHeld = true;
    if (e.key === 'q' || e.key === 'Q') this.steerLeft = true;
    if (e.key === 'e' || e.key === 'E') this.steerRight = true;
    if (e.key === '1') this.setCam('chase');
    if (e.key === '2') this.setCam('cockpit');
    if (e.key === '3') this.setCam('rooftop');
    if (e.key === 'p' || e.key === 'P') Game.togglePark();
    if (e.key === ' ') {
      e.preventDefault();
      if (this.pendingRoad) {
        const k = this.pendingRoad.kind;
        this.pendingRoad = null;
        Game.openRoadEvent(k);
      }
    }
  };

  private onKeyUp = (e: KeyboardEvent): void => {
    if (e.key === 'd' || e.key === 'D' || e.key === 'ArrowRight') this.gasHeld = false;
    if (e.key === 'a' || e.key === 'A' || e.key === 'ArrowLeft') this.brakeHeld = false;
    if (e.key === 'q' || e.key === 'Q') this.steerLeft = false;
    if (e.key === 'e' || e.key === 'E') this.steerRight = false;
  };

  private setCam(mode: CamMode): void {
    this.camMode = mode;
  }

  // ---- 主循环 ----
  private loop = (): void => {
    if (this.disposed) return;
    this.raf = requestAnimationFrame(this.loop);
    const dt = Math.min(this.clock.getDelta(), 0.05);
    this.update(dt);
    this.renderScene(dt);
  };

  private renderScene(dt: number): void {
    const w = this.container.clientWidth || 1280;
    const h = this.container.clientHeight || 720;
    const cam = this.activeCam();

    // 主渲染
    this.renderer.setViewport(0, 0, w, h);
    this.renderer.setScissorTest(false);
    this.renderer.render(this.scene, cam);

    // 车内画中画：仅舱内视角时显示（画面顶部左上）
    if (this.camMode === 'cockpit') {
      const pw = Math.round(Math.min(230, w * 0.3));
      const ph = Math.round(pw * 0.7);
      const px = 14;
      const py = h - 78 - ph; // 顶部 HudBar 之下
      this.camInterior.aspect = pw / ph;
      this.camInterior.updateProjectionMatrix();
      this.renderer.setViewport(px, py, pw, ph);
      this.renderer.setScissor(px, py, pw, ph);
      this.renderer.setScissorTest(true);
      this.renderer.render(this.scene, this.camInterior);
      this.renderer.setScissorTest(false);
      this.renderer.setViewport(0, 0, w, h);
    }
    void dt;
  }

  private activeCam(): THREE.PerspectiveCamera {
    if (this.camMode === 'cockpit') return this.camCockpit;
    if (this.camMode === 'rooftop') return this.camRooftop;
    return this.camChase;
  }

  private update(dt: number): void {
    const state = Game.getState();
    const driving = state.phase === 'driving';

    // 游戏时钟推进（驾驶与事件阶段都走时间）
    if (driving || state.phase === 'event') {
      Game.advanceClock(dt);
    }

    // 耐久影响极速：耐久越低车越肉
    const maxSpeed = MAX_SPEED * (0.5 + 0.5 * (state.durability / 100));

    // 横向移动（躲避路障）
    const steerSpeed = 7;
    if (this.steerLeft) this.offsetX -= steerSpeed * dt;
    if (this.steerRight) this.offsetX += steerSpeed * dt;
    this.offsetX = Math.max(-4.5, Math.min(4.5, this.offsetX));
    if (this.rv) this.rv.position.x = this.offsetX;

    // 速度物理（天气影响同 2D 版）
    const weather = state.weather;
    let accel = ACCEL;
    let brake = BRAKE;
    if (weather === 'rain') brake = BRAKE * 0.7;
    if (weather === 'snow') accel = ACCEL * 0.6;

    const parked = state.parked && driving;
    if (parked) {
      // 停车：快速刹停
      this.speed = Math.max(0, this.speed - brake * 2.5 * dt);
    } else if (driving && this.gasHeld && state.fuel > 0) {
      this.speed += accel * dt;
    } else if (this.brakeHeld) {
      this.speed -= brake * dt;
    } else {
      this.speed -= DRAG * dt;
    }
    this.speed = Math.max(0, Math.min(maxSpeed, this.speed));

    // 推背感：猛加速→相机后仰下沉+车身前倾（快起慢落）；急刹→反向前顶
    const accelNow = (this.speed - this.prevSpeed) / Math.max(dt, 0.001); // km/h/s
    this.prevSpeed = this.speed;
    if (accelNow > 12) this.boost = Math.min(1, this.boost + dt * 4.5);
    else if (accelNow < -30) this.boost = Math.max(-0.9, this.boost - dt * 4.5);
    else this.boost += (0 - this.boost) * (1 - Math.exp(-dt * 1.1));
    if (this.rv) this.rv.rotation.x = -Math.PI / 2 - this.boost * 0.05;

    const worldSpeed = this.speed * KMH_TO_UNITS;

    // 世界滚动：虚线 + 路边元素
    for (const d of this.dashes) {
      d.position.z += worldSpeed * dt;
      if (d.position.z > Z_LOOP) d.position.z -= 300;
    }
    for (const p of this.props) {
      if (p.kind === 'zombie') {
        p.z += (worldSpeed - p.speed) * dt; // 丧尸朝车走来
        // 朝车的横向位置靠近
        const dx = this.offsetX - p.group.position.x;
        p.group.position.x += Math.sign(dx) * Math.min(Math.abs(dx), worldSpeed * 0.3 * dt);
        if (p.mixer) p.mixer.update(dt);
      } else {
        p.z += worldSpeed * dt;
      }
      p.group.position.z = p.z;
      // 循环回收
      if (p.z > Z_LOOP) {
        if (p.kind === 'zombie') {
          this.scene.remove(p.group);
          p.active = false;
          continue;
        }
        p.z = Z_SPAWN + Math.random() * 60;
        p.group.position.z = p.z;
      }
      // 丧尸撞车（横向接近才算）
      if (p.kind === 'zombie' && p.z > -3.2 && Math.abs(p.group.position.x - this.offsetX) < 1.1) {
        this.scene.remove(p.group);
        p.active = false;
        this.bump(0.45);
        Game.zombieHit(p.hitDmg ?? 3);
      }
    }
    this.props = this.props.filter((p) => p.active);

    // 路障滚动 + 碰撞
    for (const b of this.blocks) {
      b.z += worldSpeed * dt;
      b.group.position.z = b.z;
      if (b.flying) {
        // 软路障被撞飞：上抛 + 翻滚
        b.flyT += dt;
        b.group.position.y = GROUND_Y + b.flyT * 3.5;
        b.group.rotation.x += dt * 4;
        b.group.rotation.z += dt * 5;
        if (b.flyT > 0.8) {
          this.scene.remove(b.group);
          b.active = false;
          continue;
        }
      }
      if (!b.hit && b.z > -6.5 && Math.abs(b.group.position.x - this.offsetX) < 2.0) {
        b.hit = true;
        if (b.kind === 'soft') {
          // 软路障：撞飞，轻扣耐久
          Game.damageVehicle(2);
          this.bump(0.35);
          b.flying = true;
          b.flyT = 0;
        } else {
          // 硬路障：重扣耐久 + 强制减速
          Game.damageVehicle(12);
          this.bump(0.85);
          this.speed = Math.max(this.speed * 0.2, 8);
        }
      }
      if (b.z > Z_LOOP && !b.flying) {
        this.scene.remove(b.group);
        b.active = false;
      }
    }
    this.blocks = this.blocks.filter((b) => b.active);

    // 路边遭遇：滚动 + 接近提示（按空格触发）
    for (const re of this.roadEvents) {
      re.z += worldSpeed * dt;
      re.group.position.z = re.z;
      re.pulse += dt;
      // 光环脉冲
      const ring = re.group.children.find(
        (c) => (c as THREE.Mesh).isMesh && (c as THREE.Mesh).geometry.type === 'TorusGeometry',
      ) as THREE.Mesh | undefined;
      if (ring) {
        const m = ring.material as THREE.MeshStandardMaterial;
        if (m) m.emissiveIntensity = 1.2 + Math.sin(re.pulse * 3) * 0.8;
      }
      if (re.z > Z_LOOP) {
        this.scene.remove(re.group);
        re.active = false;
        continue;
      }
      if (!re.done && re.z > -9 && re.z < 3 && Math.abs(re.group.position.x - this.offsetX) < 3.4) {
        re.done = true;
        this.pendingRoad = re;
      }
    }
    this.roadEvents = this.roadEvents.filter((r) => r.active);

    // 丧尸生成（仅行驶时）
    if (driving && !parked && this.speed > 5) {
      this.spawnTimer -= dt;
      if (this.spawnTimer <= 0) {
        const rate = 1.5 - (this.speed / MAX_SPEED) * 1.0;
        this.spawnTimer = Math.max(0.4, rate);
        this.spawnZombie();
      }
    }

    // 路障生成（行驶时，约每 3.5-6s 一个）
    if (driving && !parked && this.speed > 5) {
      this.blockTimer -= dt;
      if (this.blockTimer <= 0) {
        this.blockTimer = rng(3.5, 6);
        this.spawnBlock();
      }
    }

    // 路边遭遇生成（行驶时，约每 10-18s 一个，最多同时 3 个）
    if (driving && !parked && this.speed > 8) {
      this.roadTimer -= dt;
      if (this.roadTimer <= 0) {
        this.roadTimer = rng(10, 18);
        if (this.roadEvents.length < 3) this.spawnRoadEvent();
      }
    }

    // 昼夜光照
    this.updateLighting(state.hour, state.weather);

    // 天气
    this.renderWeather(weather, dt, this.dayFactor);

    // 里程推进
    if (driving && this.speed > 0) {
      Game.driveTick((this.speed / 3600) * dt);
    }

    // 相机
    this.updateCameras(dt);

    // HUD
    this.updateHud(state.phase === 'driving', state.weather);
  }

  private bump(intensity: number): void {
    this.shakeTime = 0.35;
    this.shakeIntensity = intensity;
  }

  private updateCameras(dt: number): void {
    const cam = this.activeCam();
    const sx = this.offsetX * 0.85;
    // 推背滞后：向后下方压（z 增大、y 降低、看向更近地面），模拟坐车被带一下
    const lz = this.boost * 2.2;
    const ly = -this.boost * 0.55;
    // 追尾：车后上方，看向车头前方
    this.camChase.position.set(sx, 5.2 + ly, 13.5 + lz);
    this.camChase.lookAt(sx * 0.8, 2.2 - this.boost * 1.0, -30 - this.boost * 12);
    // 舱内：驾驶舱内（车头 -Z 端、挡风玻璃后）
    this.camCockpit.position.set(sx * 0.9 + 0.5, 2.3 + ly * 0.4, -3.6 + lz * 0.5);
    this.camCockpit.lookAt(sx * 0.7, 1.6 - this.boost * 0.5, -50 - this.boost * 6);
    // 车顶：车顶上方稍偏后，俯看前方（车顶战斗位）
    this.camRooftop.position.set(sx * 0.9, 6.4 + ly * 0.3, -0.8 + lz * 0.5);
    this.camRooftop.lookAt(sx * 0.7, 4.0 - this.boost * 0.5, -50 - this.boost * 6);
    // 车内画中画机位：驾驶舱中部看向车厢后部
    this.camInterior.position.set(0, 2.4, -2.0);
    this.camInterior.lookAt(0, 2.3, 6);

    // 撞击震屏
    if (this.shakeTime > 0) {
      this.shakeTime -= dt;
      const s = this.shakeIntensity * Math.max(0, this.shakeTime);
      cam.position.x += rng(-s, s) * 0.25;
      cam.position.y += rng(-s, s) * 0.18;
    }

    const w = this.container.clientWidth || 1280;
    const h = this.container.clientHeight || 720;
    if (cam.aspect !== w / h) {
      cam.aspect = w / h;
      cam.updateProjectionMatrix();
    }
    if (this.renderer.domElement.width !== w) {
      this.renderer.setSize(w, h);
    }
  }

  private renderWeather(weather: Weather, dt: number, dayFactor: number): void {
    // 天气基调 + 昼夜调制背景与雾
    let base: THREE.Color;
    let fogNear = 40;
    let fogFar = 260;
    if (weather === 'fog') {
      base = new THREE.Color(0x2a2622);
      fogNear = 18;
      fogFar = 120;
    } else if (weather === 'rain') {
      base = new THREE.Color(0x1c2226);
      fogNear = 30;
      fogFar = 200;
    } else if (weather === 'snow') {
      base = new THREE.Color(0x20242a);
      fogNear = 30;
      fogFar = 190;
    } else {
      base = new THREE.Color(0x2a2724);
    }
    const nightMix = Math.max(0, 1 - dayFactor);
    const tint = base.clone().lerp(new THREE.Color(0x0c0f14), nightMix * 0.75);
    this.scene.background = tint;
    this.scene.fog = new THREE.Fog(tint, fogNear, fogFar);

    this.rain.visible = weather === 'rain';
    this.snow.visible = weather === 'snow';
    if (this.rain.visible) this.stepParticles(this.rain, 16 * dt, 0.5);
    if (this.snow.visible) this.stepParticles(this.snow, 3 * dt, 0.15);
    this.weather = weather;
  }

  /** 昼夜光照：阳光色温/强度、环境光、车头灯、路灯随游戏小时变化 */
  private updateLighting(hour: number, weather: Weather): void {
    let dayFactor = 0;
    if (hour >= 5 && hour <= 20) {
      dayFactor = Math.sin(((hour - 5) / 15) * Math.PI);
    }
    dayFactor = Math.max(0.12, dayFactor);
    this.dayFactor = dayFactor;

    // 阳光色温：清晨/黄昏偏橙，正午偏白
    const t = Math.abs(hour - 12) / 12;
    const sunColor = new THREE.Color(1.0, 0.94 - t * 0.28, 0.82 - t * 0.42);
    // 雨雪天阳光打折扣
    const dim = weather === 'rain' || weather === 'snow' ? 0.6 : 1;
    this.sun.color.copy(sunColor);
    this.sun.intensity = dayFactor * 2.2 * dim;
    this.sun.position.set(-20, 40, -30);

    // 环境光：夜晚更冷更暗
    this.hemi.intensity = 0.15 + dayFactor * 0.4;
    this.hemi.color.setHSL(0.58, 0.2, 0.42 + dayFactor * 0.18);

    // 车头灯：夜晚开启，跟随车身横向偏移
    const nightOn = hour < 5 || hour >= 20 || dayFactor < 0.35;
    this.headlight.intensity = nightOn ? 26 : 0;
    this.headlight.position.x = this.offsetX * 0.9;
    this.headlight.target.position.x = this.offsetX * 0.9;

    // 路灯灯头：夜晚增强
    for (const lamp of this.nightLamps) {
      const m = lamp.material as THREE.MeshStandardMaterial;
      if (m) m.emissiveIntensity = nightOn ? 3.2 : 0.35;
    }
  }

  private stepParticles(points: THREE.Points, fall: number, sway: number): void {
    const pos = points.geometry.getAttribute('position') as THREE.BufferAttribute;
    for (let i = 0; i < pos.count; i++) {
      let y = pos.getY(i) - fall;
      if (y < GROUND_Y) y = 30 + Math.random() * 6;
      pos.setY(i, y);
      pos.setX(i, pos.getX(i) + Math.sin(i + performance.now() * 0.0004) * sway * 0.02);
    }
    pos.needsUpdate = true;
  }

  private updateHud(driving: boolean, weather: Weather): void {
    const s = Game.getState();
    const hh = Math.floor(s.hour);
    const mm = Math.floor((s.hour - hh) * 60);
    const time = `D${s.day} ${String(hh).padStart(2, '0')}:${String(mm).padStart(2, '0')}`;
    this.telemetryEl.textContent = driving
      ? `${Math.round(this.speed)} km/h · 车况${Math.round(s.durability)}% · ${time}`
      : `车况${Math.round(s.durability)}% · ${time}`;

    let hint = `${CAM_HINT[this.camMode]} · ${WEATHER_LABEL[weather]} · D 油门 A 刹车 Q/E 躲避 1/2/3 视角`;
    if (s.parked) hint += ' · P 继续行驶';
    else hint += ' · P 停车';
    if (this.pendingRoad) {
      hint = `【${this.roadHint(this.pendingRoad.kind)}】`;
    }
    this.hintEl.textContent = hint;
    this.pipEl.style.display = this.camMode === 'cockpit' ? 'block' : 'none';
  }

  dispose(): void {
    this.disposed = true;
    cancelAnimationFrame(this.raf);
    window.removeEventListener('keydown', this.onKeyDown);
    window.removeEventListener('keyup', this.onKeyUp);
    this.telemetryEl.remove();
    this.hintEl.remove();
    this.pipEl.remove();
    this.renderer.dispose();
    if (this.renderer.domElement.parentElement === this.container) {
      this.container.removeChild(this.renderer.domElement);
    }
  }
}
