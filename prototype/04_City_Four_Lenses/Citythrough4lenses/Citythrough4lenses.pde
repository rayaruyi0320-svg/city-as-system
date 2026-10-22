import processing.sound.*;

PImage img;
String imagePath = "City2.jpg";

ArrayList<Particle> particles = new ArrayList<Particle>();
int TARGET_PARTICLES = 25000;  // Desired number of particles

float stressVal = 0.0;
float energyVal = 0.0;
float orderVal  = 0.0;
float warmthVal = 0.0;

float t = 0;

// Reusable vectors to avoid per-frame allocation
PVector centerVec = new PVector();
PVector fromCenter = new PVector();
PVector toHome = new PVector();
PVector acc = new PVector();

//AUDIO ENGINE
SinOsc[] oscillators = new SinOsc[4];
LowPass[] filters = new LowPass[4];
float[] baseFreqs = {110.0, 220.0, 165.0, 330.0}; // subtle, dissonant-free intervals
boolean audioMuted = false;

void setup() {
  size(1000, 800, P2D);
  colorMode(HSB, 360, 100, 100, 100);
  smooth();

  // Initialize audio
  initAudio();

  img = loadImage(imagePath);
  if (img == null) {
    println("Image not found. Generating procedural fallback texture.");
    img = createImage(width, height, RGB);
    generateFallbackImage();
  } else {
    // Scale down large images to maintain performance
    img = resizeImageToFit(img, 1200);
  }

  initParticlesFromImage();
}

void initAudio() {
  for (int i = 0; i < 4; i++) {
    // Create sine wave oscillator
    oscillators[i] = new SinOsc(this);
    oscillators[i].freq(baseFreqs[i]);
    oscillators[i].amp(0.0); // start silent

    // Create low-pass filter for each channel
    filters[i] = new LowPass(this);
    filters[i].freq(400); // initial cutoff

    // Patch: oscillator -> filter -> output
    oscillators[i].play();
    filters[i].process(oscillators[i]);
  }
}

// Scale image proportionally, limiting the longest edge
PImage resizeImageToFit(PImage source, int maxSize) {
  int w = source.width;
  int h = source.height;
  float scale = min(float(maxSize) / w, float(maxSize) / h);
  if (scale >= 1.0) return source;
  int newW = int(w * scale);
  int newH = int(h * scale);
  PImage resized = createImage(newW, newH, RGB);
  resized.copy(source, 0, 0, w, h, 0, 0, newW, newH);
  return resized;
}

void initParticlesFromImage() {
  particles.clear();
  img.loadPixels();

  // Calculate step size based on target particle count
  int totalPixels = img.width * img.height;
  int step = max(1, int(sqrt(totalPixels / float(TARGET_PARTICLES))));

  // Compute draw area (centered)
  float scale = min(float(width) / img.width, float(height) / img.height);
  int drawW = int(img.width * scale);
  int drawH = int(img.height * scale);
  int offsetX = (width - drawW) / 2;
  int offsetY = (height - drawH) / 2;

  for (int y = 0; y < img.height; y += step) {
    for (int x = 0; x < img.width; x += step) {
      int loc = x + y * img.width;
      color c = img.pixels[loc];
      float posX = offsetX + x * scale;
      float posY = offsetY + y * scale;
      particles.add(new Particle(posX, posY, c));
    }
  }
  println("Particle count: " + particles.size());
}

void generateFallbackImage() {
  img.loadPixels();
  for (int y = 0; y < img.height; y++) {
    for (int x = 0; x < img.width; x++) {
      float h = noise(x * 0.005, y * 0.005) * 360;
      float s = noise(x * 0.01 + 100, y * 0.01 + 100) * 100;
      float b = noise(x * 0.02 + 200, y * 0.02 + 200) * 100;
      img.pixels[y * img.width + x] = color(h, s, b);
    }
  }
  img.updatePixels();
}

void draw() {
  updateParametersFromMouse();
  updateAudioFromParameters();

  t += 0.01;
  for (Particle p : particles) {
    p.update(stressVal, energyVal, orderVal, warmthVal, t, centerVec, fromCenter, toHome, acc);
  }

  background(0, 0, 0);
  for (Particle p : particles) {
    p.display(stressVal, energyVal, orderVal, warmthVal);
  }

  drawUI();
}

void updateParametersFromMouse() {
  float mx = mouseX;
  float my = mouseY;
  float distTL = dist(mx, my, 0, 0);
  float distTR = dist(mx, my, width, 0);
  float distBL = dist(mx, my, 0, height);
  float distBR = dist(mx, my, width, height);
  float maxDist = dist(0, 0, width, height);

  stressVal = constrain(map(distTL, 0, maxDist, 1.0, 0.0), 0, 1);
  energyVal = constrain(map(distTR, 0, maxDist, 1.0, 0.0), 0, 1);
  orderVal  = constrain(map(distBL, 0, maxDist, 1.0, 0.0), 0, 1);
  warmthVal = constrain(map(distBR, 0, maxDist, 1.0, 0.0), 0, 1);
}

void updateAudioFromParameters() {
  if (audioMuted) {
    for (int i = 0; i < 4; i++) oscillators[i].amp(0);
    return;
  }

  // Map parameters to audio: each corner's parameter drives volume and filter cutoff
  // Channel 0 (TL) : Stress   -> darker, lower filter, moderate volume
  // Channel 1 (TR) : Energy   -> brighter, higher filter, dynamic volume
  // Channel 2 (BL) : Order    -> pure, mid filter, restrained volume
  // Channel 3 (BR) : Warmth   -> warm, resonant filter, smooth volume

  float[] params = {stressVal, energyVal, orderVal, warmthVal};

  for (int i = 0; i < 4; i++) {
    // Volume: base 0.0, max 0.15 (subtle)
    float vol = params[i] * 0.12;
    // Add a small cross‑influence to keep sound from being totally silent at center
    vol = max(vol, 0.01);
    oscillators[i].amp(vol);

    // Filter cutoff: map parameter to frequency range (200Hz to 2000Hz)
    float cutoff = map(params[i], 0, 1, 200, 1800);
    // Stress channel tends darker, Warmth more resonant
    if (i == 0) cutoff *= 0.8;      // stress -> lower
    if (i == 3) cutoff *= 1.1;      // warmth -> slightly higher
    filters[i].freq(cutoff);
  }
}

void drawUI() {
  pushStyle();
  textAlign(CENTER, CENTER);
  textSize(14);

  fill(200, 80, 100);
  text("STRESS\n" + nf(stressVal, 0, 2), 80, 50);
  fill(50, 90, 100);
  text("ENERGY\n" + nf(energyVal, 0, 2), width - 80, 50);
  fill(120, 80, 100);
  text("ORDER\n" + nf(orderVal, 0, 2), 80, height - 50);
  fill(30, 90, 100);
  text("WARMTH\n" + nf(warmthVal, 0, 2), width - 80, height - 50);

  fill(0, 0, 100);
  text("Mouse to shift | R reset | S save | O open | M mute", width/2, height - 20);

  // Audio status indicator
  if (audioMuted) {
    fill(0, 0, 100, 200);
    text("🔇 AUDIO MUTED", width/2, 30);
  }
  popStyle();
}

void keyPressed() {
  if (key == 'r' || key == 'R') {
    initParticlesFromImage();
    noiseSeed((long)random(1000000));
  }
  if (key == 's' || key == 'S') {
    saveFrame("city_lens_" + year() + nf(month(),2) + nf(day(),2) + "_" + millis() + ".png");
    println("Screenshot saved.");
  }
  if (key == 'o' || key == 'O') {
    selectInput("Select an image", "fileSelected");
  }
  if (key == 'm' || key == 'M') {
    audioMuted = !audioMuted;
    println("Audio " + (audioMuted ? "muted" : "unmuted"));
  }
}

void fileSelected(File selection) {
  if (selection != null) {
    img = loadImage(selection.getAbsolutePath());
    if (img != null) {
      img = resizeImageToFit(img, 1200);
      initParticlesFromImage();
    }
  }
}

// Particle Class (optimized, with audio‑friendly motion)
// ============================================================
class Particle {
  PVector home, pos, vel;
  float noiseSeedX, noiseSeedY;

  // Precomputed HSB color (converted once at initialization)
  float baseH, baseS, baseB;

  Particle(float x, float y, color c) {
    home = new PVector(x, y);
    pos = home.copy();
    vel = new PVector();
    noiseSeedX = random(1000);
    noiseSeedY = random(1000);

    colorMode(HSB, 360, 100, 100);
    baseH = hue(c);
    baseS = saturation(c);
    baseB = brightness(c);
  }

  // Update motion using reusable vectors to avoid per‑frame allocation
  void update(float stress, float energy, float order, float warmth, float time,
              PVector center, PVector fromCenterVec, PVector toHomeVec, PVector accVec) {

    // Stress: pushes particles outward from center
    float stressForce = stress * 0.8;

    // Energy: controls noise amplitude and speed limit
    float energyNoiseAmp = energy * 3.0;
    float energySpeedLimit = map(energy, 0, 1, 0.2, 4.0);

    // Order: pulls particles back toward their original sampled position
    float orderPullBase = 0.03;
    float orderPull = orderPullBase + order * 0.15;

    // Warmth mainly affects color, minimal motion impact

    // Perlin noise (only active when energy is above threshold)
    float nx = 0, ny = 0;
    if (energy > 0.01) {
      nx = noise(noiseSeedX + time * 0.3, noiseSeedY) * 2 - 1;
      ny = noise(noiseSeedX, noiseSeedY + time * 0.3) * 2 - 1;
      nx *= energyNoiseAmp;
      ny *= energyNoiseAmp;
    }

    // Outward vector (stress)
    center.set(width/2, height/2);
    fromCenterVec.set(pos.x - center.x, pos.y - center.y);
    float len = fromCenterVec.mag();
    if (len > 0.1) {
      fromCenterVec.div(len);
      fromCenterVec.mult(stressForce);
    } else {
      fromCenterVec.set(0, 0);
    }

    // Homeward vector (order)
    toHomeVec.set(home.x - pos.x, home.y - pos.y);
    toHomeVec.mult(orderPull);

    // Combine accelerations
    accVec.set(nx, ny);
    accVec.add(fromCenterVec);
    accVec.add(toHomeVec);

    vel.add(accVec);
    vel.limit(energySpeedLimit);
    pos.add(vel);

    // Wrap around edges
    if (pos.x < 0) pos.x = width;
    if (pos.x > width) pos.x = 0;
    if (pos.y < 0) pos.y = height;
    if (pos.y > height) pos.y = 0;

    // Friction: higher when parameters are low, so particles settle quickly
    float friction = (energy + stress) < 0.05 ? 0.85 : 0.95;
    vel.mult(friction);
  }

  void display(float stress, float energy, float order, float warmth) {
    float h = baseH;
    float s = baseS;
    float br = baseB;

    // Parameter-Driven Tone Mapping
    h = lerp(h, 200, stress * 0.7);   // stress → cool blue
    h = lerp(h, 30, warmth * 0.8);    // warmth → orange/red
    s = lerp(s, 90, warmth * 0.5);    // warmth → saturated
    br = lerp(br, 100, energy * 0.6); // energy → bright
    s = lerp(s, 40, order * 0.5);     // order → desaturated

    // Apply a unique random offset to each particle to create a richer color palette
    // Use `noiseSeedX` to generate a hue offset between -25 and +25 degrees
    float hueShift = (noise(noiseSeedX, noiseSeedY) - 0.5) * 50;
    h = (h + hueShift + 360) % 360;


    s = constrain(s + (noise(noiseSeedX + 100, noiseSeedY) - 0.5) * 30, 0, 100);

    // Brightness also fluctuates (±10%)
    br = constrain(br + (noise(noiseSeedX + 200, noiseSeedY) - 0.5) * 20, 0, 100);

    float sz = map(energy, 0, 1, 2.5, 7) + stress * 1.5;

    noStroke();
    fill(h, s, br, 200);
    ellipse(pos.x, pos.y, sz, sz);

    if (energy > 0.6) {
        fill(h, s, br, 30);
        ellipse(pos.x, pos.y, sz * 2.5, sz * 2.5);
    }
}
}
