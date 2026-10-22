import processing.sound.*;

import java.util.*;
import java.io.File;

// =====================================================
// Urban Groove Skyline — Winamp Textured + Hover Audio
// =====================================================

Table table;
ArrayList<Building> buildings = new ArrayList<Building>();
final int TOP_N = 20;

TextureManager texManager;
PFont uiFont;

float reveal = 0;
float groundY;
boolean dataReady = false;
int hoveredIndex = -1;
int previousHoveredIndex = -2;

float minPop = 999, maxPop = -999;
float minDur = 999999, maxDur = -999999;
float minTempo = 9999, maxTempo = -9999;
float minLoud = 999, maxLoud = -999;
float minEnergy = 999, maxEnergy = -999;

SoundFile currentSound;
String currentSoundKey = "";
String currentSoundName = "";

boolean audioReady = true;

float currentAmp = 0.0;
float targetAmp = 0.0;
float fadeStep = 0.03;

int playStartTime = 0;
int playDuration = 10000;
int audioState = 0;   // 0 idle, 1 fade-in, 2 playing, 3 fade-out

Building pendingStart = null;


HashMap<String, String> soundLookup = new HashMap<String, String>();

void setup() {
  size(1600, 900, P2D);
  smooth(8);

  surface.setTitle("URBAN GROOVE SKYLINE — WINAMP TEXTURED + AUDIO");

  uiFont = createFont("Arial", 14, true);
  textFont(uiFont);

  texManager = new TextureManager();

  randomSeed(7);
  noiseSeed(7);

  groundY = height * 0.82;

  audioReady = true;
println("Processing Sound library enabled.");

  buildSoundLookup();
  loadAndPrepareData();
}

void draw() {
  drawSkyGradient();
  drawStars();
  drawAtmosphere();

  if (!dataReady) {
    fill(255);
    textAlign(CENTER, CENTER);
    textSize(18);
    text("Loading dataset...", width/2, height/2);
    return;
  }

  drawGround();

  reveal = min(1, reveal + 0.0075);

  hoveredIndex = -1;
  for (int i = 0; i < buildings.size(); i++) {
    if (buildings.get(i).isHover(mouseX, mouseY)) hoveredIndex = i;
  }

  for (int i = 0; i < buildings.size(); i++) {
    Building b = buildings.get(i);
    float localReveal = constrain(map(reveal, (float)i / buildings.size(), (float)(i + 1) / buildings.size(), 0, 1), 0, 1);
    b.updateParticles();
    b.display(localReveal, i == hoveredIndex);
  }

  if (hoveredIndex >= 0) buildings.get(hoveredIndex).drawTooltip();

  drawTitleBlock();

  handleAudioHover();
  updateAudio();

  previousHoveredIndex = hoveredIndex;
}

// =====================================================
// Data loading
// =====================================================

void loadAndPrepareData() {
  table = loadTable("high_popularity_spotify_data.csv", "header");
  if (table == null) {
    println("CSV not found!");
    return;
  }

  HashSet<String> seen = new HashSet<String>();
  ArrayList<Building> temp = new ArrayList<Building>();

  for (TableRow row : table.rows()) {
    String id = safeString(row, "track_id");
    String dateStr = safeString(row, "track_album_release_date");

    if (id == null || id.length() == 0) continue;
    if (dateStr == null || dateStr.length() < 4) continue;
    if (seen.contains(id)) continue;
    seen.add(id);

    Building b = new Building(row);
    if (b.valid) temp.add(b);
  }

  Collections.sort(temp, new Comparator<Building>() {
    public int compare(Building a, Building b) {
      int c = Float.compare(b.popularity, a.popularity);
      if (c != 0) return c;
      c = Integer.compare(a.releaseKey, b.releaseKey);
      if (c != 0) return c;
      return a.trackName.compareToIgnoreCase(b.trackName);
    }
  });

  buildings.clear();
  for (int i = 0; i < min(TOP_N, temp.size()); i++) {
    buildings.add(temp.get(i));
  }

  Collections.sort(buildings, new Comparator<Building>() {
    public int compare(Building a, Building b) {
      int c = Integer.compare(a.releaseKey, b.releaseKey);
      if (c != 0) return c;
      return Float.compare(b.popularity, a.popularity);
    }
  });

  computeRanges();
  layoutBuildings();

  dataReady = true;
  println("Loaded " + buildings.size() + " songs.");
}

void computeRanges() {
  if (buildings.size() == 0) return;

  for (Building b : buildings) {
    minPop = min(minPop, b.popularity); maxPop = max(maxPop, b.popularity);
    minDur = min(minDur, b.durationMs);   maxDur = max(maxDur, b.durationMs);
    minTempo = min(minTempo, b.tempo);    maxTempo = max(maxTempo, b.tempo);
    minLoud = min(minLoud, b.loudness);   maxLoud = max(maxLoud, b.loudness);
    minEnergy = min(minEnergy, b.energy); maxEnergy = max(maxEnergy, b.energy);
  }

  if (abs(maxPop - minPop) < 0.001) maxPop = minPop + 1;
  if (abs(maxDur - minDur) < 0.001) maxDur = minDur + 1;
  if (abs(maxTempo - minTempo) < 0.001) maxTempo = minTempo + 1;
  if (abs(maxLoud - minLoud) < 0.001) maxLoud = minLoud + 1;
  if (abs(maxEnergy - minEnergy) < 0.001) maxEnergy = minEnergy + 1;
}

void layoutBuildings() {
  float leftMargin = width * 0.08;
  float rightMargin = width * 0.08;
  float usableW = width - leftMargin - rightMargin;

  float totalGap = 0;
  for (int i = 1; i < buildings.size(); i++) {
    if (!buildings.get(i).getEra().equals(buildings.get(i - 1).getEra())) {
      totalGap += 40;
    }
  }

  float slotW = (usableW - totalGap) / buildings.size();
  float currentX = leftMargin;

  for (int i = 0; i < buildings.size(); i++) {
    Building b = buildings.get(i);
    if (i > 0 && !b.getEra().equals(buildings.get(i - 1).getEra())) currentX += 40;
    float centerX = currentX + slotW * 0.5;
    b.layout(i, centerX, groundY, slotW);
    currentX += slotW;
  }
}

// =====================================================
// Audio control
// =====================================================

void buildSoundLookup() {
  File soundDir = new File(dataPath("sound"));
  if (!soundDir.exists() || !soundDir.isDirectory()) {
    println("Sound folder not found: data/sound");
    return;
  }

  File[] files = soundDir.listFiles();
  if (files == null) return;

  for (File f : files) {
    if (!f.isFile()) continue;
    String name = f.getName();
    if (!name.toLowerCase().endsWith(".mp3")) continue;

    String stem = name.substring(0, name.length() - 4);
    soundLookup.put(sanitizeKey(stem), name);
  }

  println("Indexed audio files: " + soundLookup.size());
}

String sanitizeKey(String s) {
  if (s == null) return "";
  s = s.toLowerCase().trim();
  s = s.replace("’", "");
  s = s.replace("'", "");
  s = s.replaceAll("[^a-z0-9]+", "");
  return s;
}

void handleAudioHover() {
  if (!audioReady) return;

  if (hoveredIndex != previousHoveredIndex) {
    if (hoveredIndex < 0) {
      requestStop();
    } else {
      Building b = buildings.get(hoveredIndex);

      if (currentSound == null) {
        startTrack(b);
      } else {
        String newKey = sanitizeKey(b.trackName);
        if (!newKey.equals(currentSoundKey)) {
          requestSwitchTo(b);
        }
      }
    }
  }

  if (currentSound != null && audioState != 3) {
    if (millis() - playStartTime >= playDuration) {
      requestStop();
    }
  }
}

void updateAudio() {
  if (currentSound == null) return;

  currentAmp = lerp(currentAmp, targetAmp, 0.10);
  currentSound.amp(currentAmp);

  if (audioState == 3 && abs(currentAmp - 0.0) < 0.02) {
    closeCurrentSound();

    if (pendingStart != null) {
      Building next = pendingStart;
      pendingStart = null;
      startTrack(next);
    } else {
      audioState = 0;
    }
  }

  if (audioState == 1 && abs(currentAmp - 0.55) < 0.03) {
    audioState = 2;
  }
}

void startTrack(Building b) {
  if (!audioReady || b == null) return;

  String path = resolveAudioPath(b.trackName);
  if (path == null) return;

  closeCurrentSound();

  try {
    currentSound = new SoundFile(this, path);
    currentSound.amp(0.0);
    currentSound.play();

    currentSoundKey = sanitizeKey(b.trackName);
    currentSoundName = b.trackName;

    currentAmp = 0.0;
    targetAmp = 0.55;   // 音量适中
    audioState = 1;
    playStartTime = millis();

    println("Playing: " + currentSoundName);
  } catch (Exception e) {
    println("Could not play audio for: " + b.trackName);
    currentSound = null;
  }
}

void requestStop() {
  if (currentSound == null) return;
  pendingStart = null;
  targetAmp = 0.0;
  audioState = 3;
}

void requestSwitchTo(Building b) {
  if (b == null) return;
  pendingStart = b;
  targetAmp = 0.0;
  audioState = 3;
}

void closeCurrentSound() {
  if (currentSound == null) return;
  try {
    currentSound.stop();
  } catch (Exception e) {
  }
  currentSound = null;
  currentSoundKey = "";
  currentSoundName = "";
  currentAmp = 0.0;
  targetAmp = 0.0;
  audioState = 0;
}

String resolveAudioPath(String trackName) {
  String key = sanitizeKey(trackName);
  String fileName = soundLookup.get(key);

  if (fileName == null) {
    println("Audio file not found for track: " + trackName + " | key=" + key);
    return null;
  }

  return dataPath("sound/" + fileName);
}

// =====================================================
// Background
// =====================================================

void drawSkyGradient() {
  for (int y = 0; y < height; y++) {
    float t = map(y, 0, height, 0, 1);
    color c1 = color(5, 8, 20);
    color c2 = color(30, 15, 45);
    color c3 = color(2, 2, 8);

    color c = (t < 0.6) ? lerpColor(c1, c2, t/0.6) : lerpColor(c2, c3, (t - 0.6)/0.4);
    stroke(c);
    line(0, y, width, y);
  }
}

void drawStars() {
  randomSeed(7);
  noStroke();
  for (int i = 0; i < 150; i++) {
    float sx = random(width);
    float sy = random(height * 0.5);
    float tw = map(noise(i * 0.1, frameCount * 0.01), 0, 1, 60, 200);
    fill(255, tw);
    ellipse(sx, sy, 1.2, 1.2);
  }
}

void drawAtmosphere() {
  noStroke();
  for (int i = 0; i < 12; i++) {
    float a = map(i, 0, 11, 25, 0);
    fill(150, 100, 220, a);
    ellipse(width * 0.5, height * 0.15, width * (0.8 + i * 0.1), height * 0.35);
  }
}

void drawGround() {
  noStroke();
  fill(3, 5, 12);
  rect(0, groundY, width, height - groundY);

  for (int i = 0; i < 30; i++) {
    float y = groundY - i * 2;
    fill(100, 70, 180, 15 - i * 0.4);
    rect(0, y, width, 2);
  }

  stroke(255, 30);
  line(0, groundY, width, groundY);
}

void drawTitleBlock() {
  fill(255);
  textAlign(LEFT, TOP);
  textSize(22);
  text("URBAN GROOVE SKYLINE", 28, 22);

  textSize(12);
  fill(230, 220, 240, 190);
  text("Hover a building to play 10s clip", 28, 50);
  fill(220, 220, 235, 140);
  text("Timeline left → right by release date; Building Height → by popularity", 28, 68);
}

// =====================================================
// General helpers
// =====================================================

String safeString(TableRow row, String col) {
  try {
    String s = row.getString(col);
    return s == null ? "" : trim(s);
  } catch (Exception e) {
    return "";
  }
}

String normalizeGenre(String g) {
  if (g == null) return "default";
  g = g.toLowerCase().trim();
  g = g.replace("_", "-");
  g = g.replace(" ", "-");

  if (g.contains("hip-hop") || g.contains("hiphop") || g.contains("rap")) return "hip-hop";
  if (g.contains("electronic") || g.contains("edm")) return "electronic";
  if (g.contains("classical")) return "classical";
  if (g.contains("jazz")) return "jazz";
  if (g.contains("pop")) return "pop";

  return g;
}

int parseDateKey(String d) {
  if (d == null || d.length() < 4) return 0;
  String[] parts = split(d, '-');
  if (parts == null || parts.length < 3) {
    try {
      return int(trim(d)) * 10000;
    } catch (Exception e) {
      return 0;
    }
  }
  try {
    return int(parts[0]) * 10000 + int(parts[1]) * 100 + int(parts[2]);
  } catch (Exception e) {
    return 0;
  }
}

int parseYear(String d) {
  if (d == null || d.length() < 4) return 0;
  try {
    return int(split(d, '-')[0]);
  } catch (Exception e) {
    return 0;
  }
}

float easeOutCubic(float t) {
  t = constrain(t, 0, 1);
  return 1 - pow(1 - t, 3);
}

// =====================================================
// Texture manager
// =====================================================

class TextureManager {
  private HashMap<String, PImage> textures;

  TextureManager() {
    textures = new HashMap<String, PImage>();
  }

  PImage getTexture(String genre) {
    if (genre == null) genre = "default";
    String key = normalizeGenre(genre);

    if (textures.containsKey(key)) return textures.get(key);

    PImage img = null;
    String filename = null;

    if (key.equals("classical")) filename = "classical.bmp";
    else if (key.equals("electronic") || key.equals("pop")) filename = "edm.bmp";
    else if (key.equals("jazz")) filename = "jazz.bmp";
    else if (key.equals("hip-hop")) filename = "rap.bmp";
    else filename = "edm.bmp";

    img = loadImage("winamp/" + filename);

    if (img == null) println("Failed to load texture: winamp/" + filename + " for genre = " + key);
    else println("Loaded texture: winamp/" + filename + " for genre = " + key);

    textures.put(key, img);
    return img;
  }
}

// =====================================================
// Building class
// =====================================================

class Building {
  boolean valid = true;

  String trackId, trackName, artist, album, genre, dateStr;
  float popularity, durationMs, energy, loudness, valence, acousticness, danceability, liveness, speechiness, tempo;
  int mode, key, releaseKey, releaseYear;

  float x, baseY, slotW, bodyW, bodyH, seed;

  color baseCol, accentCol, windowCol, glowCol, shadowCol;

  ArrayList<Particle> particles = new ArrayList<Particle>();
  boolean particlesGenerated = false;
  float[] spectrumVals;

  PImage genreTexture;
  boolean useTexture = false;

  Building(TableRow row) {
    try {
      trackId = safeString(row, "track_id");
      trackName = safeString(row, "track_name");
      artist = safeString(row, "track_artist");
      album = safeString(row, "track_album_name");
      genre = normalizeGenre(safeString(row, "playlist_genre"));
      dateStr = safeString(row, "track_album_release_date");

      popularity = row.getFloat("track_popularity");
      durationMs = row.getFloat("duration_ms");
      energy = row.getFloat("energy");
      loudness = row.getFloat("loudness");
      valence = row.getFloat("valence");
      acousticness = row.getFloat("acousticness");
      danceability = row.getFloat("danceability");
      liveness = row.getFloat("liveness");
      speechiness = row.getFloat("speechiness");
      tempo = row.getFloat("tempo");

      mode = row.getInt("mode");
      key = row.getInt("key");

      releaseKey = parseDateKey(dateStr);
      releaseYear = parseYear(dateStr);

      seed = random(1000);

      spectrumVals = new float[12];
      for (int i = 0; i < 12; i++) spectrumVals[i] = random(0.3, 1.0);

      updatePalette();
      generateParticles();

      genreTexture = texManager.getTexture(genre);
      useTexture = (genreTexture != null);
    } catch (Exception e) {
      valid = false;
    }
  }

  String getEra() {
    if (releaseYear >= 2020) return "2020s";
    if (releaseYear >= 2010) return "2010s";
    return "2000s";
  }

  void updatePalette() {
    float valN = constrain(valence, 0, 1);
    color moodBase;

    if (valN > 0.65) {
      moodBase = color(255, 190, 90);
    } else if (valN < 0.35) {
      moodBase = color(90, 130, 240);
    } else {
      moodBase = color(130, 210, 180);
    }

    String g = genre == null ? "" : genre;

    if (g.equals("classical")) {
      moodBase = lerpColor(moodBase, color(210, 205, 190), 0.65);
    } else if (g.equals("electronic") || g.equals("pop")) {
      moodBase = lerpColor(moodBase, color(120, 180, 255), 0.55);
    } else if (g.equals("jazz")) {
      moodBase = lerpColor(moodBase, color(210, 160, 90), 0.55);
    } else if (g.equals("hip-hop")) {
      moodBase = lerpColor(moodBase, color(110, 100, 130), 0.55);
    }

    if (releaseYear < 2010) {
      moodBase = lerpColor(moodBase, color(185, 150, 120), 0.25);
    } else if (releaseYear >= 2020) {
      moodBase = lerpColor(moodBase, color(140, 210, 255), 0.18);
    }

    baseCol = moodBase;
    accentCol = lerpColor(baseCol, color(255, 255, 255), 0.35);
    windowCol = lerpColor(baseCol, color(255, 245, 200), 0.65);

    if (valN > 0.6) {
      glowCol = color(255, 200, 100, 200);
    } else if (valN < 0.4) {
      glowCol = color(150, 200, 255, 200);
    } else {
      glowCol = color(200, 255, 200, 200);
    }

    shadowCol = color(0, 0, 0, 100);
  }

  void layout(int idx, float centerX, float gY, float slotWidth) {
    baseY = gY;
    slotW = slotWidth;
    x = centerX;

    float durN = norm(durationMs, minDur, maxDur);
    float popN = norm(popularity, minPop, maxPop);

    bodyW = slotW * lerp(0.68, 0.95, durN);
    bodyH = lerp(height * 0.25, height * 0.58, pow(popN, 0.9));
  }

  boolean isHover(float mx, float my) {
    float halfW = bodyW * 0.5;
    float topY = baseY - bodyH - 80;
    return (mx >= x - halfW && mx <= x + halfW && my >= topY && my <= baseY + 8);
  }

  void generateParticles() {
    if (particlesGenerated) return;

    int count = int(map(energy, 0, 1, 6, 25));
    for (int i = 0; i < count; i++) {
      particles.add(new Particle(this, random(TWO_PI), random(0.8, 2.0)));
    }
    particlesGenerated = true;
  }

  void updateParticles() {
    for (Particle p : particles) p.update();
  }

  void display(float revealFactor, boolean hover) {
    float ease = easeOutCubic(revealFactor);
    float visibleH = bodyH * ease;
    if (visibleH < 2) return;

    float energyN = norm(energy, minEnergy, maxEnergy);
    float loudN = norm(loudness, minLoud, maxLoud);
    float popN = norm(popularity, minPop, maxPop);
    float valN = constrain(valence, 0, 1);
    float danceN = constrain(danceability, 0, 1);
    float acN = constrain(acousticness, 0, 1);
    float speechN = constrain(speechiness, 0, 1);
    String era = getEra();

    float shakeX = 0;
    float shakeY = 0;
    if (energyN > 0.6) {
      shakeX = map(energyN, 0.6, 1, 0, 6) * sin(frameCount * 0.3 + seed);
      shakeY = map(energyN, 0.6, 1, 0, 4) * cos(frameCount * 0.25 + seed * 2);
    }

    float tilt = map(danceN, 0, 1, -0.06, 0.06) * (1 + energyN);
    float breath = 1.0 + sin(frameCount * map(tempo, 60, 200, 0.03, 0.12) + seed) * (0.02 + energyN * 0.05);

    float h = visibleH * breath;
    float yTop = baseY - h + shakeY;
    float left = x - bodyW * 0.5 + shakeX;

    pushMatrix();
    translate(x, baseY);
    rotate(tilt);
    translate(-x, -baseY);

    // glow
    float glowAlpha = (50 + 200 * loudN) * (hover ? 1.8 : 1);
    noStroke();
    fill(red(glowCol), green(glowCol), blue(glowCol), 30 + glowAlpha * 0.15);
    ellipse(x, yTop + h * 0.45, bodyW * (1.4 + energyN * 0.7), h * 1.1);

    // shadow
    fill(0, 80);
    rect(left + 10, yTop + 10, bodyW, h, 12);

    // body
    drawCore(left, yTop, h, era);

    if (acN > 0.5) {
      stroke(0, 0, 0, 30 + acN * 50);
      strokeWeight(1.5);
      for (float py = yTop; py < yTop + h; py += 8) {
        line(left + 2, py, left + bodyW - 2, py + (acN - 0.5) * 4);
      }
    }

    if (speechN > 0.25) {
      fill(255, 120 + speechN * 100);
      textSize(8 + speechN * 6);
      for (int i = 0; i < 5; i++) {
        float tx = left + bodyW * 0.1 + random(bodyW * 0.8);
        float ty = yTop + h * 0.2 + random(h * 0.6);
        text("♪", tx, ty);
      }
    }

    drawSpectrumBars(left, yTop, bodyW, h, era);
    drawWaveformRoof(left, yTop, bodyW, h * 0.15, danceN, valN, era);
    drawWindows(left, yTop, bodyW, h, loudN, valN);
    drawRoof(left, yTop, bodyW, h * 0.15, valN, popN);

    if (popN > 0.8) {
      stroke(255, 220, 100, 200);
      strokeWeight(3);
      line(x, yTop - 10, x, yTop - 35);
      fill(255, 200, 50, 200);
      noStroke();
      ellipse(x, yTop - 38, 8, 8);
    }

    noFill();
    stroke(red(glowCol), green(glowCol), blue(glowCol), hover ? 180 : 80);
    strokeWeight(2.5);
    rect(left, yTop, bodyW, h, era.equals("2020s") ? 15 : (era.equals("2010s") ? 18 : 0));

    if (hover) {
      stroke(255, 255, 200, 150);
      strokeWeight(3);
      rect(left - 5, yTop - 5, bodyW + 10, h + 10, 20);
    }

    popMatrix();

    for (Particle p : particles) p.display(baseCol, era);
  }

  void drawCore(float left, float yTop, float h, String era) {
    fill(red(baseCol), green(baseCol), blue(baseCol), 220);
    if (era.equals("2020s")) {
      rect(left, yTop, bodyW, h, 15);
    } else if (era.equals("2010s")) {
      rect(left, yTop, bodyW, h, 18);
    } else {
      rect(left, yTop, bodyW, h);
    }

    noStroke();
    for (int i = 0; i < 4; i++) {
      float yy = yTop + h * (0.15 + i * 0.18);
      fill(255, 255, 255, 10 + i * 6);
      rect(left + bodyW * 0.05, yy, bodyW * 0.90, h * 0.04, 2);
    }

    if (useTexture && genreTexture != null) {
      drawTextureOverlay(left, yTop, bodyW, h);
    }

    drawTextureAccents(left, yTop, h);
  }

  void drawTextureOverlay(float left, float yTop, float w, float h) {
    if (genreTexture == null) return;

    pushStyle();
    imageMode(CORNER);
    noStroke();

    float inset = w * 0.08;

    tint(255, 95);
    blendMode(SCREEN);
    image(genreTexture, left + inset, yTop + h * 0.18, w - inset * 2, h * 0.34);

    tint(255, 65);
    image(genreTexture, left + inset, yTop + h * 0.56, w - inset * 2, h * 0.14);

    tint(255, 45);
    image(genreTexture, left + inset * 0.7, yTop + h * 0.05, w - inset * 1.4, h * 0.10);

    noTint();
    blendMode(BLEND);
    popStyle();
  }

  void drawTextureAccents(float left, float yTop, float h) {
    if (!useTexture || genreTexture == null) return;

    pushStyle();
    blendMode(SCREEN);
    tint(255, 50);

    float bandH = h * 0.08;
    image(genreTexture, left, yTop + h * 0.42, bodyW, bandH);

    float capH = h * 0.05;
    image(genreTexture, left, yTop - capH, bodyW, capH);

    noTint();
    blendMode(BLEND);
    popStyle();
  }

  void drawSpectrumBars(float left, float yTop, float w, float h, String era) {
    float energyN = norm(energy, minEnergy, maxEnergy);
    float loudN = norm(loudness, minLoud, maxLoud);

    int bars = int(map(energyN, 0, 1, 5, 16));
    float barW = w / (bars * 1.8);
    float startX = left + (w - bars * barW * 1.4) / 2;

    for (int i = 0; i < bars; i++) {
      float val = spectrumVals[i % spectrumVals.length];
      float barH = map(val, 0.3, 1, h * 0.1, h * 0.7);
      float pulse = sin(frameCount * 0.1 + i) * 0.1;
      barH *= (1 + pulse);

      float bx = startX + i * barW * 1.4;
      float by = yTop + h - barH;

      noStroke();

      if (era.equals("2020s")) {
        fill(red(glowCol), green(glowCol), blue(glowCol), 180 + 70 * loudN);
        rect(bx, by, barW, barH, 3);
        fill(255, 255, 255, 60);
        rect(bx - 1, by - 1, barW + 2, barH + 2, 3);
      } else if (era.equals("2010s")) {
        fill(255, 255, 255, 200);
        rect(bx, by, barW, barH, 5);
      } else {
        fill(0, 0, 0, 120);
        rect(bx, by, barW, barH);
        fill(255, 255, 255, 200);
        rect(bx + 2, by + 2, barW - 4, barH - 4);
      }
    }
  }

  void drawWaveformRoof(float left, float yTop, float w, float roofH, float danceN, float valN, String era) {
    float amp = map(danceN, 0, 1, 5, 20);
    float freq = map(valN, 0, 1, 2, 5);

    noFill();
    strokeWeight(era.equals("2020s") ? 2.5 : 3.5);
    stroke(accentCol, 220);

    beginShape();
    for (float px = left; px <= left + w; px += 5) {
      float t = map(px, left, left + w, 0, TWO_PI * freq);
      float waveY = yTop - abs(sin(t + frameCount * 0.02)) * amp;
      vertex(px, waveY);
    }
    endShape();
  }

  void drawWindows(float left, float yTop, float w, float h, float loudN, float valN) {
    float energyN = norm(energy, minEnergy, maxEnergy);

    int cols = max(2, int(w / 20));
    int rows = max(3, int(map(energyN, 0, 1, 3, 12)));

    float pad = w * 0.08;
    float cellW = (w - 2 * pad) / cols;
    float cellH = (h * 0.7) / rows;

    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        float wx = left + pad + c * cellW + cellW * 0.1;
        float wy = yTop + h * 0.15 + r * cellH + cellH * 0.1;
        float ww = cellW * 0.7;
        float wh = cellH * 0.7;

        float lit = noise(seed + c * 0.3, r * 0.2, frameCount * 0.02);

        if (lit > 0.4) {
          float bright = map(loudN, 0, 1, 100, 255) * (0.7 + 0.5 * sin(frameCount * 0.1 + seed));
          fill(red(windowCol), green(windowCol), blue(windowCol), bright);
          rect(wx, wy, ww, wh, 3);
        } else {
          fill(10, 15, 25, 150);
          rect(wx, wy, ww, wh, 3);
        }
      }
    }
  }

  void drawRoof(float left, float yTop, float w, float roofH, float valN, float popN) {
    pushStyle();
    noStroke();

    color roofCol = lerpColor(baseCol, accentCol, 0.3);
    float roofHeight = roofH * (0.8 + popN * 0.5);

    if (valN > 0.7) {
      fill(roofCol);
      float stepW = w * 0.2;
      float stepH = roofHeight * 0.3;

      rect(left, yTop - roofHeight, w, roofHeight);
      fill(lerpColor(roofCol, accentCol, 0.2));
      rect(left + stepW, yTop - roofHeight - stepH, w - 2 * stepW, stepH);
      fill(lerpColor(roofCol, accentCol, 0.4));
      rect(left + stepW * 1.8, yTop - roofHeight - stepH * 2, w - 3.6 * stepW, stepH * 0.8);

      stroke(red(glowCol), green(glowCol), blue(glowCol), 150);
      strokeWeight(2);
      line(left + w * 0.3, yTop - roofHeight - stepH * 2, left + w * 0.7, yTop - roofHeight - stepH * 2);
    } else if (valN < 0.3) {
      fill(roofCol);
      triangle(left, yTop, left + w, yTop, left + w / 2, yTop - roofHeight * 1.5);

      stroke(red(accentCol), green(accentCol), blue(accentCol), 200);
      strokeWeight(3);
      line(left + w / 2, yTop - roofHeight * 1.5, left + w / 2, yTop - roofHeight * 1.9);

      noStroke();
      fill(accentCol);
      ellipse(left + w / 2, yTop - roofHeight * 1.95, 6, 6);
    } else {
      fill(roofCol);
      rect(left, yTop - roofHeight, w, roofHeight);

      fill(lerpColor(roofCol, accentCol, 0.3));
      int crenels = int(map(popN, 0, 1, 3, 7));
      float crenelW = w / (crenels * 2 - 1);

      for (int i = 0; i < crenels; i++) {
        float cx = left + i * crenelW * 2;
        rect(cx, yTop - roofHeight - 6, crenelW, 6);
      }

      stroke(red(glowCol), green(glowCol), blue(glowCol), 100);
      strokeWeight(2);
      line(left + 2, yTop - roofHeight, left + w - 2, yTop - roofHeight);
    }

    if (popN > 0.9) {
      stroke(red(accentCol), green(accentCol), blue(accentCol), 220);
      strokeWeight(2.5);

      float tipX = left + w / 2;
      float tipBaseY = (valN < 0.3) ? yTop - roofHeight * 1.5 : yTop - roofHeight;
      line(tipX, tipBaseY, tipX, tipBaseY - 25);

      noStroke();
      fill(255, 200, 50);
      ellipse(tipX, tipBaseY - 27, 5, 5);
    }

    popStyle();
  }

  void drawTooltip() {
    pushStyle();

    String info1 = trackName;
    String info2 = artist;
    String info3 = "Popularity " + nf(popularity, 0, 0) + "  |  " + genre + "  |  " + releaseYear;
    String info4 = "Energy " + nf(energy, 0, 2) + "  Loud " + nf(loudness, 0, 2);

    textSize(13);
    float boxW = max(textWidth(info1), max(textWidth(info2), max(textWidth(info3), textWidth(info4)))) + 20;
    float boxH = 72;

    float bx = mouseX + 18;
    float by = mouseY + 18;

    if (bx + boxW > width) bx = mouseX - boxW - 18;
    if (by + boxH > height) by = mouseY - boxH - 18;

    fill(10, 15, 25, 230);
    noStroke();
    rect(bx, by, boxW, boxH, 10);

    stroke(255, 60);
    noFill();
    rect(bx, by, boxW, boxH, 10);

    fill(255);
    textAlign(LEFT, TOP);
    text(info1, bx + 10, by + 8);

    fill(230, 220, 240);
    text(info2, bx + 10, by + 25);

    fill(210, 220, 235);
    text(info3, bx + 10, by + 42);

    fill(180, 200, 230);
    text(info4, bx + 10, by + 57);

    popStyle();
  }
}

// =====================================================
// Particle class
// =====================================================

class Particle {
  Building parent;
  float angle, speed, radius, size;

  Particle(Building b, float ang, float spd) {
    parent = b;
    angle = ang;
    speed = spd * 0.015;
    radius = random(40, 90);
    size = random(3, 8);
  }

  void update() {
    angle += speed * (0.8 + parent.energy * 0.5);
    float loudF = map(parent.loudness, -15, 0, 0.7, 1.5);
    radius = 50 * loudF + sin(frameCount * 0.05 + angle) * 10;
  }

  void display(color c, String era) {
    float px = parent.x + cos(angle) * radius;
    float py = parent.baseY - parent.bodyH * 0.5 + sin(angle) * radius * 0.5;

    noStroke();

    if (era.equals("2020s")) {
      fill(red(c), green(c), blue(c), 200);
      ellipse(px, py, size, size);
      fill(255, 255, 255, 120);
      ellipse(px - 1, py - 1, size * 0.6, size * 0.6);
    } else if (era.equals("2010s")) {
      fill(255, 255, 255, 220);
      rect(px, py, size, size, 3);
    } else {
      fill(red(c), green(c), blue(c), 220);
      rect(px, py, size, size);
      fill(0, 0, 0, 80);
      rect(px + 1, py + 1, size - 2, size - 2);
    }
  }
}
