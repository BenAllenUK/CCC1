// COMS20001 - Cellular Automaton Farm - Initial Code Skeleton
// (using the XMOS i2c accelerometer demo)

#include <platform.h>
#include <xs1.h>
#include <print.h>
#include <stdio.h>
#include "ReadWrite.h"
#include "Input.h"
#include "Worker.h"
#include "i2c.h"

typedef unsigned char uchar;
#define  IMHT 128
#define  IMWD 128

#define  NUMCPUs 6

on tile[0]: port p_scl = XS1_PORT_1E; //interface ports to accelerometer
on tile[0]: port p_sda = XS1_PORT_1F;

on tile[0] : in port buttons = XS1_PORT_4E; //port to access xCore-200 buttons
on tile[0] : out port leds = XS1_PORT_4F;   //port to access xCore-200 LEDs


#define FXOS8700EQ_I2C_ADDR 0x1E  //register addresses for accelerometer
#define FXOS8700EQ_XYZ_DATA_CFG_REG 0x0E
#define FXOS8700EQ_CTRL_REG_1 0x2A
#define FXOS8700EQ_DR_STATUS 0x0
#define FXOS8700EQ_OUT_X_MSB 0x1
#define FXOS8700EQ_OUT_X_LSB 0x2
#define FXOS8700EQ_OUT_Y_MSB 0x3
#define FXOS8700EQ_OUT_Y_LSB 0x4
#define FXOS8700EQ_OUT_Z_MSB 0x5
#define FXOS8700EQ_OUT_Z_LSB 0x6

#define WORKER_WAIT_FOR_NEXT_ROUND -1
#define SERVER_CONTINUE 1
#define SERVER_FINISH_ROUND 0
#define WORKER_SENT 1

#define EMPTY -1
#define NOT_EMPTY 0

#define PERFORM_LINE_OPTIMIZATION 1
#define PERFORM_CHAR_OPTIMIZATION 1

void sendCurrentGameToOutStream(chanend c_out, uchar  grid[IMHT][IMWD/8]){
    printf("Start writing\n");
    //syncronise printouts
    c_out <: 0;
    for( int y = 0; y < IMHT; y++ ) {
        for( int x = 0; x < IMWD/8; x++ ) {
           c_out <: grid[y][x];
        }
    }
    //syncronise printouts
    c_out <: 0;
    printf("Finished writing\n");
}

void sendData(streaming chanend c, uchar grid[IMHT][IMWD/8], int* lineToSend){
    for(int x = 0; x < IMWD / 8; x++){
        c <: grid[(((*lineToSend) - 1 ) + IMHT)%IMHT][ x];
    }
    for(int x = 0; x < IMWD / 8; x++){
        c <: grid[(((*lineToSend)) + IMHT)%IMHT][ x];
    }
    for(int x = 0; x < IMWD / 8; x++){
        c <: grid[(((*lineToSend) + 1 ) + IMHT)%IMHT][ x];
    }
}

int checkIfAreaIsBlank(uchar grid[IMHT][IMWD/8], int* lineToSend){

    for(int x = 0; x < IMWD / 8; x++){
        if(grid[(((*lineToSend) - 1 ) + IMHT)%IMHT][x] != 0){
            return NOT_EMPTY;
        }
        if(grid[(((*lineToSend)) + IMHT)%IMHT][x] != 0){
            return NOT_EMPTY;
        }
        if(grid[(((*lineToSend) + 1 ) + IMHT)%IMHT][x] != 0){
            return NOT_EMPTY;
        }
    }

    return EMPTY;
}

int sendNextNonEmptyLine(streaming chanend workerChan, uchar grid[IMHT][IMWD / 8], uchar alteredGrid[IMHT][IMWD / 8], int* linesReceived, int* lineToSend){
    (*lineToSend)++;

      while(PERFORM_LINE_OPTIMIZATION == 1 && checkIfAreaIsBlank(grid, lineToSend)==EMPTY && (lineToSend) < IMHT){
          for(int x = 0; x < IMWD / 8; x++){
              alteredGrid[(*lineToSend)][x] = 0;
          }
          (*linesReceived)++;
          (*lineToSend)++;
      }
      if((*lineToSend) == IMHT) {
          return WORKER_WAIT_FOR_NEXT_ROUND;
      }

      workerChan <: *lineToSend;
      sendData(workerChan, grid, lineToSend);
      return WORKER_SENT;
}

int dealWithIt(int j, streaming chanend c, uchar alteredGrid[IMHT][IMWD/8], uchar grid[IMHT][IMWD/8], int* linesReceived, int* lineToSend, int id){
    for(int x = 0; x < IMWD / 8; x++){
        c :> alteredGrid[id][x];
    }
    (*linesReceived)++;

    if((*linesReceived) == IMHT){
        // Finished this cycle
        c <: WORKER_WAIT_FOR_NEXT_ROUND;
        return SERVER_FINISH_ROUND;
    }else if((*lineToSend)+1 >= IMHT) {
        // Do nothing
        c <: WORKER_WAIT_FOR_NEXT_ROUND;
        return SERVER_CONTINUE;
    }else{
        (*lineToSend)++;
        while(PERFORM_LINE_OPTIMIZATION == 1 && checkIfAreaIsBlank(grid, lineToSend)==EMPTY && (*lineToSend) < IMHT){
            for(int x = 0; x < IMWD / 8; x++){
                alteredGrid[(*lineToSend)][x] = 0;
            }
            (*linesReceived)++;
            (*lineToSend)++;
        }
        if((*linesReceived) == IMHT) {
               // Finsih
               c <: WORKER_WAIT_FOR_NEXT_ROUND;
               return SERVER_FINISH_ROUND;
        }
        if((*lineToSend) == IMHT) {
            // Do nothing
            c <: WORKER_WAIT_FOR_NEXT_ROUND;
            return SERVER_CONTINUE;
        }

        c <: (*lineToSend);
        sendData(c, grid, lineToSend);
        return SERVER_CONTINUE;
    }
}

void distributor(chanend c_in, chanend c_out, chanend fromAcc, streaming chanend workerChans[NUMCPUs], out port leds, chanend buttonsChan)
{
  printf("Distributor: Start...\nDistributor: Waiting for button press\n");
  uchar val;
  uchar grids[2][IMHT][IMWD / 8];

  int btnResponse;
  buttonsChan  :> btnResponse;

  // Halt processing till button press
  while(btnResponse != 13){
      printf("Wrong button\n");
      buttonsChan  :> btnResponse;
  }

  printf("Button Pressed\n");


  printf("Started reading image (Green light)\n");

  leds <: 4;

  for( int y = 0; y < IMHT; y++) {
    for( int x = 0; x < IMWD/8; x++) {
      c_in :> val;
      grids[0][y][ x] = val;
    }
  }
  printf("Finished reading image\n");

  printf( "Processing image:, size = %dx%d\n", IMHT, IMWD );
  int k = 0;
  int linesReceived = 0;
  int lineToSend = -1;
  timer t;
  uint32_t startTime;
  uint32_t endTime;
  t :> startTime;
  leds <: ((k)%2);

    for(int i = 0; i < NUMCPUs; i++){
        int tmp = sendNextNonEmptyLine(workerChans[i], grids[0], grids[1], &linesReceived, &lineToSend);
        if(tmp == WORKER_WAIT_FOR_NEXT_ROUND){
            break;
        }
    }
  int average = 0;
  int num = 0;
  while(1){
      [[ordered]]
      select {
          case buttonsChan :> int btnVal:
              if(btnVal == 14){
                  printf("Iteration: %d\n", k);
                  leds <: 2;
                  sendCurrentGameToOutStream(c_out, grids[k%2]);
              }else{
                  printf("Wrong button\n");
              }
              break;
          case fromAcc :> int accResponse:
              printf("Board Tilted\n");
              leds <: 8;
              fromAcc :> accResponse;
              printf("Board level\n");
              break;
          case workerChans[int j] :> int lineID:
            int newRound = dealWithIt(j, workerChans[j], grids[(k+1)%2], grids[(k%2)], &linesReceived, &lineToSend, lineID);
            if(newRound==SERVER_FINISH_ROUND){
                linesReceived = 0;
                lineToSend = -1;
                k++;
                leds <: ((k)%2);

                for(int i = 0; i < NUMCPUs; i++){
                    int tmp = sendNextNonEmptyLine(workerChans[i], grids[(k%2)], grids[(k+1)%2], &linesReceived, &lineToSend);
                    if(tmp == WORKER_WAIT_FOR_NEXT_ROUND){
                        break;
                    }
                }
                if(k%100 == 0){
                    t :> endTime;
                    average += (endTime - startTime) / 100000;
                    num++;
                    if(num == 20){
                    printf("after 20 av: %d ms\n", (average / num));
                    }
                    startTime = endTime;
                }
            }
            break;
      }

   }
}



int main(void) {

  i2c_master_if i2c[1]; //interface to accelerometer

  chan c_acc;
  chan c_inIO, c_outIO;    //extend your channel definitions here
  streaming chan workerChans[NUMCPUs];
  chan buttonsChan;


  par {
    on tile[0]: i2c_master(i2c, 1, p_scl, p_sda, 10);   //server thread providing accelerometer data
    on tile[0]: accelerometer(i2c[0],c_acc);        //client thread reading accelerometer data
    on tile[0]: DataInStream("test.pgm", c_inIO);          //thread to read in a PGM image
    on tile[0]: DataOutStream("testout.pgm", c_outIO);       //thread to write out a PGM image
    on tile[0]: distributor(c_inIO, c_outIO, c_acc, workerChans, leds, buttonsChan);//thread to coordinate work on image
    on tile[0]: buttonListener(buttons, buttonsChan);
    par (int i = 0; i < 2; i++){
            on tile[0]: initWorker(i, workerChans[i]);
    }
    par (int i = 2; i < NUMCPUs; i++){
        on tile[1]: initWorker(i, workerChans[i]);
    }
  }

  return 0;
}
