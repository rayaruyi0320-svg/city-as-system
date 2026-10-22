import processing.sound.*;
import processing.video.*;   // ← 新增：视频库
import java.util.*;

PApplet app;
PImage  trainHead;
boolean trainHeadFacesRight = true;

// ── 背景视频 ──────────────────────────────────────────────────────────────────
Movie  bgVideo;
boolean videoReady   = false;   // 视频至少读入一帧后才绘制
float  videoAlpha    = 120;     // 0-255，半透明叠加（约47%）
float  videoVolume   = 0.15;    // 视频原声音量（0-1），通过 bgVideo.volume() 设置

ArrayList<MetroLine> lines = new ArrayList<MetroLine>();
HashMap<String, ArrayList<MetroStation>> stationIndex = new HashMap<String, ArrayList<MetroStation>>();
HashMap<String, PImage> memoryCache = new HashMap<String, PImage>();
ArrayList<ToneSound> voices = new ArrayList<ToneSound>();

MetroStation activeMemoryStation = null;
float memoryFadeAlpha = 0;
boolean memoryFadingOut = false;
int memoryTriggerMs = 0;
static final int MEM_FADE_IN_MS = 800;
static final int MEM_HOLD_MS    = 2800;
static final int MEM_FADE_OUT_MS = 1000;
int lastMemoryTrigger = -9999;

float[] tunnelLightX   = new float[12];
float[] tunnelLightY   = new float[12];
float[] tunnelLightSpd = new float[12];
float[] tunnelLightA   = new float[12];

float[] railGlowPhase = new float[28];
float[] railGlowSeed  = new float[28];
float[] railDustT     = new float[36];
float[] railDustSide  = new float[36];
float[] railDustSpeed = new float[36];
float[] railDustSize  = new float[36];

String subtitleText  = "";
float  subtitleAlpha = 0;
int    subtitleMs    = -9999;
static final int SUBTITLE_FADE = 400;
static final int SUBTITLE_HOLD = 2400;

float railScrollOffset = 0;

Slider crowdSlider, dispatchSlider, soundSlider;
int selectedLineIndex = 0;
MetroStation hoveredStation = null;
boolean showIntro = true;
int introStart;

float globalCrowd = 0.55;
boolean rushHour  = false;
boolean soundOn   = true;

float topPanelH, bottomPanelY, leftMargin = 90, rightMargin = 90;
float[] pentatonic = {261.63, 293.66, 329.63, 392.00, 440.00};

int lastDroneMs = 0;

// ═════════════════════════════════════════════════════════════════════════════
void setup() {
  size(1600, 900, P2D);
  smooth(8);
  app = this;
  textFont(createFont("Arial", 14, true));

  topPanelH    = height * 0.62;
  bottomPanelY = topPanelH;

  trainHead = loadAnyImage("train head.png");
  if (trainHead != null) trainHead.resize(0, 400);

  // ── 加载背景视频 ────────────────────────────────────────────────────────────
  try {
    bgVideo = new Movie(this, "background.mp4");
    bgVideo.loop();           // 循环播放
    bgVideo.volume(videoVolume); // 降低原声
  } catch (Exception e) {
    println("background.mp4 not found or video library missing: " + e.getMessage());
    bgVideo = null;
  }

  for (int i = 0; i < tunnelLightX.length; i++) initTunnelLight(i, true);
  for (int i = 0; i < railGlowPhase.length; i++) {
    railGlowPhase[i] = random(TWO_PI);
    railGlowSeed[i]  = random(1);
  }
  for (int i = 0; i < railDustT.length; i++) {
    railDustT[i]     = random(1);
    railDustSide[i]  = random(1) < 0.5 ? -1 : 1;
    railDustSpeed[i] = random(0.002, 0.008);
    railDustSize[i]  = random(1.5, 4.5);
  }

  buildNetwork();
  resolveTransfers();
  layoutBottomLanesY();

  crowdSlider    = new Slider(width - 280, height - 132, 220, 16, 0.55, 0.0, 1.0);
  dispatchSlider = new Slider(width - 280, height - 94,  220, 16, 1.0,  0.4, 2.5);
  soundSlider    = new Slider(width - 280, height - 56,  220, 16, 0.03, 0.0, 0.08);

  introStart = millis();
}

// ── 视频库回调：每当新帧可读时触发 ──────────────────────────────────────────────
void movieEvent(Movie m) {
  m.read();
  videoReady = true;
}

// ═════════════════════════════════════════════════════════════════════════════
void draw() {
  updateMemoryFade();
  updateSystem();

  drawCinematicTop();
  drawBottomMap();
  drawUI();

  if (showIntro) drawIntroOverlay();

  for (int i = voices.size() - 1; i >= 0; i--) {
    voices.get(i).update();
    if (voices.get(i).dead) voices.remove(i);
  }

  if (soundOn && millis() - lastDroneMs > 7600) {
    lastDroneMs = millis();
    float base = pentatonic[selectedLineIndex];
    playNote(base * 0.5, 0.06, 1800);
    playNote(base, 0.04, 1500);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
void updateMemoryFade() {
  if (activeMemoryStation == null) { memoryFadeAlpha = 0; return; }
  int elapsed = millis() - memoryTriggerMs;
  if (!memoryFadingOut) {
    if      (elapsed < MEM_FADE_IN_MS)                     memoryFadeAlpha = constrain((float)elapsed / MEM_FADE_IN_MS, 0, 1);
    else if (elapsed < MEM_FADE_IN_MS + MEM_HOLD_MS)       memoryFadeAlpha = 1.0;
    else                                                    memoryFadingOut = true;
  } else {
    int fadeStart = MEM_FADE_IN_MS + MEM_HOLD_MS;
    float t = constrain((float)(elapsed - fadeStart) / MEM_FADE_OUT_MS, 0, 1);
    memoryFadeAlpha = 1.0 - smoothstep(0, 1, t);
    if (memoryFadeAlpha <= 0.01) {
      activeMemoryStation = null;
      memoryFadeAlpha = 0;
      memoryFadingOut = false;
    }
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  CINEMATIC TOP PANEL
// ═════════════════════════════════════════════════════════════════════════════
void drawCinematicTop() {
  // 1. 暗色渐变底层
  for (int y = 0; y < (int)topPanelH; y++) {
    float t = (float)y / topPanelH;
    stroke(lerpColor(color(4, 5, 14), color(12, 10, 26), t));
    line(0, y, width, y);
  }

  // 2. 背景视频（半透明叠加在渐变之上）
  drawBackgroundVideo();

  // 3. 透视铁轨 + 粒子
  drawPerspectiveRails();
  drawRailGlow();
  drawRailParticles();
  drawTunnelLights();

  // 4. 主列车（在视频和轨道之上）
  MetroLine currentLine = lines.get(selectedLineIndex);
  Train hero = currentLine.heroTrain();
  drawHeroTrain(hero, currentLine);

  // 5. 记忆照片（最上层）
  if (activeMemoryStation != null && memoryFadeAlpha > 0.01) {
    drawMemoryOverlay();
  }

  drawSubtitleTicker();
  drawTitleLine();
}

// ─────────────────────────────────────────────────────────────────────────────
//  背景视频绘制：保持原始比例 cover 填满 topPanel，半透明
// ─────────────────────────────────────────────────────────────────────────────
void drawBackgroundVideo() {
  if (bgVideo == null || !videoReady) return;

  // 当记忆图片完全显示时，把视频淡出（避免干扰记忆氛围）
  float targetAlpha = map(memoryFadeAlpha, 0, 1, videoAlpha, 28);
  float a = targetAlpha;

  pushStyle();
  imageMode(CORNER);

  // cover 模式：让视频铺满顶部面板，保持宽高比不变
  float vw = bgVideo.width;
  float vh = bgVideo.height;
  if (vw <= 0 || vh <= 0) { popStyle(); return; }

  float panelW = width;
  float panelH = topPanelH;
  float scale  = max(panelW / vw, panelH / vh);  // cover：取较大缩放
  float drawW  = vw * scale;
  float drawH  = vh * scale;
  float drawX  = (panelW - drawW) * 0.5;
  float drawY  = (panelH - drawH) * 0.5;

  // clip 到 topPanel 区域（Processing 没原生 clip，用 tint alpha 控制透明度）
  tint(255, a);
  image(bgVideo, drawX, drawY, drawW, drawH);
  noTint();

  // 在视频上叠一层暗色蒙版，使轨道和粒子效果更清晰
  noStroke();
  fill(4, 5, 14, 110);
  rect(0, 0, width, topPanelH);

  popStyle();
}

// ─────────────────────────────────────────────────────────────────────────────
void drawPerspectiveRails() {
  MetroLine cl = lines.get(selectedLineIndex);
  color rc = cl.lineColor;
  float vpX = width * 0.5, vpY = topPanelH * 0.30, botY = topPanelH * 0.95;
  railScrollOffset += 4.5;

  for (int i = 0; i < 18; i++) {
    float frac  = ((float)i / 18 + (railScrollOffset * 0.0012)) % 1.0;
    float t     = frac * frac;
    float y     = lerp(vpY, botY, frac);
    float halfW = lerp(0, width * 0.46, t);
    float alpha = lerp(10, 55, t);
    stroke(red(rc), green(rc), blue(rc), alpha);
    strokeWeight(lerp(0.5, 3.5, t));
    line(vpX - halfW, y, vpX + halfW, y);
  }
  strokeWeight(2.5); stroke(red(rc), green(rc), blue(rc), 80);
  line(vpX, vpY, vpX - width * 0.46, botY);
  line(vpX, vpY, vpX + width * 0.46, botY);
  strokeWeight(6); stroke(red(rc), green(rc), blue(rc), 30);
  line(vpX - 10, botY - 5, vpX - width * 0.46, botY);
  line(vpX + 10, botY - 5, vpX + width * 0.46, botY);
  noStroke();
}

void drawRailGlow() {
  MetroLine cl = lines.get(selectedLineIndex);
  color rc = cl.lineColor;
  float vpX = width * 0.5, vpY = topPanelH * 0.30, botY = topPanelH * 0.95;

  pushStyle(); noStroke(); blendMode(ADD);
  for (int i = 0; i < railGlowPhase.length; i++) {
    float t      = (frameCount * 0.003 + i * 0.045) % 1.0;
    float y      = lerp(botY, vpY, t);
    float spread = lerp(width * 0.46, 2, t);
    float glowW  = lerp(70, 8, t);
    float glowH  = lerp(22, 4, t);
    float wiggle = sin(frameCount * 0.02 + railGlowPhase[i]) * 4;
    float alpha  = lerp(10, 70, 1.0 - t) * (0.35 + globalCrowd * 0.6);
    fill(red(rc), green(rc), blue(rc), alpha);
    ellipse(vpX - spread + wiggle, y, glowW, glowH);
    ellipse(vpX + spread - wiggle, y, glowW, glowH);
    fill(255, 255, 230, alpha * 0.16);
    ellipse(vpX + sin(i * 1.7 + frameCount * 0.01) * 12, y, 3, 3);
  }
  blendMode(BLEND); popStyle();
}

void drawRailParticles() {
  MetroLine cl = lines.get(selectedLineIndex);
  color rc = cl.lineColor;
  float vpX = width * 0.5, vpY = topPanelH * 0.30, botY = topPanelH * 0.95;

  pushStyle(); noStroke(); blendMode(ADD);
  for (int i = 0; i < railDustT.length; i++) {
    railDustT[i] += railDustSpeed[i];
    if (railDustT[i] > 1) railDustT[i] = 0;
    float t     = railDustT[i];
    float y     = lerp(botY, vpY, t);
    float railX = vpX + railDustSide[i] * lerp(width * 0.42, 6, t);
    float drift = sin(frameCount * 0.03 + i) * 6;
    float alpha = lerp(30, 4, t) * (0.5 + globalCrowd * 0.5);
    fill(red(rc), green(rc), blue(rc), alpha);
    ellipse(railX + drift, y, railDustSize[i], railDustSize[i]);
    if (activeMemoryStation != null && memoryFadeAlpha > 0.1) {
      fill(255, 240, 200, alpha * 0.8 * memoryFadeAlpha);
      ellipse(railX - drift * 0.5, y, railDustSize[i] * 1.4, railDustSize[i] * 1.4);
    }
  }
  blendMode(BLEND); popStyle();
}

void drawTunnelLights() {
  for (int i = 0; i < tunnelLightX.length; i++) {
    tunnelLightY[i] += tunnelLightSpd[i];
    float cx = width * 0.5;
    tunnelLightX[i] += (tunnelLightX[i] - cx) * 0.06;
    if (tunnelLightY[i] > topPanelH * 0.92) initTunnelLight(i, false);
    float streak = tunnelLightSpd[i] * 3.5;
    float a = tunnelLightA[i] * constrain((tunnelLightY[i] - topPanelH * 0.25) / (topPanelH * 0.3), 0, 1);
    stroke(255, 240, 200, a);
    strokeWeight(1.2);
    line(tunnelLightX[i], tunnelLightY[i] - streak, tunnelLightX[i], tunnelLightY[i]);
  }
  noStroke();
}

void initTunnelLight(int i, boolean anywhere) {
  float vpX = width * 0.5, vpY = topPanelH * 0.28;
  tunnelLightX[i]   = vpX + random(-22, 22);
  tunnelLightY[i]   = anywhere ? random(vpY, topPanelH * 0.7) : vpY + random(2, 12);
  tunnelLightSpd[i] = random(3.5, 9.0);
  tunnelLightA[i]   = random(60, 160);
}

// ─────────────────────────────────────────────────────────────────────────────
//  记忆图片叠加层
// ─────────────────────────────────────────────────────────────────────────────
void drawMemoryOverlay() {
  float alpha = memoryFadeAlpha;
  color lc = activeMemoryStation.parentLine.lineColor;
  ArrayList<PImage> images = activeMemoryStation.getMemoryImages();

  if (images != null && !images.isEmpty()) {
    float maxW = width * 0.78;
    float maxH = topPanelH * 0.50;
    float gap  = 26;

    ArrayList<float[]> dims = new ArrayList<float[]>();
    float totalW = 0, maxDrawH = 0;
    for (PImage img : images) {
      float s = min(maxW / images.size() / img.width, maxH / img.height);
      float w = img.width * s, h = img.height * s;
      dims.add(new float[]{w, h});
      totalW  += w;
      maxDrawH = max(maxDrawH, h);
    }
    totalW += gap * (images.size() - 1);

    float startX = (width - totalW) / 2;
    float centerY = topPanelH * 0.40;

    pushStyle();
    imageMode(CORNER);
    for (int i = 0; i < images.size(); i++) {
      PImage img = images.get(i);
      float w = dims.get(i)[0], h = dims.get(i)[1];
      float x = startX;
      float y = centerY - h * 0.5 + ((i % 2 == 0) ? -5 : 6);
      noStroke();
      fill(0, 0, 0, 90 * alpha);
      rect(x - 10, y - 10, w + 20, h + 20, 8);
      tint(
        lerp(red(lc), 255, 0.7),
        lerp(green(lc), 255, 0.7),
        lerp(blue(lc), 255, 0.7),
        255 * alpha * (1.0 - i * 0.16)
      );
      image(img, x, y, w, h);
      noTint();
      noFill(); stroke(255, 255, 255, 70 * alpha);
      rect(x - 10, y - 10, w + 20, h + 20, 8);
      startX += w + gap;
    }
    popStyle();
  } else {
    noStroke(); fill(255, 240, 200, alpha * 0.3);
    rect(0, 0, width, topPanelH);
    fill(255, 220 * alpha); textAlign(CENTER, CENTER); textSize(22);
    text(activeMemoryStation.name, width * 0.5, topPanelH * 0.38);
  }

  drawVignette(alpha);

  float captionY = topPanelH * 0.80;
  fill(0, 0, 0, 140 * alpha);
  rect(0, captionY - 10, width, topPanelH * 0.13 + 10);
  fill(255, 240, 200, 240 * alpha); textAlign(LEFT, BOTTOM); textSize(20);
  text(activeMemoryStation.name, 60, captionY + topPanelH * 0.11);
  fill(200, 210, 230, 180 * alpha); textSize(14);
  text(activeMemoryStation.memoryCaption, 60, captionY + topPanelH * 0.11 + 22);
  fill(red(lc), green(lc), blue(lc), 200 * alpha);
  rect(0, captionY - 10, 6, topPanelH * 0.13 + 10);
}

void drawVignette(float alpha) {
  noStroke();
  for (int y = 0; y < topPanelH * 0.4; y++) {
    float ft = 1.0 - (float)y / (topPanelH * 0.4); ft = ft * ft;
    stroke(4, 5, 14, 255 * ft * alpha); line(0, y, width, y);
  }
  for (int y = (int)(topPanelH * 0.75); y < (int)topPanelH; y++) {
    float ft = ((float)y - topPanelH * 0.75) / (topPanelH * 0.25); ft = ft * ft;
    stroke(4, 5, 14, 255 * ft * alpha); line(0, y, width, y);
  }
  for (int x = 0; x < width * 0.2; x++) {
    float ft = 1.0 - (float)x / (width * 0.2); ft = ft * ft;
    stroke(4, 5, 14, 255 * ft * alpha); line(x, 0, x, topPanelH);
  }
  for (int x = (int)(width * 0.8); x < width; x++) {
    float ft = ((float)x - width * 0.8) / (width * 0.2); ft = ft * ft;
    stroke(4, 5, 14, 255 * ft * alpha); line(x, 0, x, topPanelH);
  }
  noStroke();
}

// ─────────────────────────────────────────────────────────────────────────────
void drawHeroTrain(Train hero, MetroLine cl) {
  float cx = width * 0.5, botY = topPanelH * 0.66;
  if (trainHead != null) {
    pushStyle(); imageMode(CENTER);
    for (int g = 5; g >= 1; g--) {
      fill(red(cl.lineColor), green(cl.lineColor), blue(cl.lineColor), 18 * (6 - g));
      ellipse(cx, botY, 160 * g * 0.28, 60 * g * 0.28);
    }
    tint(lerp(red(cl.lineColor), 255, 0.45),
         lerp(green(cl.lineColor), 255, 0.45),
         lerp(blue(cl.lineColor), 255, 0.45), 230);
    float sc = 1.0 + 0.04 * sin(frameCount * 0.04);
    if (trainHeadFacesRight) image(trainHead, cx, botY, trainHead.width * sc, trainHead.height * sc);
    else { pushMatrix(); translate(cx, botY); scale(-sc, sc); image(trainHead, 0, 0); popMatrix(); }
    noTint(); popStyle();
  } else {
    noStroke(); fill(red(cl.lineColor), green(cl.lineColor), blue(cl.lineColor), 200);
    rect(cx - 60, botY - 30, 120, 55, 10);
  }
}

void drawSubtitleTicker() {
  int elapsed = millis() - subtitleMs;
  if      (elapsed < SUBTITLE_FADE)                  subtitleAlpha = constrain((float)elapsed / SUBTITLE_FADE, 0, 1);
  else if (elapsed < SUBTITLE_FADE + SUBTITLE_HOLD)  subtitleAlpha = 1.0;
  else subtitleAlpha = 1.0 - constrain((float)(elapsed - SUBTITLE_FADE - SUBTITLE_HOLD) / SUBTITLE_FADE, 0, 1);
  if (subtitleAlpha <= 0.01 || subtitleText.isEmpty()) return;
  fill(0, 0, 0, 110 * subtitleAlpha);
  rect(0, topPanelH - 38, width, 38);
  fill(255, 248, 220, 210 * subtitleAlpha);
  textAlign(CENTER, CENTER); textSize(14);
  text(subtitleText, width * 0.5, topPanelH - 19);
}

void drawTitleLine() {
  pushStyle();
  fill(255, 200); textAlign(LEFT, TOP); textSize(18);
  text("Conducting the Underground Symphony", 36, 14);
  MetroLine cl = lines.get(selectedLineIndex);
  fill(red(cl.lineColor), green(cl.lineColor), blue(cl.lineColor), 210);
  textSize(12);
  text(cl.lineName + "  ·  " + cl.pentatonicName, 36, 38);
  popStyle();
}

// ─────────────────────────────────────────────────────────────────────────────
void activateMemory(MetroStation st) {
  if (!st.isMemory) return;
  if (millis() - lastMemoryTrigger < 1200) return;
  lastMemoryTrigger = millis();
  st.flash = 1.0;
  st.resonance = min(st.resonance + 0.6, 1.0);
  st.lastTriggerMs = millis();
  activeMemoryStation = st;
  memoryTriggerMs = millis();
  memoryFadeAlpha = 0;
  memoryFadingOut = false;
}

// ═════════════════════════════════════════════════════════════════════════════
void updateSystem() {
  globalCrowd = crowdSlider.value;
  dispatchSlider.value = constrain(dispatchSlider.value, 0.4, 2.5);
  soundSlider.value    = constrain(soundSlider.value, 0.0, 0.08);
  for (int i = 0; i < lines.size(); i++) {
    MetroLine ml = lines.get(i);
    if (i == selectedLineIndex) ml.dispatchRate = dispatchSlider.value;
    ml.globalCrowd = globalCrowd * (rushHour ? 1.25 : 1.0);
    ml.update();
  }
  hoveredStation = null;
  for (MetroLine ml : lines)
    for (MetroStation st : ml.stations)
      if (dist(mouseX, mouseY, st.screenX(), st.parentLine.bottomY) < 14)
        hoveredStation = st;
  if (millis() - introStart > 4300) showIntro = false;
}

// ═════════════════════════════════════════════════════════════════════════════
void drawBottomMap() {
  noStroke(); fill(5, 6, 12, 235);
  rect(0, bottomPanelY, width, height - bottomPanelY);
  fill(255, 255, 255, 22); rect(0, bottomPanelY, width, 1);
  drawTransferWeb();
  for (MetroLine ml : lines) ml.drawBottom();
  fill(255, 180); textAlign(LEFT, TOP); textSize(11);
  text("click a station to surface a memory  ·  ★ = memory  ·  brighter = denser crowd", 36, height - 26);
}

void drawTransferWeb() {
  pushStyle(); strokeCap(ROUND);
  for (String key : stationIndex.keySet()) {
    ArrayList<MetroStation> group = stationIndex.get(key);
    if (group.size() < 2) continue;
    for (int i = 0; i < group.size(); i++) {
      for (int j = i + 1; j < group.size(); j++) {
        MetroStation a = group.get(i), b = group.get(j);
        float x1 = a.screenX(), y1 = a.parentLine.bottomY;
        float x2 = b.screenX(), y2 = b.parentLine.bottomY;
        float bend = 18 + abs(y2 - y1) * 0.30;
        boolean hot = (a == hoveredStation || b == hoveredStation ||
                       a.parentLine == lines.get(selectedLineIndex) ||
                       b.parentLine == lines.get(selectedLineIndex));
        stroke(255, hot ? 60 : 18); strokeWeight(hot ? 2.0 : 1.0); noFill();
        bezier(x1, y1, x1, y1 - bend, x2, y2 - bend, x2, y2);
      }
    }
  }
  popStyle();
}

// ═════════════════════════════════════════════════════════════════════════════
void drawUI() {
  crowdSlider.draw(); dispatchSlider.draw(); soundSlider.draw();
  pushStyle();
  fill(230, 230, 240, 180); textSize(11);
  text("crowd",    crowdSlider.x,    crowdSlider.y    - 16);
  text("dispatch", dispatchSlider.x, dispatchSlider.y - 16);
  text("sound",    soundSlider.x,    soundSlider.y    - 16);
  noStroke(); fill(0, 0, 0, 88); rect(width - 320, 8, 304, 70, 12);
  fill(255, 230); textAlign(LEFT, TOP); textSize(11);
  text("1-5 select lines  ·  ↑↓ crowd  ·  ←→ dispatch", width - 308, 18);
  text("R rush hour  ·  M mute  ·  H flip head",          width - 308, 36);
  text(soundOn ? "♪ sound on" : "♪ muted",                width - 308, 54);
  popStyle();

  if (hoveredStation != null) {
    pushStyle();
    noStroke(); fill(0, 0, 0, 120);
    rect(30, bottomPanelY + 6, 380, hoveredStation.isMemory ? 46 : 28, 8);
    fill(255, 245, 210, 220); textSize(12); textAlign(LEFT, TOP);
    text("↑ " + hoveredStation.name, 42, bottomPanelY + 12);
    if (hoveredStation.isMemory) {
      fill(220, 230, 240, 180); textSize(11);
      text("★  " + hoveredStation.memoryCaption, 42, bottomPanelY + 30);
    }
    popStyle();
  }
}

void drawIntroOverlay() {
  float t = constrain((millis() - introStart) / 4300.0, 0, 1);
  float a = 1.0 - smoothstep(0.0, 1.0, t);
  if (a <= 0.01) return;
  pushStyle(); noStroke();
  fill(0, 0, 0, 200 * a); rect(0, 0, width, height);
  fill(255, 240 * a); textAlign(CENTER, CENTER); textSize(26);
  text("Conducting the Underground Symphony", width * 0.5, height * 0.45);
  textSize(15); fill(200, 210, 230, 200 * a);
  text("A Living Musical Ecosystem of MY SHANGHAI MEMORIES", width * 0.5, height * 0.52);
  popStyle();
}

float smoothstep(float e0, float e1, float x) {
  float t = constrain((x - e0) / (e1 - e0), 0, 1);
  return t * t * (3 - 2 * t);
}

// ═════════════════════════════════════════════════════════════════════════════
//  INPUT
// ═════════════════════════════════════════════════════════════════════════════
void mousePressed() {
  crowdSlider.pressed(mouseX, mouseY);
  dispatchSlider.pressed(mouseX, mouseY);
  soundSlider.pressed(mouseX, mouseY);

  MetroStation clicked = null;
  MetroLine clickedLine = null;
  for (MetroLine ml : lines) {
    for (MetroStation st : ml.stations) {
      if (dist(mouseX, mouseY, st.screenX(), st.parentLine.bottomY) < 14) {
        clicked = st; clickedLine = ml; break;
      }
    }
    if (clicked != null) break;
  }

  if (clicked != null && clickedLine != null) {
    selectedLineIndex = lines.indexOf(clickedLine);
    dispatchSlider.value = clickedLine.dispatchRate;
    if (clicked.isMemory) {
      activateMemory(clicked);
    } else {
      subtitleText = clicked.name;
      subtitleMs   = millis();
    }
  } else {
    for (MetroLine ml : lines) {
      if (mouseY > ml.bottomY - 18 && mouseY < ml.bottomY + 18) {
        selectedLineIndex = lines.indexOf(ml);
        dispatchSlider.value = ml.dispatchRate;
        break;
      }
    }
  }
}

void mouseDragged()  { crowdSlider.drag(mouseX,mouseY); dispatchSlider.drag(mouseX,mouseY); soundSlider.drag(mouseX,mouseY); }
void mouseReleased() { crowdSlider.released(); dispatchSlider.released(); soundSlider.released(); }

void keyPressed() {
  if (key >= '1' && key <= '5') {
    int idx = key - '1';
    if (idx < lines.size()) { selectedLineIndex = idx; dispatchSlider.value = lines.get(idx).dispatchRate; }
  }
  if (keyCode == UP)    crowdSlider.value    = min(crowdSlider.maxValue,    crowdSlider.value    + 0.05);
  if (keyCode == DOWN)  crowdSlider.value    = max(crowdSlider.minValue,    crowdSlider.value    - 0.05);
  if (keyCode == RIGHT) dispatchSlider.value = min(dispatchSlider.maxValue, dispatchSlider.value + 0.1);
  if (keyCode == LEFT)  dispatchSlider.value = max(dispatchSlider.minValue, dispatchSlider.value - 0.1);
  if (key == 'r' || key == 'R') rushHour = !rushHour;
  if (key == 'm' || key == 'M') {
    soundOn = !soundOn;
    // 同步静音视频原声
    if (bgVideo != null) bgVideo.volume(soundOn ? videoVolume : 0);
  }
  if (key == 'h' || key == 'H') trainHeadFacesRight = !trainHeadFacesRight;
  // V 键：调节视频透明度（可选调试用）
  if (key == 'v' || key == 'V') videoAlpha = (videoAlpha > 60) ? 40 : 120;
}

// ═════════════════════════════════════════════════════════════════════════════
//  AUDIO
// ═════════════════════════════════════════════════════════════════════════════
void playNote(float freq, float amp, int durationMs) {
  if (!soundOn || soundSlider == null) return;
  if (voices.size() >= 8) { voices.get(0).stopTone(); voices.remove(0); }
  float finalAmp = constrain(amp * soundSlider.value, 0.0, 0.08);
  if (finalAmp <= 0.0001) return;
  voices.add(new ToneSound(freq, finalAmp, durationMs, 0));
}

void playDyad(float f1, float f2, float amp, int durationMs) {
  playNote(f1, amp, durationMs);
  playNote(f2, amp * 0.75, durationMs);
}

void playChord(float baseFreq, float amp, int durationMs) {
  playNote(baseFreq,       amp,       durationMs);
  playNote(baseFreq * 1.5, amp * 0.7, durationMs);
  playNote(baseFreq * 2.0, amp * 0.5, durationMs);
}

// ═════════════════════════════════════════════════════════════════════════════
//  IMAGE LOADING
// ═════════════════════════════════════════════════════════════════════════════
PImage loadAnyImage(String fileName) {
  if (fileName == null || fileName.isEmpty()) return null;
  PImage img = null;
  try { img = loadImage(fileName); } catch (Exception e) {}
  if (img == null) try { img = loadImage(sketchPath(fileName)); } catch (Exception e) {}
  return img;
}

PImage loadMemoryImage(String fileName) {
  if (fileName == null || fileName.isEmpty()) return null;
  if (memoryCache.containsKey(fileName)) return memoryCache.get(fileName);
  PImage img = loadAnyImage(fileName);
  if (img != null) memoryCache.put(fileName, img);
  return img;
}

// ═════════════════════════════════════════════════════════════════════════════
//  BUILD NETWORK  — 文件名精确匹配文件夹截图（含空格版本）
// ═════════════════════════════════════════════════════════════════════════════
void buildNetwork() {
  color c1  = unhex("FFF00030");
  color c2  = unhex("FF90D800");
  color c10 = unhex("FFC0A8D8");
  color c11 = unhex("FF781830");
  color c13 = unhex("FFF090D8");

  MetroLine l1  = new MetroLine("Line 1",  pentatonic[0], c1,  0, "Gong / C");
  MetroLine l2  = new MetroLine("Line 2",  pentatonic[1], c2,  1, "Shang / D");
  MetroLine l10 = new MetroLine("Line 10", pentatonic[2], c10, 2, "Jue / E");
  MetroLine l11 = new MetroLine("Line 11", pentatonic[3], c11, 3, "Zhi / G");
  MetroLine l13 = new MetroLine("Line 13", pentatonic[4], c13, 4, "Yu / A");

  // Line 1
  l1.addStation("上海马戏城",        0.10, true,
    new String[]{"马戏城.jpg"},
    "An evening of lights and wonder, where childhood first learned to believe in magic.");
  l1.addStation("人民广场",          0.34, false, null, "");
  l1.addStation("一大会址·黄陂南路", 0.40, true,
    new String[]{"一大会址.jpg"},
    "After the Gaokao exam, the world felt suddenly open, as if everything had just begun.");
  l1.addStation("汉中路",            0.46, true,
    new String[]{"汉中路.jpg", "汉中路 2.jpg"},
    "A quiet citywalk during Spanish field trip with a friend, where the afternoon stretched longer than it should.");
  l1.addStation("陕西南路",          0.55, true,
    new String[]{"陕西南路.jpg", "陕西南路站.jpg"},
    "A familiar route to the theater, where other lives briefly replaced my own.");
  l1.addStation("徐家汇",            0.70, false, null, "");
  l1.addStation("上海南站",          0.84, false, null, "");
  l1.addStation("莘庄",              0.95, false, null, "");

  // Line 2
  l2.addStation("国家会展中心", 0.08, true,
    new String[]{"国家会展中心.jpg"},
    "Early mornings and long commutes, stepping quietly into the rhythm of working life.");
  l2.addStation("静安寺",       0.23, false, null, "");
  l2.addStation("人民广场",     0.34, false, null, "");
  l2.addStation("南京西路",     0.45, false, null, "");
  l2.addStation("南京东路",     0.52, true,
    new String[]{"南京东路.jpg", "南京东路 2.jpg"},
    "A sunny day with family and a new friend, where my sense of style first took shape.");
  l2.addStation("江苏路",       0.58, false, null, "");
  l2.addStation("陆家嘴",       0.74, false, null, "");
  l2.addStation("上海科技馆",   0.83, false, null, "");
  l2.addStation("世纪公园",     0.92, false, null, "");

  // Line 10
  l10.addStation("陕西南路",      0.16, true,
    new String[]{"陕西南路站.jpg", "陕西南路.jpg"},
    "A familiar route to the theater, where other lives briefly replaced my own.");
  l10.addStation("上海图书馆",    0.26, false, null, "");
  l10.addStation("淮海中路",      0.31, true,
    new String[]{"淮海中路.jpg", "淮海中路 2.jpg"},
    "My first Christmas market with friends, on a street that seemed to glow quietly through the winter.");
  l10.addStation("交通大学",      0.40, false, null, "");
  l10.addStation("南京西路",      0.52, false, null, "");
  l10.addStation("南京东路",      0.58, true,
    new String[]{"南京东路.jpg", "南京东路 2.jpg"},
    "A sunny day with family and a new friend, where my sense of style first took shape.");
  l10.addStation("新天地",        0.67, true,
    new String[]{"新天地.jpg"},
    "A quiet city walk in Xintiandi, where the day felt just slightly different with someone beside me.");
  l10.addStation("豫园",          0.74, false, null, "");
  l10.addStation("虹桥1号航站楼", 0.92, false, null, "");

  // Line 11
  l11.addStation("交通大学",   0.20, false, null, "");
  l11.addStation("江苏路",     0.30, false, null, "");
  l11.addStation("上海图书馆", 0.40, false, null, "");
  l11.addStation("新天地",     0.52, true,
    new String[]{"新天地.jpg"},
    "A quiet city walk in Xintiandi, where the day felt just slightly different with someone beside me.");
  l11.addStation("苏州河",     0.62, false, null, "");
  l11.addStation("迪士尼",     0.90, true,
    new String[]{"迪士尼.jpg", "迪士尼 2.jpg"},
    "Waiting hours for a photo, just to stand a little closer to a world of happiness.");

  // Line 13
  l13.addStation("汉中路",    0.14, false, null, "");
  l13.addStation("自然博物馆",0.22, true,
    new String[]{"自然博物馆.jpg"},
    "A school trip photo, holding a version of friendship that never needed explanation.");
  l13.addStation("江宁路",    0.36, false, null, "");
  l13.addStation("新天地",    0.52, true,
    new String[]{"新天地.jpg"},
    "A quiet city walk in Xintiandi, where the day felt just slightly different with someone beside me.");
  l13.addStation("世博大道",  0.80, true,
    new String[]{"世博会.jpg"},
    "A childhood glimpse of a vast world, not fully understood but impossible to forget.");

  lines.add(l1); lines.add(l2); lines.add(l10); lines.add(l11); lines.add(l13);
  for (MetroLine ml : lines) { ml.spawnInitialTrains(1); ml.spawnInitialPassengers(12); }
}

void resolveTransfers() {
  stationIndex.clear();
  for (MetroLine ml : lines)
    for (MetroStation st : ml.stations) {
      if (!stationIndex.containsKey(st.name)) stationIndex.put(st.name, new ArrayList<MetroStation>());
      stationIndex.get(st.name).add(st);
    }
  for (String key : stationIndex.keySet()) {
    ArrayList<MetroStation> g = stationIndex.get(key);
    if (g.size() > 1) for (MetroStation st : g) { st.isTransfer = true; st.transferCount = g.size(); }
  }
  for (String key : stationIndex.keySet()) {
    ArrayList<MetroStation> g = stationIndex.get(key);
    for (MetroStation st : g) {
      st.transferTargets = new ArrayList<MetroStation>();
      for (MetroStation o : g) if (o != st) st.transferTargets.add(o);
    }
  }
}

void layoutBottomLanesY() {
  float startY = bottomPanelY + 44;
  float usable = height - startY - 64;
  float gap    = usable / max(1, lines.size());
  for (int i = 0; i < lines.size(); i++) lines.get(i).bottomY = startY + i * gap;
}

// ═════════════════════════════════════════════════════════════════════════════
//  MetroLine
// ═════════════════════════════════════════════════════════════════════════════
class MetroLine {
  String lineName, pentatonicName;
  color lineColor;
  float baseFreq;
  int displayIndex;
  float bottomY, globalCrowd = 0.55, dispatchRate = 1.0;
  int lastDispatchMs = 0;
  ArrayList<MetroStation> stations   = new ArrayList<MetroStation>();
  ArrayList<Train>        trains     = new ArrayList<Train>();
  ArrayList<PassengerDot> passengers = new ArrayList<PassengerDot>();

  MetroLine(String name, float freq, color col, int idx, String pentName) {
    lineName = name; baseFreq = freq; lineColor = col; displayIndex = idx; pentatonicName = pentName;
  }

  void addStation(String name, float xNorm, boolean mem, String[] imgNames, String cap) {
    stations.add(new MetroStation(name, xNorm, mem, imgNames, cap, this));
  }

  void spawnInitialTrains(int n) {
    for (int i = 0; i < n; i++) trains.add(new Train(this, random(0, max(1, stations.size()-0.01))));
  }
  void spawnInitialPassengers(int n) {
    for (int i = 0; i < n; i++) passengers.add(new PassengerDot(this, random(0, max(1, stations.size()-0.01))));
  }

  void update() {
    int interval = int(15000 / max(0.4, dispatchRate));
    if (millis() - lastDispatchMs > interval && trains.size() < 2) {
      trains.add(new Train(this, random(0, max(1, stations.size()-0.01))));
      lastDispatchMs = millis();
    }
    for (MetroStation st : stations) st.update(globalCrowd);
    for (Train tr : trains) tr.update();
    int target = int(map(globalCrowd, 0, 1, 8, 22));
    while (passengers.size() < target) passengers.add(new PassengerDot(this, random(0, max(1, stations.size()-0.01))));
    while (passengers.size() > target) passengers.remove(passengers.size()-1);
    for (PassengerDot d : passengers) d.update();
  }

  Train heroTrain() {
    if (trains.isEmpty()) trains.add(new Train(this, 0));
    Train best = trains.get(0);
    float bestDist = 9999;
    for (Train tr : trains) {
      float d = abs(tr.progress - stations.size() * 0.5);
      if (d < bestDist) { bestDist = d; best = tr; }
    }
    return best;
  }

  void drawBottom() {
    if (stations.size() < 2) return;
    boolean sel = (lines.indexOf(this) == selectedLineIndex);
    stroke(lineColor, sel ? 180 : 70); strokeWeight(sel ? 5 : 2.5); noFill();
    beginShape();
    for (int i = 0; i < stations.size(); i++) {
      MetroStation st = stations.get(i);
      curveVertex(st.heroX(), bottomY + sin(i * 0.55 + frameCount * 0.01) * (sel ? 2.5 : 1.4));
    }
    endShape();
    stroke(lineColor, sel ? 40 : 20); strokeWeight(sel ? 10 : 7);
    line(leftMargin, bottomY, width - rightMargin, bottomY);
    for (PassengerDot d : passengers) d.draw();
    for (Train tr : trains) tr.drawMini(bottomY, sel ? 1.0 : 0.45);
    for (MetroStation st : stations) st.drawBottomNode();
    noStroke(); fill(255, sel ? 230 : 150);
    textAlign(LEFT, CENTER); textSize(12);
    text(lineName, 18, bottomY);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  MetroStation
// ═════════════════════════════════════════════════════════════════════════════
class MetroStation {
  String   name;
  float    xNorm;
  boolean  isMemory, isTransfer = false;
  int      transferCount = 1;
  String[] memoryImageNames;
  String   memoryCaption;
  MetroLine parentLine;
  ArrayList<MetroStation> transferTargets = new ArrayList<MetroStation>();
  float resonance = 0, flash = 0;
  int   lastTriggerMs = -9999;

  MetroStation(String name, float xNorm, boolean isMemory, String[] imgNames, String cap, MetroLine line) {
    this.name = name; this.xNorm = xNorm; this.isMemory = isMemory;
    this.memoryImageNames = imgNames; this.memoryCaption = cap; this.parentLine = line;
  }

  float heroX()   { return map(xNorm, 0, 1, leftMargin, width - rightMargin); }
  float screenX() { return heroX(); }

  ArrayList<PImage> getMemoryImages() {
    if (!isMemory || memoryImageNames == null) return null;
    ArrayList<PImage> imgs = new ArrayList<PImage>();
    for (String n : memoryImageNames) {
      if (n == null || n.isEmpty()) continue;
      PImage img = loadMemoryImage(n);
      if (img != null) imgs.add(img);
    }
    return imgs.isEmpty() ? null : imgs;
  }

  void update(float crowd) {
    flash     *= 0.96;
    resonance *= 0.992;
    resonance += crowd * 0.002;
    resonance  = constrain(resonance, 0, 1);
  }

  void drawBottomNode() {
    float x = screenX(), y = parentLine.bottomY;
    float r = (isTransfer ? 8 : 5) + (isMemory ? 3 : 0);
    noStroke(); fill(20, 20, 28, 255); ellipse(x, y, 18, 18);
    fill(parentLine.lineColor, 120 + 120 * resonance); ellipse(x, y, r * 2.0, r * 2.0);
    if (isTransfer) {
      stroke(255, 240, 220, 170 * (0.5f + resonance));
      strokeWeight(1.5); noFill();
      ellipse(x, y, 20 + resonance * 16, 20 + resonance * 16);
    }
    if (isMemory) {
      noStroke(); fill(255, 240, 180, 160 + 80 * flash);
      textAlign(CENTER, CENTER); textSize(9); text("★", x, y - r - 7);
    }
    boolean showLabel = (parentLine == lines.get(selectedLineIndex)) || isTransfer || isMemory || hoveredStation == this;
    if (showLabel) {
      fill(240, 240, 248, 170); textAlign(CENTER, BOTTOM); textSize(10); text(name, x, y - 10);
    }
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Train
// ═════════════════════════════════════════════════════════════════════════════
class Train {
  MetroLine    line;
  float        progress, lastProgress, speed = 0.0045, energy = 1.0;
  MetroStation closestStation;

  Train(MetroLine line, float progress) {
    this.line = line; this.progress = progress; this.lastProgress = progress;
  }

  void update() {
    if (line.stations.size() < 2) return;
    float crowd = line.globalCrowd;
    speed = 0.0020 * max(0.6, line.dispatchRate) * (0.7 + crowd * 1.1);
    float prev = progress;
    progress += speed * max(0.9, 60.0 / max(1.0, frameRate));
    boolean wrapped = false;
    if (progress >= line.stations.size()) { progress -= line.stations.size(); wrapped = true; }
    int prevIdx = floor(prev), curIdx = floor(progress);
    if (wrapped) {
      for (int i = prevIdx + 1; i < line.stations.size(); i++) onArriveStation(line.stations.get(i));
      for (int i = 0; i <= curIdx; i++)                        onArriveStation(line.stations.get(i));
    } else if (curIdx != prevIdx) {
      for (int i = prevIdx + 1; i <= curIdx; i++)              onArriveStation(line.stations.get(i));
    }
    closestStation = line.stations.get(curIdx);
    lastProgress = progress;
    energy = lerp(energy, 0.5 + crowd * 0.5, 0.02);
  }

  void onArriveStation(MetroStation st) {
    if (line == lines.get(selectedLineIndex) && !st.isMemory) {
      subtitleText = st.name + (st.isTransfer ? "  ⇄" : "");
      subtitleMs   = millis();
    }

    float amp = 0.28 + line.globalCrowd * 0.12;
    int   dur = 360;

    if (st.isMemory) {
      playChord(line.baseFreq, amp * 0.9, 780);
      playNote(line.baseFreq * 2.0, amp * 0.22, 620);
      st.resonance = min(st.resonance + 0.6, 1.0);
      st.flash     = min(st.flash + 0.5, 1.0);
      if (line == lines.get(selectedLineIndex) && activeMemoryStation == null) activateMemory(st);
    } else if (st.isTransfer) {
      playChord(line.baseFreq, amp * 0.65, 700);
      float p = 0.06 + line.globalCrowd * 0.08 + st.resonance * 0.08;
      if (random(1) < p && st.transferTargets != null && !st.transferTargets.isEmpty()) {
        MetroStation tgt = st.transferTargets.get((int)random(st.transferTargets.size()));
        switchToLine(tgt.parentLine, tgt.name);
      }
    } else {
      if (random(1) < 0.38) playDyad(line.baseFreq, line.baseFreq * 1.5, amp * 0.55, 420);
      else                   playNote(line.baseFreq, amp, dur);
    }
    if (line.globalCrowd > 0.72) playNote(line.baseFreq * 9.0 / 8.0, amp * 0.15, 120);
  }

  void switchToLine(MetroLine newLine, String stationName) {
    int idx = findStationIndex(newLine, stationName);
    if (idx >= 0) { line = newLine; progress = idx + 0.001; lastProgress = progress; }
  }
  int findStationIndex(MetroLine l, String name) {
    for (int i = 0; i < l.stations.size(); i++) if (l.stations.get(i).name.equals(name)) return i;
    return -1;
  }

  void drawMini(float y, float alpha) {
    float x = currentX();
    if (trainHead != null) {
      pushStyle(); imageMode(CENTER);
      tint(line.lineColor, 100 * alpha);
      if (trainHeadFacesRight) image(trainHead, x, y, 30, 20);
      else { pushMatrix(); translate(x, y); scale(-1, 1); image(trainHead, 0, 0, 30, 20); popMatrix(); }
      noTint(); popStyle();
    } else {
      fill(line.lineColor, 100 * alpha); noStroke(); rect(x - 6, y - 4, 12, 8, 3);
    }
  }

  float currentX() {
    int i0 = floor(progress) % line.stations.size();
    int i1 = (i0 + 1) % line.stations.size();
    return lerp(line.stations.get(i0).heroX(), line.stations.get(i1).heroX(), progress - floor(progress));
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  PassengerDot
// ═════════════════════════════════════════════════════════════════════════════
class PassengerDot {
  MetroLine line;
  float progress, speed, seed;

  PassengerDot(MetroLine line, float progress) {
    this.line = line; this.progress = progress;
    seed = random(TWO_PI); speed = random(0.15, 0.55);
  }

  void update() {
    speed = 0.12 + line.globalCrowd * 0.40;
    progress += speed * 0.02;
    if (progress >= line.stations.size()) progress -= line.stations.size();
  }

  void draw() {
    if (line.stations.size() < 2) return;
    int   i0 = floor(progress) % line.stations.size();
    int   i1 = (i0 + 1) % line.stations.size();
    float t  = progress - floor(progress);
    float x  = lerp(line.stations.get(i0).heroX(), line.stations.get(i1).heroX(), t);
    float y  = line.bottomY + sin(frameCount * 0.08 + seed) * 2.0;

    boolean memBoost = (activeMemoryStation != null && activeMemoryStation.parentLine == line && memoryFadeAlpha > 0.1);
    float glow = 28 + 110 * line.globalCrowd;
    float dotR = memBoost ? 11 : 8;

    noStroke();
    if (memBoost) {
      float pulse = 0.6 + 0.4 * sin(frameCount * 0.15 + seed);
      fill(255, 220 * pulse, 120 * pulse, glow * 1.4 * memoryFadeAlpha);
      ellipse(x, y, dotR, dotR);
      fill(255, 245, 200, 90 * memoryFadeAlpha);
      ellipse(x - 1.5, y - 1.5, dotR * 0.45, dotR * 0.45);
    } else {
      fill(red(line.lineColor), green(line.lineColor), blue(line.lineColor), glow);
      ellipse(x, y, dotR, dotR);
      fill(255, 255, 255, 70 + glow * 0.40);
      ellipse(x - 1.1, y - 1.1, 3.5, 3.5);
    }
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  ToneSound
// ═════════════════════════════════════════════════════════════════════════════
class ToneSound {
  SinOsc  osc;
  float   amp;
  int     startMs, durationMs, oscType;
  boolean dead = false;

  ToneSound(float freq, float amp, int durationMs, int oscType) {
    this.amp = amp; this.startMs = millis(); this.durationMs = durationMs; this.oscType = oscType;
    osc = new SinOsc(app);
    osc.freq(freq * random(0.998, 1.002));
    osc.amp(0); osc.play();
  }

  void update() {
    float t = (millis() - startMs) / float(max(1, durationMs));
    float env;
    if      (t < 0.22) env = t / 0.22;
    else if (t < 0.78) env = 1.0;
    else               env = 1.0 - (t - 0.78) / 0.22;
    env = constrain(env, 0, 1);
    osc.amp(amp * env * env * 0.85);
    if (t >= 1.0) { stopTone(); dead = true; }
  }

  void stopTone() { if (osc != null) { osc.stop(); osc = null; } }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Slider
// ═════════════════════════════════════════════════════════════════════════════
class Slider {
  float x, y, w, h, value, minValue, maxValue;
  boolean dragging = false;

  Slider(float x, float y, float w, float h, float val, float mn, float mx) {
    this.x=x; this.y=y; this.w=w; this.h=h; value=val; minValue=mn; maxValue=mx;
  }
  void draw() {
    noStroke(); fill(255,255,255,35); rect(x,y,w,h,10);
    float k = map(value,minValue,maxValue,0,1);
    fill(255,255,255,90); rect(x,y,w*k,h,10);
    fill(255); ellipse(x+w*k, y+h*0.5, 20, 20);
  }
  void pressed(float mx,float my) {
    if(mx>=x&&mx<=x+w&&my>=y-6&&my<=y+h+6){dragging=true;setFromMouse(mx);}
  }
  void drag(float mx,float my){if(dragging)setFromMouse(mx);}
  void released(){dragging=false;}
  void setFromMouse(float mx){value=lerp(minValue,maxValue,constrain((mx-x)/w,0,1));}
}
