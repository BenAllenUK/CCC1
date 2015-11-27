// COMS20001 - Cellular Automaton Farm - Initial Code Skeleton
// (using the XMOS i2c accelerometer demo)

#include <platform.h>
#include <xs1.h>
#include <print.h>
#include <stdio.h>
#include "pgmIO.h"
#include "i2c.h"

#define  IMHT 16                  //image height
#define  IMWD 16                  //image width
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

#define STOP_WORKER -1
#define FINISH_SERVER -2
#define CONTINUE_SERVER 1

#define EMPTY -1
#define NOT_EMPTY 0

void initServer( chanend workers[NUMCPUs], uchar grid[IMHT][IMWD/8], int* linesReceived, int* lineToSend, uchar alteredGrid[IMHT][IMWD/8]);
void initWorker(int CPUId, chanend c);
void dealWithIt(int j, chanend c, uchar alteredGrid[IMHT][IMWD/8], uchar grid[IMHT][IMWD/8], int* linesReceived, int* lineToSend);
void sendData(chanend c, uchar grid[IMHT][IMWD/8], int* lineToSend);
int gridDoesNotNeedProccessingAsItAndItsNeighboursAreEmpty(uchar grid[IMHT][IMWD/8], int* lineToSend);

int indexer(int y, int x){
    return y*IMWD + x;
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Read Image from PGM file from path infname[] to channel c_out
//
/////////////////////////////////////////////////////////////////////////////////////////
void DataInStream(char infname[], chanend c_out)
{
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

void distributor(chanend c_in, chanend c_out, chanend fromAcc, chanend workerChans[NUMCPUs], chanend ledDisplay, chanend btnPress)
{
  printf("Distributor: Start...\nDistributor: Waiting for button press\n");
  uchar val;
  uchar grids[2][IMHT][IMWD / 8];


  int btnResponse;
  btnPress :> btnResponse;

  // Halt processing till button press
  while(btnResponse != 13){
      btnPress :> btnResponse;
  }


  //Starting up and wait for tilting of the xCore-200 Explorer
  printf( "ProcessImage:Start, size = %dx%d\n", IMHT, IMWD );

  ledDisplay <: 4;
  for( int y = 0; y < IMHT; y++) {
    for( int x = 0; x < IMWD/8; x++) {
      c_in :> val;
      grids[0][y][ x] = val;
    }
  }

  printf("Original\n");

  for( int y = 0; y < IMHT; y++) {   //go through all lines
      for( int x = 0; x < IMWD/8; x++) { //go through each pixel per line
             c_out <: grids[0][y][x]; //send some modified pixel out
      }
    }

  int k = 0;
  while(1){
      int linesReceived = 0;
      int lineToSend = -1;
      ledDisplay <: (k%2) << 3;
      initServer(workerChans, grids[k%2] , &linesReceived, &lineToSend, grids[1 - k%2]);
      int btnVal;

      // Accelermeter Pause
      int accResponse;
      fromAcc :> accResponse;
      while(accResponse > 10){
          fromAcc :> accResponse;
          ledDisplay <: 8;
      }

      // Button read
      btnPress :> btnVal;
      if(btnVal == 14){
        //print out and then carry on.
        ledDisplay <: 2;

        printf("Updated\n");
        //sychronise
        c_out <: 0;
        for( int y = 0; y < IMHT; y++ ) {   //go through all lines
            for( int x = 0; x < IMWD/8; x++ ) { //go through each pixel per line
               c_out <: grids[1 - k%2][y][x]; //send some modified pixel out
            }
        }
      }

      k++;
  }

  c_out <: -1;

}

void initServer(chanend workers[NUMCPUs], uchar  grid[IMHT][IMWD/8], int* linesReceived, int* lineToSend, uchar alteredGrid[IMHT][IMWD/8]){
    for(int i = 0; i < NUMCPUs; i++){
          (*lineToSend)++;
          workers[i] <: (*lineToSend);
          for(int x = 0; x < IMWD / 8; x++){
              workers[i] <: grid[((*lineToSend) - 1 ) & (16-1)][ x];
          }
          for(int x = 0; x < IMWD / 8; x++){
              workers[i] <: grid[((*lineToSend)) & (16-1)][x];
          }
          for(int x = 0; x < IMWD / 8; x++){
              workers[i] <: grid[((*lineToSend) + 1 ) & (16-1)][x];
          }
      }


    int running = 1;
    while(running){
        select {
            case workers[int j] :> int stopFlag:
                if(stopFlag == STOP_WORKER){
                    running = 0;
                } else {
                    dealWithIt(j, workers[j], alteredGrid, grid, linesReceived, lineToSend);
                }
                break;
        }
    }
}

void dealWithIt(int j, chanend c, uchar alteredGrid[IMHT][IMWD/8], uchar grid[IMHT][IMWD/8], int* linesReceived, int* lineToSend){
    int id;
    c :> id;
    for(int x = 0; x < IMWD / 8; x++){
        c :> alteredGrid[id][x];
    }
    (*linesReceived)++;

    if((*linesReceived) == IMHT){
        // Finished this cycle
        c <: FINISH_SERVER;
    }else if((*lineToSend)+1 == IMHT) {
        // Do nothing
        c <: STOP_WORKER;
    }else{
        (*lineToSend)++;
        while(gridDoesNotNeedProccessingAsItAndItsNeighboursAreEmpty(grid, lineToSend)==EMPTY){
            for(int x = 0; x < IMWD / 8; x++){
                alteredGrid[(*lineToSend)][x];
            }
            (*linesReceived)++;
            (*lineToSend)++;
        }
        c <: (*lineToSend);
        sendData(c, grid, lineToSend);

    }
}

 int gridDoesNotNeedProccessingAsItAndItsNeighboursAreEmpty(uchar grid[IMHT][IMWD/8], int* lineToSend){
     for(int x = 0; x < IMWD / 8; x++){
         if(grid[(*lineToSend - 1 ) & (16-1)][x] != 0){
             return NOT_EMPTY;
         }
         if((grid[(*lineToSend) & (16-1)])[x] != 0){
             return NOT_EMPTY;
         }
         if((grid[(*lineToSend + 1 ) & (16-1)])[x] != 0){
             return NOT_EMPTY;
         }
     }
     return EMPTY;
 }

void sendData(chanend c, uchar grid[IMHT][IMWD/8], int* lineToSend){
    for(int x = 0; x < IMWD / 8; x++){
        c <: grid[(*lineToSend - 1 ) & (16-1)][ x];
    }
    for(int x = 0; x < IMWD / 8; x++){
        c <: grid[(*lineToSend) & (16-1)][ x];
    }
    for(int x = 0; x < IMWD / 8; x++){
        c <: grid[(*lineToSend + 1 ) & (16-1)][ x];
    }
}

void initWorker(int CPUId, chanend c){
    printf("Worker (%d): Start...\n", CPUId);
    while(1){
        int lineId;
        uchar startLine[IMWD / 8], midLine[IMWD / 8], endLine[IMWD / 8], newLine[IMWD / 8];

        c :> lineId;

        for(int x = 0; x < IMWD / 8; x++){
            c :> startLine[x];
        }
        for(int x = 0; x < IMWD / 8; x++){
            c :> midLine[x];
        }
        for(int x = 0; x < IMWD / 8; x++){
            c :> endLine[x];
        }

        int started = 1;
        while(started){
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

            c <: CONTINUE_SERVER;

            c <: lineId;
            for(int x = 0; x < IMWD / 8; x++){
                c <: newLine[x];
            }

            c :> lineId;


            if(lineId==-1){
                started = 0;

                break;
            }else if(lineId==FINISH_SERVER){
                c <: -1;

                break;
            }
            for(int x = 0; x < IMWD / 8; x++){
                c :> startLine[x];
            }
            for(int x = 0; x < IMWD / 8; x++){
                c :> midLine[x];
            }
            for(int x = 0; x < IMWD / 8; x++){
                c :> endLine[x];
            }

        }

    }
}

void DataOutStream(char outfname[], chanend c_in)
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
                printf( "-%4.1d ", newChar );
            }
            printf( " " );
        }
        printf( "\n" );
        _writeoutline( line, IMWD );
      }
      int y;
      c_in :> y;
      if(y == -1){
          break;
      }
  }



  //Close the PGM image
  _closeoutpgm();
  printf( "DataOutStream:Done...\n" );
  return;
}

void accelerometer(client interface i2c_master_if i2c, chanend toDist) {
  printf("Accelerometer: Start...\n");
  toDist <: 1;
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
    toDist <: x;
  }
}

int showLEDs(out port p, chanend fromVisualiser) {
  int pattern; //1st bit...separate green LED
               //2nd bit...blue LED
               //3rd bit...green LED
               //4th bit...red LED
  while (1) {
    fromVisualiser :> pattern;   //receive new pattern from visualiser
    p <: pattern;                //send pattern to LED port
  }
  return 0;
}

void buttonListener(in port b, chanend responseChan) {
  int r;
  while (1) {
    b when pinseq(15)  :> r;    // check that no button is pressed
    b when pinsneq(15) :> r;    // check if some buttons are pressed// if either button is pressed
    responseChan <: r;             // send button pattern to userAnt
  }
}

int main(void) {

  i2c_master_if i2c[1];               //interface to accelerometer

//  char infname[] = "test.pgm";     //put your input image path here
//  char outfname[] = "testout.pgm"; //put your output image path here

  chan c_inIO, c_outIO, c_control;    //extend your channel definitions here
  chan workerChans[NUMCPUs];
  chan buttonPress, ledDisplay;

  par {
    on tile[0]: i2c_master(i2c, 1, p_scl, p_sda, 10);   //server thread providing accelerometer data
    on tile[0]: accelerometer(i2c[0],c_control);        //client thread reading accelerometer data
    on tile[0]: DataInStream("test.pgm", c_inIO);          //thread to read in a PGM image
    on tile[0]: DataOutStream("testout.pgm", c_outIO);       //thread to write out a PGM image
    on tile[0]: distributor(c_inIO, c_outIO, c_control, workerChans, ledDisplay, buttonPress);//thread to coordinate work on image
    on tile[0]: buttonListener(buttons, buttonPress);
    on tile[0]: showLEDs(leds, ledDisplay);
    par (int i = 0; i < 2; i++){
        on tile[0]: initWorker(i, workerChans[i]);
    }
    par (int i = 0; i < 8; i++){
        on tile[1]: initWorker(i+2, workerChans[i+2]);
    }
  }

  return 0;
}
