int numLines = 4;// number of moving paths
int startTime;// time
import processing.sound.*;
SoundFile bgm;

float[] xPos = new float[numLines];
float[] yPos = new float[numLines];
float[] speed = new float[numLines];
float[] amplitude = new float[numLines];//store each line's current position, speed and movement intensity

color[] palette = {
  color(18, 63, 119),
  color(15, 134, 182),
  color(55, 202, 229),
  color(175,206,243),
  color(108,153,234),
  color(57,89,191),
  color(214,157,15),
  color(243,192,29),
  color(226,213,158),
  color(245,219,55),
  color(251,239,203),
  color(240,187,24),
  color(240,187,24),
  color(10,8,41),
  color(255,215,0)
};

void setup() {
  size(500, 500);
  frameRate(30);//specifies the number of frames to be displayed every second
  background(60,67,161);
  bgm = new SoundFile(this,"城市的浪漫运作.mp3");
  bgm.loop();
  startTime= millis();//start time
  for (int i = 0; i < numLines; i++) {
    xPos[i] = 0;
    yPos[i] = height / numLines * i;
    speed[i] = random(1, 3);
    amplitude[i] = random(2, 6);
  }
}

void draw() {
  if (millis() - startTime >= 60000) {
    saveFrame("DazeOfCityWalk_"+month()+day()+hour()+minute()+second()+".png");//rename every time
    noLoop();
    return;//save png
}
  stroke(255, 20); //change the opacity so the lines feel subtle, and less like creeping worms...
  strokeWeight(2);

  for (int i = 0; i < numLines; i++) {
    float oldX = xPos[i];
    float oldY = yPos[i];

    xPos[i] += speed[i];//move forward in time to the right

    float n = noise(frameCount * 0.01, i * 10);
    yPos[i] += map(n, 0, 1, -amplitude[i], amplitude[i]);//using Perlin noise to create random smooth organic movement

    yPos[i] += sin(frameCount * 0.02 + i) * 0.8;//adding wave like music rhythm;)

    float centerY = height / 2;
    yPos[i] += (centerY - yPos[i]) * 0.01;//subtle attraction towards center(to increase the chance of encounters)

    yPos[i] = constrain(yPos[i], 0, height);//keep inside canvas

    line(oldX, oldY, xPos[i], yPos[i]);//draw the path segment
  }

  for (int i = 0; i < numLines; i++) {
    for (int j = i + 1; j < numLines; j++) {

      float d = dist(xPos[i], yPos[i], xPos[j], yPos[j]);//distance between two paths

      if (d < 45 && frameCount % 12 == 0) {//if they get close enough, a connection will be generated

        int index = int(random(palette.length));
        fill(palette[index]);//color randomness

        float size = map(d, 0, 40, 30, 10); //bigger size of block, bigger visual impact

        rectMode(CENTER);
        rect(xPos[i], yPos[i], size, size);//draw square to represent connection
      }
    }
  }

  for (int i = 0; i < numLines; i++) {//reset when reaching the edge
    if (xPos[i] > width) {
      xPos[i] = 0;//restart from left
      yPos[i] = random(height);//reset random height for new path
    }
  }
}
