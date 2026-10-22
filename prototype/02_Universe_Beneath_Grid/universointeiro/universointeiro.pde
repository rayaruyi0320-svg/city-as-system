import processing.sound.*;

int mode = 1;          // 1: Matrix Mode  2: Burning Poem Mode

int cols = 20;
int rows = 20;
float cellW, cellH;
float angle = 0;
float[][] digitY;      // stores vertical offset for each digit (for scrolling)

// mode2 resources
PImage poemImg;
PGraphics firePaper;
ArrayList<FlameParticle> particles;

// sound
SoundFile originalMusic;
SoundFile glitchMusic;
float totalExposedArea = 0;
float totalCanvasArea;
float glitchStartTime = 0;
float glitchFadeDuration = 3.0;   // fades-out time
boolean glitchFading = false;      // whether it's currently fading out

void setup() {
  size(800, 800);
  cellW = width / (float)cols;
  cellH = height / (float)rows;

  //initialize scrolling values for digits
  digitY = new float[cols][rows];
  for (int i = 0; i < cols; i++) {
    for (int j = 0; j < rows; j++) {
      digitY[i][j] = random(height);
    }
  }

  // load poem image
  poemImg = loadImage("pessoa.jpg");
  if (poemImg != null){
  poemImg.resize(width,height);}

  // firepaper layer
  firePaper = createGraphics(width, height);
  firePaper.beginDraw();
  firePaper.background(0, 0, 0, 0);
  firePaper.fill(100, 255, 100, 255);   // the green covers everything
  firePaper.rect(0, 0, width, height);
  firePaper.endDraw();

  // particle system
  particles = new ArrayList<FlameParticle>();

  // load music
  originalMusic = new SoundFile(this, "original.mp3");
  glitchMusic = new SoundFile(this, "glitch.mp3");

  // glitch sound loops silently in the background
  glitchMusic.loop();
  glitchMusic.amp(0);

  // original music will only start in mode 2
  totalCanvasArea = width * height;

  frameRate(30);
}


void draw() {
  // glitch music fades out over time
  if (glitchFading) {
    float elapsed = (millis() - glitchStartTime) / 1000.0;
    if (elapsed >= glitchFadeDuration) {
      glitchMusic.amp(0);
      glitchFading = false;
    } else {
      float vol = map(elapsed, 0, glitchFadeDuration, 1.0, 0);
      glitchMusic.amp(vol);
    }
  }

  background(0);
  if (mode == 1) {
    drawMode1();
  } else {
    drawMode2();
  }
}


void drawMode1() {
  angle += 0.02;

  // draw subtle grid lines
  stroke(40);
  strokeWeight(0.5);
  for (int i = 0; i <= cols; i++) {
    line(i*cellW, 0, i*cellW, height);
    line(0, i*cellH, width, i*cellH);
  }

  for (int i = 0; i < cols; i++) {
    for (int j = 0; j < rows; j++) {
      float x = i * cellW;
      float y = j * cellH;

      //decide whether to draw a gear (sparse distribution)
      boolean drawGear = ((i + j) % 3 == 0);

      // gear (abstract mechanical shape)
      if (drawGear) {
        pushMatrix();
        translate(x + cellW*0.7, y + cellH*0.3);  // place near top-right of cell
        rotate(angle * (i + j) * 0.3);
        stroke(100, 255, 100);
        noFill();
        // outer circle
        ellipse(0, 0, cellW*0.35, cellH*0.35);
        // inner circle
        ellipse(0, 0, cellW*0.2, cellH*0.2);
        // radial lines to mimic gear teeth
        for (int k = 0; k < 8; k++) {
          float rad = k * TWO_PI / 8;
          float x1 = cos(rad) * cellW*0.12;
          float y1 = sin(rad) * cellH*0.12;
          float x2 = cos(rad) * cellW*0.22;
          float y2 = sin(rad) * cellH*0.22;
          line(x1, y1, x2, y2);
        }
        popMatrix();
      }

      // binary digits (bottom-left of each cell)
      fill(0, 255, 0);
      textSize(cellW * 0.3);
      textAlign(LEFT, TOP);
      // random digits every frame → flickering effect
      int digit = (int)random(2);
      float digitX = x + cellW*0.1;
      float digitY = y + cellH*0.7;
      text(digit, digitX, digitY);

    }
  }

  // update scrolling motion (slow downward drift)
  for (int i = 0; i < cols; i++) {
    for (int j = 0; j < rows; j++) {
      digitY[i][j] += 0.8;
      if (digitY[i][j] > height + cellH) {
        digitY[i][j] = -cellH;
      }
    }
  }
}


void drawMode2() {
  // draw background poem
  image(poemImg, 0, 0);
  // draw fire paper layer on top
  image(firePaper, 0, 0);

  // update + display flame particles
  for (int i = particles.size()-1; i >= 0; i--) {
    FlameParticle p = particles.get(i);
    p.update();
    p.display();
    if (p.isDead()) {
      particles.remove(i);
    }
  }
}

// Mouse interaction
void mouseDragged() {
  if (mode == 2) burnFirePaper(mouseX, mouseY);
}

void mouseMoved() {
  if (mode == 2) burnFirePaper(mouseX, mouseY);
}

void mousePressed() {
  if (mode == 1) {
    // trigger glitch sound and start fading out
    glitchMusic.amp(1.0);
    glitchStartTime = millis();
    glitchFading = true;
  }
}

void burnFirePaper(float mx, float my) {
  if (mx < 0 || mx > width || my < 0 || my > height) return;

  float addedArea = 0;  // track how much area we reveal this frame

  firePaper.beginDraw();

  // main erase area (fully transparent → reveals poem)
  firePaper.blendMode(REPLACE);
  firePaper.noStroke();
  float mainSize = random(30, 50);
  firePaper.fill(0, 0, 0, 0);
  firePaper.ellipse(mx, my, mainSize, mainSize);
  addedArea += PI * (mainSize/2) * (mainSize/2);

  // add irregular edges to make it feel more organic
  int edgeCount = int(random(5, 12));
  for (int i = 0; i < edgeCount; i++) {
    float offsetX = random(-20, 20);
    float offsetY = random(-20, 20);
    float size = random(8, 20);
    firePaper.fill(0, 0, 0, 0);
    firePaper.ellipse(mx + offsetX, my + offsetY, size, size);
    addedArea += PI * (size/2) * (size/2);
  }

  // slight burn marks around the edge (visual detail only)
  firePaper.blendMode(BLEND);
  int burnCount = int(random(3, 8));
  for (int i = 0; i < burnCount; i++) {
    float angle = random(TWO_PI);
    float radius = random(mainSize/2 - 5, mainSize/2 + 8);
    float xOff = cos(angle) * radius;
    float yOff = sin(angle) * radius;
    float size = random(5, 12);
    firePaper.fill(40, 25, 15, random(80, 150));
    firePaper.ellipse(mx + xOff, my + yOff, size, size);
  }
  firePaper.endDraw();

  // flame particles (purely visual effect)
  int particleCount = int(random(8, 18));
  for (int i = 0; i < particleCount; i++) {
    particles.add(new FlameParticle(mx + random(-18, 18), my + random(-15, 15)));
  }

  // update revealed area → control music volume
  totalExposedArea += addedArea;
  totalExposedArea = min(totalExposedArea, totalCanvasArea);
  float areaRatio = totalExposedArea / totalCanvasArea;
  // cubic curve → very slow at first, then grows fast
  float volume = 0.8 * pow(areaRatio, 3.0);
  originalMusic.amp(volume);
}

// Keyboard control
void keyPressed() {
  if (key == '1') {
    mode = 1;
    originalMusic.stop();       // stop original sound
    glitchMusic.amp(0);
    glitchFading = false;
  } else if (key == '2') {
    mode = 2;
    // reset fire paper
    firePaper.beginDraw();
    firePaper.background(0, 0, 0, 0);
    firePaper.fill(100, 255, 100, 255);
    firePaper.rect(0, 0, width, height);
    firePaper.endDraw();
    particles.clear();

    totalExposedArea = 0;
   //  restart original music from beginning
    originalMusic.stop();
    originalMusic.loop();
    originalMusic.amp(0);

    // mute glitch
    glitchMusic.amp(0);
    glitchFading = false;
  }
}

// Flame Particle
class FlameParticle {
  float x, y;
  float vx, vy;
  float life;
  float size;
  color col;

  FlameParticle(float x, float y) {
    this.x = x;
    this.y = y;
    vx = random(-1.2, 1.2);
    vy = random(-2.5, -0.8);
    life = 200;
    size = random(2, 7);
    // warm fire colors (orange/red/yellow range)
    float r = random(220, 255);
    float g = random(80, 180);
    float b = random(0, 60);
    col = color(r, g, b, random(180, 255));
  }

  void update() {
    x += vx;
    y += vy;
    life -= 5;
    size *= 0.98;
  }

  void display() {
    noStroke();
    fill(col, life);
    ellipse(x, y, size, size);
  }

  boolean isDead() {
    return life <= 0 || size < 0.5;
  }
}
