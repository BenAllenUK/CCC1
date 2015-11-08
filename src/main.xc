// COMS20001 - Cellular Automaton Farm - Initial Code Skeleton
// (using the XMOS i2c accelerometer demo)

#include <platform.h>
#include <xs1.h>
#include <stdio.h>
#include "pgmIO.h"
#include "i2c.h"

#define  IMHT 16                  //image height
#define  IMWD 16                  //image width
#define  NUMCPUs 4



typedef unsigned char uchar;      //using uchar as shorthand

port p_scl = XS1_PORT_1E;         //interface ports to accelerometer
port p_sda = XS1_PORT_1F;

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



void initServer( chanend workers[NUMCPUs], uchar grid[IMHT][IMWD / 8], int* linesReceived, int* lineToSend, uchar alteredGrid[IMHT][IMWD / 8]);
void initWorker(int CPUId, chanend c);
void dealWithIt(int j, chanend c, uchar alteredGrid[IMHT][IMWD / 8], uchar grid[IMHT][IMWD / 8], int* linesReceived, int* lineToSend);




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

/////////////////////////////////////////////////////////////////////////////////////////
//
// Start your implementation by changing this function to implement the game of life
// by farming out parts of the image to worker threads who implement it...
// Currently the function just inverts the image
//
/////////////////////////////////////////////////////////////////////////////////////////
void distributor(chanend c_in, chanend c_out, chanend fromAcc)
{
  uchar val;
  uchar grid[IMHT][IMWD / 8];

  //Starting up and wait for tilting of the xCore-200 Explorer
  printf( "ProcessImage:Start, size = %dx%d\n", IMHT, IMWD );
  printf( "Waiting for Board Tilt...\n" );
  fromAcc :> int value;

  //Read in and do something with your image values..
  //This just inverts every pixel, but you should
  //change the image according to the "Game of Life"
  printf( "Processing...\n" );
  for( int y = 0; y < IMHT; y++ ) {   //go through all lines
    for( int x = 0; x < IMWD/8; x++ ) { //go through each pixel per line
      c_in :> val;                    //read the pixel value

      grid[y][x] = val;

      //c_out <: (uchar)( val ^ 0xFF ); //send some modified pixel out
    }
  }
  printf( "One processing round completed...\n" );
  uchar alteredGrid[IMHT][IMWD / 8];

  chan workerChans[NUMCPUs];
  int linesReceived = 0;
  int lineToSend = -1;
#ifdef DEBUG
  printf( "Before par\n" );
#endif
  par{
      initServer( workerChans, grid, &linesReceived, &lineToSend, alteredGrid);

      par (int i = 0; i < NUMCPUs; i++){
          initWorker(i, workerChans[i]);
      }
  }
#ifdef DEBUG
  printf("Finished\n");
#endif
  //printing out
  printf("Original\n");

  for( int y = 0; y < IMHT; y++ ) {   //go through all lines
        for( int x = 0; x < IMWD/8; x++ ) { //go through each pixel per line
           c_out <: grid[y][x]; //send some modified pixel out
        }
  }
  c_out <: 0;

  printf("Updated\n");

  for( int y = 0; y < IMHT; y++ ) {   //go through all lines
      for( int x = 0; x < IMWD/8; x++ ) { //go through each pixel per line
         c_out <: alteredGrid[y][x]; //send some modified pixel out
      }
  }
}
void initServer(chanend workers[NUMCPUs], uchar grid[IMHT][IMWD / 8], int* linesReceived, int* lineToSend, uchar alteredGrid[IMHT][IMWD / 8]){
    #ifdef DEBUG
    printf("Start of Server\n");
    #endif
    for(int i = 0; i < NUMCPUs; i++){
          (*lineToSend)++;
          #ifdef DEBUG
          printf("Server: Beginning of %d loop\n", (*lineToSend));
          #endif
          workers[i] <: (*lineToSend);
          for(int x = 0; x < IMWD / 8; x++){
              workers[i] <: grid[((*lineToSend) - 1 ) & (16-1)][x];
          }
          for(int x = 0; x < IMWD / 8; x++){
              workers[i] <: grid[((*lineToSend)) & (16-1)][x];
          }
          for(int x = 0; x < IMWD / 8; x++){
              workers[i] <: grid[((*lineToSend) + 1 ) & (16-1)][x];
          }
          #ifdef DEBUG
          printf("Server: After sending Date\n");
          #endif
      }


    int running = 1;
    while(running){
        select {
            case workers[int j] :> int id:
                if(id == -1){
                    running = 0;
                }else{
                    #ifdef DEBUG
                    printf("Server: Interface Called by CPU:%d\n", j);
                    #endif
                    dealWithIt(j, workers[j], alteredGrid, grid, linesReceived, lineToSend);
                }
                break;
        }
    }
}

void dealWithIt(int j, chanend c, uchar alteredGrid[IMHT][IMWD / 8], uchar grid[IMHT][IMWD / 8], int* linesReceived, int* lineToSend){
    #ifdef DEBUG
    printf("Start of dealWithIt for %d\n", j);
    #endif
    int id;
    c :> id;
    #ifdef DEBUG
    printf("Server: after ID recieved for %d\n", j);
    #endif
    for(int x = 0; x < IMWD / 8; x++){
        c :> alteredGrid[id][x];
    }
    (*linesReceived)++;
    // Check for finish
    #ifdef DEBUG
    printf("Server: after data recieved for %d\n", j);
    #endif
    if((*linesReceived) == IMHT){
        // Finished this cycle
        #ifdef DEBUG
        printf("All lines recieved - by %d\n", j);
        #endif
        c <: -2;
    }else if((*lineToSend)+1 == IMHT) {
        // Do nothing
        #ifdef DEBUG
        printf("All lines sent - by %d\n", j);
        #endif
        c <: -1;
    }else{
        (*lineToSend)++;
        #ifdef DEBUG
        printf("Server: Beginning of loops for %d\n", j);
        #endif
        c <: (*lineToSend);
        for(int x = 0; x < IMWD / 8; x++){
            c <: grid[(*lineToSend - 1 ) & (16-1)][x];
        }
        for(int x = 0; x < IMWD / 8; x++){
            c <: grid[(*lineToSend) & (16-1)][x];
        }
        for(int x = 0; x < IMWD / 8; x++){
            c <: grid[(*lineToSend + 1 ) & (16-1)][x];
        }
    }
}

void initWorker(int CPUId, chanend c){
    int lineId;
    uchar startLine[IMWD / 8];
    uchar midLine[IMWD / 8];
    uchar endLine[IMWD / 8];
    uchar newLine[IMWD / 8];
    #ifdef DEBUG
    printf("Worker %d: before recieving data\n", CPUId);
    #endif

    c :> lineId;
    #ifdef DEBUG
    printf("Worker %d: recieved lineId %d\n", CPUId, lineId);
    #endif
    for(int x = 0; x < IMWD / 8; x++){
        c :> startLine[x];
    }
    for(int x = 0; x < IMWD / 8; x++){
        c :> midLine[x];
    }
    for(int x = 0; x < IMWD / 8; x++){
        c :> endLine[x];
    }
    #ifdef DEBUG
    printf("Worker %d: after recieving data\n", CPUId);
    #endif

    int started = 1;
    while(started){
        for(int x = 0; x<IMWD/8; x++){
            newLine[x] = 0;
        }
        // do calculationsss...
        for(int x = 0; x<IMWD; x++)
        {
            int l = (x-1) % IMWD;
            int r = (x+1) % IMWD;
            int neighbours =
              ((midLine[l/8] >> (7 - (l%8)) ) && 1)
            + ((midLine[r/8] >> (7 - (r%8)) ) && 1)
            + ((startLine[l/8] >> (7 - (l%8)) ) && 1)
            + ((startLine[r/8] >> (7 - (r%8)) ) && 1)
            + ((startLine[x/8] >> (7 - (x%8)) ) && 1)
            + ((endLine[l/8] >> (7 - (l%8)) ) && 1)
            + ((endLine[r/8] >> (7 - (r%8)) ) && 1)
            + ((endLine[x/8] >> (7 - (x%8)) ) && 1);
            //x living
            int living = ((midLine[x/8] >> (7 - (x)) ) && 1);
            if(living){
                if(neighbours==2 || neighbours==3){
                   newLine[x/8] += (1 << (7-x));
                }
            }else if(!(living)){
                if(neighbours == 3){
                    newLine[x/8] += (1 << (7-x));
                }
            }
        }
        #ifdef DEBUG
        printf("Worker %d: before interface called\n", CPUId);
        #endif

        c <: 1;
        #ifdef DEBUG
        printf("Worker %d: after interface called\n", CPUId);
        #endif
        #ifdef DEBUG
        printf("Worker %d: About to send LineID: \n", CPUId, lineId);
        #endif
        c <: lineId;
        for(int x = 0; x < IMWD / 8; x++){
            c <: newLine[x];
        }

        c :> lineId;
        #ifdef DEBUG
        printf("Worker %d: after recieved Id/Code\n", CPUId);
        #endif

        if(lineId==-1){
            started = 0;
            #ifdef DEBUG
            printf("Worker %d: Killed\n", CPUId);
            #endif
            break;
        }else if(lineId==-2){
            c <: -1;
            #ifdef DEBUG
            printf("Worker %d: and Server Killed\n", CPUId);
            #endif
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
        #ifdef DEBUG
        printf("Worker %d: after recieved Data\n", CPUId);
        #endif
    }
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Write pixel stream from channel c_in to PGM image file
//
/////////////////////////////////////////////////////////////////////////////////////////
void DataOutStream(char outfname[], chanend c_in)
{
  int res;
  uchar line[ IMWD ];

  //Open PGM file
  printf( "DataOutStream:Start...\n" );
  res = _openoutpgm( outfname, IMWD, IMHT );
  if( res ) {
    printf( "DataOutStream:Error opening %s\n.", outfname );
    return;
  }

  //Compile each line of the image and write the image line-by-line
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

  c_in :> int y;

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

  //Close the PGM image
  _closeoutpgm();
  printf( "DataOutStream:Done...\n" );
  return;
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Initialise and  read accelerometer, send first tilt event to channel
//
/////////////////////////////////////////////////////////////////////////////////////////
void accelerometer(client interface i2c_master_if i2c, chanend toDist) {
  i2c_regop_res_t result;
  char status_data = 0;
  int tilted = 0;

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
    if (!tilted) {
      if (x>10) {
        tilted = 1 - tilted;
        toDist <: 1;
      }
    }
  }
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Orchestrate concurrent system and start up all threads
//
/////////////////////////////////////////////////////////////////////////////////////////
int main(void) {

  i2c_master_if i2c[1];               //interface to accelerometer

  char infname[] = "test.pgm";     //put your input image path here
  char outfname[] = "testout.pgm"; //put your output image path here
  chan c_inIO, c_outIO, c_control;    //extend your channel definitions here

  par {
    i2c_master(i2c, 1, p_scl, p_sda, 10);   //server thread providing accelerometer data
    accelerometer(i2c[0],c_control);        //client thread reading accelerometer data
    DataInStream(infname, c_inIO);          //thread to read in a PGM image
    DataOutStream(outfname, c_outIO);       //thread to write out a PGM image
    distributor(c_inIO, c_outIO, c_control);//thread to coordinate work on image
  }

  return 0;
}
