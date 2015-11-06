// COMS20001 - Cellular Automaton Farm - Initial Code Skeleton
// (using the XMOS i2c accelerometer demo)

#include <platform.h>
#include <xs1.h>
#include <stdio.h>
#include "pgmIO.h"
#include "i2c.h"

#define  IMHT 16                  //image height
#define  IMWD 16                  //image width

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

typedef interface FinishedInterface {
    {int, uchar[IMWD / 8], uchar[IMWD / 8], uchar[IMWD / 8]} hasFinished(int resultId, uchar resultData[IMWD / 8]);
} FinishedInterface;

void initServer(server FinishedInterface serverInterface, uchar grid[IMHT][IMWD / 8]);
void initWorker(int id, client FinishedInterface clientInterface, uchar startLine[IMWD / 8], uchar midLine[IMWD / 8], uchar endLine[IMWD / 8]);



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
    for( int x = 0; x < IMWD; x += 8 ) { //go through each pixel per line
      c_in :> val;                    //read the pixel value

      grid[y][x] = val;

      //c_out <: (uchar)( val ^ 0xFF ); //send some modified pixel out
    }
  }
  printf( "\nOne processing round completed...\n" );

  interface FinishedInterface finishedInterface;
  initServer(finishedInterface, grid);
  par (int i = 0; i < 10; i++){
      initWorker(i, finishedInterface, grid[i-1 % 16], grid[i], grid[i+1 % 16]);
  }



}
void initServer(server FinishedInterface serverInterface, uchar grid[IMHT][IMWD / 8]){
    uchar alteredGrid[IMHT][IMWD / 8];
    int linesReceived = 0, lineToSend = 9;
    int started = 1;
    while(started){
        select {
            case serverInterface.hasFinished(int id, uchar result[IMWD / 8]):
                alteredGrid[id] = result;

                // Check for finish
                linesReceived++;
                if(linesReceived == IMHT){
                    // Finished this cycle
                    printf("Finished Cycle");
                    return (-1, null, null, null);

                } else if(lineToSend == IMHT) {
                    // Do nothing
                    printf("All lines sent");
                    return (-1, null, null, null);
                } else {
                    lineToSend++;
                    printf("New Worker %d", lineToSend);
                    return (lineToSend, grid[lineToSend - 1 % 16], grid[lineToSend % 16], grid[lineToSend % 16]);
                }
            break;

        }
    }
}
void initWorker(int id, client FinishedInterface clientInterface, uchar startLine[IMWD / 8], uchar midLine[IMWD / 8], uchar endLine[IMWD / 8]){
    uchar newLine[IMWD / 8];
    for(int x = 0; x<IMWD/8; x++){
        newLine[x] = 0;
    }
    int started = 1;
    while(started){
        // do calculationsss...
        for(int x = 0; x<IMWD; x++)
        {
            int l = (x-1) % IMWD;
            int r = (x+1) % IMWD;
            int neighbours =
              ((midline[l/8] >> (7 - (l%8)) ) && 1)
            + ((midline[r/8] >> (7 - (r%8)) ) && 1)
            + ((startLine[l/8] >> (7 - (l%8)) ) && 1)
            + ((startLine[r/8] >> (7 - (r%8)) ) && 1)
            + ((startLine[x/8] >> (7 - (x%8)) ) && 1)
            + ((endLine[l/8] >> (7 - (l%8)) ) && 1)
            + ((endLine[r/8] >> (7 - (r%8)) ) && 1)
            + ((endLine[x/8] >> (7 - (x%8)) ) && 1);
            //x living
            int living = ((midline[x/8] >> (7 - (x)) ) && 1);
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

        {id, startLine, midLine, endLine} = clientInterface.hasFinished(id, newLine);
        if (id == -1){
            break;
        }
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
