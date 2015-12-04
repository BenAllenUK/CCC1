// COMS20001 - Cellular Automaton Farm - Initial Code Skeleton
// (using the XMOS i2c accelerometer demo)

#include <platform.h>
#include <xs1.h>
#include <print.h>
#include <stdio.h>
#include "pgmIO.h"
#include "i2c.h"

#define  IMHT 512                  //image height
#define  IMWD 512                  //image width
#define  NUMCPUs 10

//#define DEBUG

typedef unsigned char uchar;      //using uchar as shorthand

on tile[0]: port p_scl = XS1_PORT_1E;         //interface ports to accelerometer
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

void initServer( streaming chanend workers[NUMCPUs], uchar grid[IMHT][IMWD/8], int* linesReceived, int* lineToSend, uchar alteredGrid[IMHT][IMWD/8]);
void initWorker(int CPUId, streaming chanend c);
int dealWithIt(int j, streaming chanend c, uchar alteredGrid[IMHT][IMWD/8], uchar grid[IMHT][IMWD/8], int* linesReceived, int* lineToSend, int id);
void sendData(streaming chanend c, uchar grid[IMHT][IMWD/8], int* lineToSend);
int gridDoesNotNeedProccessingAsItAndItsNeighboursAreEmpty(uchar grid[IMHT][IMWD/8], int* lineToSend);

int indexer(int y, int x){
    return y*IMWD + x;
}

void DataInStream(char infname[], streaming chanend c_out)
{
  timer t;
  uint32_t  startTime;
  t :> startTime;
  int res;
  uchar line[ IMWD ];
  printf( "DataInStream: Start...\n" );

  //Open PGM file
  res = _openinpgm( infname, IMWD, IMHT );
  if( res ) {
    printf( "DataInStream: Error openening %s\n.", infname );
    return;
  }

  //Read image line-by-line and send byte by byte to channel c_out
  for( int y = 0; y < IMHT; y++ ) {
    _readinline( line, IMWD );
    for( int x = 0; x < IMWD; x += 8 ) {
        uchar linePart = 0;
        for( int z = 0; z < 8; z++){
           if(line[x + z] == 255){
               linePart += 1 << (7 - z);
           }
        }
        c_out <: linePart;

    }
  }
  uint32_t  endTime;
  t :> endTime;
  printf("Read in time: %d sec\n",(endTime - startTime) / 100000000);
  //Close PGM image file
  _closeinpgm();
  printf( "DataInStream:Done...\n" );
  return;
}

void printBin(uchar num){
    for(int y = 0; y<8; y++){
        printf("%d", ((num >> (7 - y)) & 1));
    }

}

void printGrid(uchar grid[IMHT][IMWD / 8]){
    for(int x = 0; x<IMHT; x++){
        for(int y = 0; y<IMWD / 8; y++){
            printBin(grid[x][y]);
        }
        printf("\n");
    }
    printf("\n");
}

void sendCurrentGameToOutStream(streaming chanend c_out, uchar  grid[IMHT][IMWD/8]){
    printf("Start writing\n");
    //syncronise printouts
    c_out <: 0;
    for( int y = 0; y < IMHT; y++ ) {   //go through all lines
        for( int x = 0; x < IMWD/8; x++ ) { //go through each pixel per line
           c_out <: grid[y][x]; //send some modified pixel out
        }
    }
    //syncronise printouts
    c_out <: 0;
    printf("Finished writing\n");
}

void sendData(streaming chanend c, uchar grid[IMHT][IMWD/8], int* lineToSend){
    //printf("sendData: sending data from line %d\n", *lineToSend);
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

int sentNextNoneEmptyLineUpdatingLineCounters(streaming chanend workerChan, uchar grid[IMHT][IMWD / 8], uchar alteredGrid[IMHT][IMWD / 8], int* linesReceived, int* lineToSend){
    (*lineToSend)++;
      while(gridDoesNotNeedProccessingAsItAndItsNeighboursAreEmpty(grid, lineToSend)==EMPTY && (lineToSend) < IMHT){
          for(int x = 0; x < IMWD / 8; x++){
              alteredGrid[(*lineToSend)][x] = 0;
          }
          //printf("Pre Server: Line is clear so didn't send\n");
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

void distributor(streaming chanend c_in, streaming chanend c_out, chanend fromAcc, streaming chanend workerChans[NUMCPUs], out port leds, chanend buttonsChan)
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
        //printf("Pre Server: Sending initial data to core: %d\n", i);
        int tmp = sentNextNoneEmptyLineUpdatingLineCounters(workerChans[i], grids[0], grids[1], &linesReceived, &lineToSend);
        if(tmp == WORKER_WAIT_FOR_NEXT_ROUND){
            break;
        }
    }

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
                    int tmp = sentNextNoneEmptyLineUpdatingLineCounters(workerChans[i], grids[(k%2)], grids[(k+1)%2], &linesReceived, &lineToSend);
                    if(tmp == WORKER_WAIT_FOR_NEXT_ROUND){
                        break;
                    }
                }
                if(k%100 == 0){
                    t :> endTime;
                    printf("Time for 100 generations: %d ms\n",(endTime - startTime) / 100000);
                    startTime = endTime;
                }
            }
            break;
      }

   }
}



int dealWithIt(int j, streaming chanend c, uchar alteredGrid[IMHT][IMWD/8], uchar grid[IMHT][IMWD/8], int* linesReceived, int* lineToSend, int id){
    //printf("deal with it: start %d\n", id);
    for(int x = 0; x < IMWD / 8; x++){
        c :> alteredGrid[id][x];
    }
    (*linesReceived)++;

    if((*linesReceived) == IMHT){
        // Finished this cycle
        //printf("Deal with it: finished image\n");
        c <: WORKER_WAIT_FOR_NEXT_ROUND;
        return SERVER_FINISH_ROUND;
    }

    if((*lineToSend)+1 >= IMHT) {
        // Do nothing
        //printf("Deal with it: no more image to send out\n");
        c <: WORKER_WAIT_FOR_NEXT_ROUND;
        return SERVER_CONTINUE;
    }else{
        (*lineToSend)++;
        while(gridDoesNotNeedProccessingAsItAndItsNeighboursAreEmpty(grid, lineToSend)==EMPTY && (*lineToSend) < IMHT){
            for(int x = 0; x < IMWD / 8; x++){
                alteredGrid[(*lineToSend)][x] = 0;
            }
            //printf("Deal with it: Line is clear so didn't send\n");
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

 int gridDoesNotNeedProccessingAsItAndItsNeighboursAreEmpty(uchar grid[IMHT][IMWD/8], int* lineToSend){
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



void initWorker(int CPUId, streaming chanend c){
    printf("Worker: (%d): Start...\n", CPUId);

    int lineId;
    uchar startLine[IMWD / 8], midLine[IMWD / 8], endLine[IMWD / 8], newLine[IMWD / 8];

    while(1){

        c :> lineId;


        if(lineId==WORKER_WAIT_FOR_NEXT_ROUND){
            //printf("Worker: WORKER_WAIT_FOR_NEXT_ROUND\n");
            continue;
        }
        //printf("Worker: Before worker given new line data\n");
        for(int x = 0; x < IMWD / 8; x++){
            c :> startLine[x];
        }
        for(int x = 0; x < IMWD / 8; x++){
            c :> midLine[x];
        }
        for(int x = 0; x < IMWD / 8; x++){
            c :> endLine[x];
        }
        //printf("Worker: After worker given new line data\n");






        for(int x = 0; x<IMWD/8; x++){
            newLine[x] = 0;
        }

        for(int x = 0; x<IMWD; x++)
        {

            int l = (x-1+IMWD) % IMWD;
            int r = (x+1) % IMWD;
            int neighbours =
              ((midLine[l/8] >> (7 - (l%8)) ) & 1)
            + ((midLine[r/8] >> (7 - (r%8)) ) & 1)
            + ((startLine[l/8] >> (7 - (l%8)) ) & 1)
            + ((startLine[r/8] >> (7 - (r%8)) ) & 1)
            + ((startLine[x/8] >> (7 - (x%8)) ) & 1)
            + ((endLine[l/8] >> (7 - (l%8)) ) & 1)
            + ((endLine[r/8] >> (7 - (r%8)) ) & 1)
            + ((endLine[x/8] >> (7 - (x%8)) ) & 1);
            int living = ((midLine[x/8] >> (7 - (x%8)) ) & 1);

            if(living==1){
                if(neighbours==2 || neighbours==3){
                   newLine[x/8] += (1 << (7-(x%8)));
                }
            }else if((living!=1)){
                if(neighbours == 3){
                    newLine[x/8] += (1 << (7-(x%8)));
                }
            }
        }
        //printf("Worker: finished line %d\n", lineId);
        c <: lineId;
        //printf("Worker: finished atfer send line %d\n", lineId);

        for(int x = 0; x < IMWD / 8; x++){
            c <: newLine[x];
        }
        //printf("Worker: Sent results of line %d\n", lineId);
    }
}

void DataOutStream(char outfname[], streaming chanend c_in)
{
  int res;
  uchar line[ IMWD ];

  //Open PGM file
  printf( "DataOutStream: Start...\n" );
  res = _openoutpgm( outfname, IMWD, IMHT );
  if( res ) {
    printf( "DataOutStream:Error opening %s\n.", outfname );
    return;
  }

  //Compile each line of the image and write the image line-by-line
  while(1){
      //sync before printout
      int y;
      c_in :> y;
      timer t;
      uint32_t  startTime;
      t :> startTime;
      for( int y = 0; y < IMHT; y++ ) {
        for( int x = 0; x < IMWD; x += 8 ) {
            uchar linePart;
            c_in :> linePart;
            for( int z = 0; z < 8; z++){
                uchar newChar = (uchar)0;
                if(((linePart >> (7 - z)) & 1) == 1){
                    newChar = (uchar)(255);
                }
                line[x + z] = newChar;
                //printf( "%s ", (char) (newChar!=255?"\u25A0":" ") );
            }
        }
       // printf( "\n" );
        _writeoutline( line, IMWD );
      }
      //sync after printout
      c_in :> y;

      uint32_t  endTime;
      t :> endTime;
      printf("Print out time: %d sec\n",(endTime - startTime) / 100000000);

  }



  //Close the PGM image
  _closeoutpgm();
  printf( "DataOutStream:Done...\n" );
  return;
}

void accelerometer(client interface i2c_master_if i2c, chanend toDist) {
    i2c_regop_res_t result;
    char status_data = 0;



  // Configure FXOS8700EQ
  result = i2c.write_reg(FXOS8700EQ_I2C_ADDR, FXOS8700EQ_XYZ_DATA_CFG_REG, 0x01);
  if (result != I2C_REGOP_SUCCESS) {
    printf("I2C write reg failed\n");
  }
  
  // Enable FXOS8700EQ
  result = i2c.write_reg(FXOS8700EQ_I2C_ADDR, FXOS8700EQ_CTRL_REG_1, 0x01);
  if (result != I2C_REGOP_SUCCESS) {
    printf("I2C write reg failed\n");
  }

  //Probe the accelerometer x-axis forever
  while (1) {

    //check until new accelerometer data is available
    do {
      status_data = i2c.read_reg(FXOS8700EQ_I2C_ADDR, FXOS8700EQ_DR_STATUS, result);
    } while (!status_data & 0x08);

    //get new x-axis tilt value
    int x = read_acceleration(i2c, FXOS8700EQ_OUT_X_MSB);

    //send signal to distributor after first tilt
    if (x>30) {
        toDist <: x;

      do {
          do {
                status_data = i2c.read_reg(FXOS8700EQ_I2C_ADDR, FXOS8700EQ_DR_STATUS, result);
              } while (!status_data & 0x08);

              //get new x-axis tilt value
              x = read_acceleration(i2c, FXOS8700EQ_OUT_X_MSB);
      } while (x>30);

      printf("Acc: flat");
      toDist <: x;

    }
  }
}

void buttonListener(in port b, chanend toUserAnt) {
  int r;
  while (1) {
    b when pinseq(15)  :> r;    // check that no button is pressed
    b when pinsneq(15) :> r;    // check if some buttons are pressed
    if ((r==13) || (r==14))     // if either button is pressed
    toUserAnt <: r;             // send button pattern to userAnt
  }
}

/*
void readFileSize(const char *filename, chanend fileSizeChan){
    FILE* f = fopen(filename, "r");
    int i;
    int j;
    fscanf(f, "P5\n%d %d", &i, &j);

    fileSizeChan :> i;
    fileSizeChan :> j;

    fclose(f);
}
*/

int main(void) {

  i2c_master_if i2c[1];               //interface to accelerometer

  chan c_acc;
  streaming chan c_inIO, c_outIO;    //extend your channel definitions here
  streaming chan workerChans[NUMCPUs];
  chan buttonsChan;


  par {
    //on tile[0]: readFileSize("test.pgm", fileSizeChan);
    on tile[0]: i2c_master(i2c, 1, p_scl, p_sda, 10);   //server thread providing accelerometer data
    on tile[0]: accelerometer(i2c[0],c_acc);        //client thread reading accelerometer data
    on tile[0]: DataInStream("512x512.pgm", c_inIO);          //thread to read in a PGM image
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
