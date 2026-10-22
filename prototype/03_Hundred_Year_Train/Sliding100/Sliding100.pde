import processing.sound.*;

PImage original;
PImage[] newImages = new PImage[6];
String[] newImageFiles = {"new.jpg", "new1.jpg", "new2.jpg", "new3.jpg", "new4.jpg", "new5.jpg"};
PImage resultImage;
int imgW, imgH;
float imgScale;
int imgX, imgY;


SoundFile[] sounds = new SoundFile[4];   // Four sound files for four historical eras
boolean soundEnabled = true;              // Turn sound on/off if files are missing


float t = 0.0;                 // Master time value (0.0 = 1907, 1.0 = 2021)
boolean autoPlay = false;
float autoStartTime = 0;
float autoDuration = 20.0;


int sliderY, sliderHeight = 40;
int markerRadius = 8;
boolean showTooltip = false;             // Show year/event when hovering over a marker?
int tooltipX, tooltipY;
String tooltipText = "";
final float[] tPoints = {0.0, 0.2, 0.6, 1.0};   // Four key moments (1907,1937,1997,2021)
final String[] years = {"1907", "1937", "1997", "2021"};
final String[] events = {"Founding", "Bombing", "Rebuilding", "Forest Station"};

boolean needUpdate = true;               // Re-draw the image only when t changes (saves CPU)


float lastFlashTime = 0;
float flashIntensity = 0;



void settings() {
  fullScreen(P2D);
}

void setup() {
  sliderY = height - sliderHeight;

  original = loadImage("old.jpg");
  if (original == null) {
    println("Error: old.jpg not found.");
    exit();
  }

  int loadedCount = 0;
  for (int i = 0; i < newImageFiles.length; i++) {
    newImages[i] = loadImage(newImageFiles[i]);
    if (newImages[i] != null) loadedCount++;
    else println("Warning: " + newImageFiles[i] + " not found.");
  }
  if (loadedCount == 0) {
    println("Error: Image not found. ");
    exit();
  }

  // Calculate how to fit the image on screen without stretching
  float ratioW = (float)width / original.width;
  float ratioH = (float)(height - sliderHeight) / original.height;
  imgScale = min(ratioW, ratioH);      // Use the smaller ratio so image fits entirely
  imgW = (int)(original.width * imgScale);
  imgH = (int)(original.height * imgScale);
  imgX = (width - imgW) / 2;           // Center horizontally
  imgY = (height - sliderHeight - imgH) / 2;  // Center vertically above slider

  // Resize all images to the same display size (for faster processing)
  original.resize(imgW, imgH);
  for (int i = 0; i < newImages.length; i++) {
    if (newImages[i] != null) newImages[i].resize(imgW, imgH);
  }

  resultImage = createImage(imgW, imgH, RGB);   // Blank canvas for final blending

  // Load sound files
  try {
    sounds[0] = new SoundFile(this, "hit_1907.wav");
    sounds[1] = new SoundFile(this, "hit_1937.wav");
    sounds[2] = new SoundFile(this, "hit_1997.wav");
    sounds[3] = new SoundFile(this, "hit_2021.wav");
    for (int i = 0; i < 4; i++) {
      if (sounds[i] != null) sounds[i].loop();   // Keep playing in background
      else soundEnabled = false;
    }
  } catch (Exception e) {
    soundEnabled = false;
  }

  updateImage();          // Generate the first image based on t=0
  frameRate(60);          // Target 60 frames per second
}


void draw() {
  background(0);

  // Handle auto-play: increase t over time
  if (autoPlay) {
    float elapsed = (millis() - autoStartTime) / 1000.0;
    if (elapsed >= autoDuration) {
      autoPlay = false;
      t = 1.0;
    } else {
      t = elapsed / autoDuration;
    }
    needUpdate = true;    // t changed, re-generate the image
  }

  // Only regenerate the image when t actually changed
  if (needUpdate) {
    updateImage();
    needUpdate = false;
  }

  // Draw the final blended image on screen (centered)
  image(resultImage, imgX, imgY, imgW, imgH);

  // Draw the UI (slider, markers, tooltip)
  drawSlider();
  drawMarkers();
  if (showTooltip) drawTooltip();

  // Adjust sound volumes according to current t (cross-fade between eras)
  if (soundEnabled) {
    float[] w = computeWeights(t);
    float sum = w[0]+w[1]+w[2]+w[3];
    if (sum > 0) {
      for (int i=0; i<4; i++) {
        sounds[i].amp(w[i] / sum);   // Volume = normalized weight
      }
    }
  }
}

//Generate blended images
void updateImage() {
  // Get the four era weights (based on t)
  float[] weights = computeWeights(t);
  float sum = weights[0]+weights[1]+weights[2]+weights[3];
  if (sum == 0) sum = 1;
  for (int i=0; i<4; i++) weights[i] /= sum;   // Normalize so they add to 1

  // Generate the effect images for the first two eras (if their weight > 0)
  PImage img0 = (weights[0] > 0.01) ? pixelateFast(original, weights[0]) : null;
  PImage img1 = (weights[1] > 0.01) ? glitchFast(original, weights[1]) : null;

  // For the combined "rebuild → nature" part (1997 + 2021), treat them as one smooth transition
  PImage img234 = null;

  if (t <= 0.6) {
    // Before t=0.6, only show the vertical shift effect, but its intensity grows gradually from 0 to 1 between t=0.4 and t=0.6.
    float shiftIntensity = getShiftIntensity(t);
    img234 = verticalShiftEffect(original, shiftIntensity);
  } else {
    // After t=0.6, start fading from vertical shift to new images
    float localT = constrain((t - 0.6) / 0.4, 0, 1);   // 0 = at 0.6, 1 = at 1.0
    img234 = rebuildToNature(original, localT);
  }

  // Blend all three parts using their weights
  resultImage.loadPixels();
  if (img0 != null) img0.loadPixels();
  if (img1 != null) img1.loadPixels();
  if (img234 != null) img234.loadPixels();

  for (int i = 0; i < resultImage.pixels.length; i++) {
    float r = 0, g = 0, b = 0;
    if (img0 != null) {
      color c = img0.pixels[i];
      r += red(c)*weights[0];
      g += green(c)*weights[0];
      b += blue(c)*weights[0];
    }
    if (img1 != null) {
      color c = img1.pixels[i];
      r += red(c)*weights[1];
      g += green(c)*weights[1];
      b += blue(c)*weights[1];
    }
    if (img234 != null) {
      color c = img234.pixels[i];
      r += red(c)*(weights[2]+weights[3]);
      g += green(c)*(weights[2]+weights[3]);
      b += blue(c)*(weights[2]+weights[3]);
    }
    resultImage.pixels[i] = color(r, g, b);
  }
  resultImage.updatePixels();

  // Add random flash effects like sunlight glints)
  applyFlashEffect();
}


// This makes the vertical lines appear smoothly, not suddenly. t=0.4=intensity 0 (no lines); t=0.6=intensity 1 (full lines); t=1.0=intensity 0 (lines fade away again)
float getShiftIntensity(float t) {
  if (t < 0.4) return 0;
  if (t < 0.6) return map(t, 0.4, 0.6, 0, 1);
  if (t < 1.0) return map(t, 0.6, 1.0, 1, 0);
  return 0;
}


PImage rebuildToNature(PImage src, float localT) {
  // Pick a random new image
  PImage targetNew = selectNewImage(localT);

  // Vertical shift strength decreases as localT increases
  float shiftIntensity = 1.0 - localT;
  PImage shifted = verticalShiftEffect(src, shiftIntensity);

  // Blend the shifted image with the chosen new image
  PImage out = createImage(src.width, src.height, RGB);
  out.loadPixels();
  shifted.loadPixels();
  targetNew.loadPixels();

  for (int i = 0; i < out.pixels.length; i++) {
    color cShift = shifted.pixels[i];
    color cNew = targetNew.pixels[i];
    float r = lerp(red(cShift), red(cNew), localT);
    float g = lerp(green(cShift), green(cNew), localT);
    float b = lerp(blue(cShift), blue(cNew), localT);
    out.pixels[i] = color(r, g, b);
  }
  out.updatePixels();
  return out;
}


PImage selectNewImage(float localT) {
  // Collect all valid new images (skip missing ones)
  ArrayList<PImage> valid = new ArrayList<PImage>();
  for (int i = 0; i < newImages.length; i++) {
    if (newImages[i] != null) valid.add(newImages[i]);
  }
  if (valid.size() == 0) return original;   // fallback if nothing works

  // At the very end (localT >= 0.98), force new2.jpg (index 2)
  if (localT >= 0.98) {
    if (newImages[2] != null) return newImages[2];
    else return valid.get(0);   // if new2.jpg missing, use first available
  }

  // Otherwise, give new2.jpg a higher chance as localT increases
  float chanceForNew2 = constrain(localT * 1.2, 0, 0.9);   // max 90%
  if (random(1) < chanceForNew2 && newImages[2] != null) {
    return newImages[2];
  } else {
    // Pick any random valid new image
    int idx = floor(random(valid.size()));
    return valid.get(idx);
  }
}


void applyFlashEffect() {
  // Only enable flashes after t=0.6 (during the rebuild→nature phase)
  if (t < 0.6) return;
  float localT = constrain((t - 0.6) / 0.4, 0, 1);
  if (localT < 0.15) return;   // very early part of transition: no flash yet

  // Flash parameters
  float flashProb = 0.12;           // 12% chance per frame
  float intensityMin = 0.7;
  float intensityMax = 1.5;
  float duration = 0.18;            // flash lasts 0.18 seconds
  float radiusFactor = 0.45;        // flash radius = 45% of image width
  float brightnessBoost = 2.0;      // how much brighter the flash makes pixels

  // Randomly decide to start a new flash
  if (random(1) < flashProb) {
    flashIntensity = random(intensityMin, intensityMax) * constrain(localT*1.2, 0.5, 1.2);
    lastFlashTime = millis() / 1000.0;
  }

  // If a flash is active, draw a bright radial gradient on top of the image
  float elapsed = (millis() / 1000.0) - lastFlashTime;
  if (elapsed < duration && flashIntensity > 0) {
    float alpha = flashIntensity * (1.0 - elapsed/duration);   // fades over time
    resultImage.loadPixels();
    float cx = random(resultImage.width);    // random center X
    float cy = random(resultImage.height);   // random center Y
    float maxRadius = resultImage.width * radiusFactor;

    for (int y = 0; y < resultImage.height; y++) {
      for (int x = 0; x < resultImage.width; x++) {
        float d = dist(x, y, cx, cy);
        if (d < maxRadius) {
          float strength = alpha * (1.0 - d/maxRadius);   // stronger in the center
          int idx = y * resultImage.width + x;
          color c = resultImage.pixels[idx];
          // Add white light (more red+green than blue for warm feel)
          float r = red(c) + 255 * strength * brightnessBoost;
          float g = green(c) + 255 * strength * brightnessBoost;
          float b = blue(c) + 200 * strength * brightnessBoost;
          resultImage.pixels[idx] = color(constrain(r,0,255), constrain(g,0,255), constrain(b,0,255));
        }
      }
    }
    resultImage.updatePixels();
  } else {
    flashIntensity = 0;   // flash finished
  }
}




// 1907: Pixelation + color averaging (blurry, like old memory)
PImage pixelateFast(PImage src, float intensity) {
  int blockSize = (int)map(intensity, 0, 1, 1, 20);   // bigger block = more pixelated
  blockSize = max(1, blockSize);
  PImage out = createImage(src.width, src.height, RGB);
  out.loadPixels();
  src.loadPixels();
  for (int y = 0; y < src.height; y += blockSize) {
    for (int x = 0; x < src.width; x += blockSize) {
      int x2 = min(x + blockSize, src.width);
      int y2 = min(y + blockSize, src.height);
      float r = 0, g = 0, b = 0;
      int cnt = 0;
      for (int yy = y; yy < y2; yy++) {
        for (int xx = x; xx < x2; xx++) {
          color c = src.pixels[yy * src.width + xx];
          r += red(c); g += green(c); b += blue(c);
          cnt++;
        }
      }
      r /= cnt; g /= cnt; b /= cnt;
      for (int yy = y; yy < y2; yy++) {
        for (int xx = x; xx < x2; xx++) {
          out.pixels[yy * src.width + xx] = color(r, g, b);
        }
      }
    }
  }
  out.updatePixels();
  return out;
}

// 1937: Glitch effect (RGB channel shift + random block copying)
PImage glitchFast(PImage src, float intensity) {
  PImage out = src.copy();
  out.loadPixels();
  src.loadPixels();
  int maxOffset = (int)map(intensity, 0, 1, 0, 20);
  if (maxOffset == 0) return out;
  // Shift red, green, blue channels independently by random amounts
  for (int y = 0; y < src.height; y++) {
    for (int x = 0; x < src.width; x++) {
      int idx = y * src.width + x;
      int rOff = (int)random(-maxOffset, maxOffset);
      int gOff = (int)random(-maxOffset, maxOffset);
      int bOff = (int)random(-maxOffset, maxOffset);
      int rIdx = constrain(idx + rOff, 0, src.pixels.length-1);
      int gIdx = constrain(idx + gOff, 0, src.pixels.length-1);
      int bIdx = constrain(idx + bOff, 0, src.pixels.length-1);
      out.pixels[idx] = color(red(src.pixels[rIdx]), green(src.pixels[gIdx]), blue(src.pixels[bIdx]));
    }
  }
  // Copy some random blocks to other positions
  int copies = (int)map(intensity, 0, 1, 0, 8);
  for (int c = 0; c < copies; c++) {
    int w = (int)random(20, 60);
    int h = (int)random(20, 60);
    int x1 = (int)random(0, src.width - w);
    int y1 = (int)random(0, src.height - h);
    int x2 = (int)random(0, src.width - w);
    int y2 = (int)random(0, src.height - h);
    out.copy(x1, y1, w, h, x2, y2, w, h);
  }
  out.updatePixels();
  return out;
}

// 1997: Vertical shift effect (simulates tracks / rigid order); Each column shifts up or down based on its average brightness.
PImage verticalShiftEffect(PImage src, float intensity) {
  PImage out = src.copy();
  if (intensity <= 0.01) return out;
  out.loadPixels();
  src.loadPixels();
  int maxShift = (int)map(intensity, 0, 1, 0, src.height / 4);
  if (maxShift == 0) return out;
  for (int x = 0; x < src.width; x++) {
    // Calculate average brightness of this column
    float colAvgBright = 0;
    for (int y = 0; y < src.height; y++) {
      colAvgBright += brightness(src.pixels[y*src.width + x]);
    }
    colAvgBright /= src.height;
    // Darker columns shift more (or less, depending on mapping)
    int shift = (int)map(colAvgBright, 0, 255, maxShift, -maxShift);
    if (shift == 0) continue;
    // Copy the column into a temporary array, then write it back shifted
    color[] column = new color[src.height];
    for (int y = 0; y < src.height; y++) {
      column[y] = src.pixels[y*src.width + x];
    }
    for (int y = 0; y < src.height; y++) {
      int newY = (y + shift + src.height) % src.height;
      out.pixels[newY * src.width + x] = column[y];
    }
  }
  out.updatePixels();
  return out;
}


// Returns how much each era (0=1907,1=1937,2=1997,3=2021) contributes at time t. The weights form a smooth "triangle" shape around each key point.
float[] computeWeights(float t) {
  float w0 = max(0, 1 - t/0.2);
  float w1 = max(0, 1 - abs(t-0.2)/0.2);
  float w2 = max(0, 1 - abs(t-0.6)/0.4);
  float w3 = max(0, (t-0.8)/0.2);
  if (t >= 1.0) { w3 = 1; w0 = w1 = w2 = 0; }
  if (t <= 0.0) { w0 = 1; w1 = w2 = w3 = 0; }
  return new float[]{w0, w1, w2, w3};
}


// Draw the slider bar at the bottom
void drawSlider() {
  fill(40);
  rect(0, sliderY, width, sliderHeight);
  fill(200);
  float x = map(t, 0, 1, 0, width);
  rect(x-5, sliderY, 10, sliderHeight);
}

// Draw circular markers for the four key years
void drawMarkers() {
  for (int i=0; i<tPoints.length; i++) {
    float x = map(tPoints[i], 0, 1, 0, width);
    fill(255, 200, 100);
    ellipse(x, sliderY + sliderHeight/2, markerRadius, markerRadius);
    // Check if mouse is hovering over this marker
    if (dist(mouseX, mouseY, x, sliderY+sliderHeight/2) < markerRadius+5) {
      showTooltip = true;
      tooltipX = mouseX + 10;
      tooltipY = mouseY - 10;
      tooltipText = years[i] + " - " + events[i];
    }
  }
}

// Draw a small text box when hovering over a marker
void drawTooltip() {
  fill(0, 200);
  rect(tooltipX, tooltipY-20, textWidth(tooltipText)+10, 25);
  fill(255);
  text(tooltipText, tooltipX+5, tooltipY-5);
}


// Click or drag on the slider to change t
void mousePressed() {
  if (mouseY >= sliderY && mouseY <= sliderY+sliderHeight) {
    float newT = constrain(map(mouseX, 0, width, 0, 1), 0, 1);
    if (newT != t) {
      t = newT;
      if (autoPlay) autoPlay = false;
      needUpdate = true;
    }
  }
}

void mouseDragged() {
  if (mouseY >= sliderY && mouseY <= sliderY+sliderHeight) {
    float newT = constrain(map(mouseX, 0, width, 0, 1), 0, 1);
    if (newT != t) {
      t = newT;
      if (autoPlay) autoPlay = false;
      needUpdate = true;
    }
  }
}

void mouseMoved() {
  showTooltip = false;   // Hide tooltip when mouse moves away from markers
}

// Press SPACE to start/stop auto-play; press R to reset to 1907
void keyPressed() {
  if (key == ' ') {
    autoPlay = !autoPlay;
    if (autoPlay) autoStartTime = millis();
    needUpdate = true;
  }
  if (key == 'r' || key == 'R') {
    t = 0;
    autoPlay = false;
    needUpdate = true;
  }
}
