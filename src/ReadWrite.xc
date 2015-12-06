#include "ReadWrite.h"
#include <platform.h>
#include <xs1.h>
#include <print.h>
#include <stdio.h>
#include "i2c.h"
#include "pgmIO.h"
typedef unsigned char uchar;
#define  IMHT 128
#define  IMWD 128
void DataInStream(char infname[], chanend c_out)
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

void DataOutStream(char outfname[], chanend c_in)
{


  //Compile each line of the image and write the image line-by-line
  while(1){

      //sync before printout
      int y;
      c_in :> y;
      timer t;
      uint32_t  startTime;
      t :> startTime;

      int res;
      uchar line[ IMWD ];

      //Open PGM file
      printf( "DataOutStream: Start...\n" );
      res = _openoutpgm( outfname, IMWD, IMHT );
      if( res ) {
        printf( "DataOutStream:Error opening %s\n.", outfname );
        return;
      }


      for( int y = 0; y < IMHT; y++ ) {
        for( int x = 0; x < IMWD; x += 8 ) {
            uchar linePart;
            c_in :> linePart;
            if(IMWD-x < 8){
                for( int z = 0; z < IMWD-x; z++){
                    uchar newChar = (uchar)0;
                    if(((linePart >> (7 - z)) & 1) == 1){
                        newChar = (uchar)(255);
                    }
                    line[x + z] = newChar;
                }
            }else{
                for( int z = 0; z < 8; z++){
                    uchar newChar = (uchar)0;
                    if(((linePart >> (7 - z)) & 1) == 1){
                        newChar = (uchar)(255);
                    }
                    line[x + z] = newChar;
                }
            }

        }
      _writeoutline( line, IMWD );
      }
      //sync after printout
      c_in :> y;

      //Close the PGM image
       _closeoutpgm();

      uint32_t  endTime;
      t :> endTime;
      printf("Print out time: %d sec\n",(endTime - startTime) / 100000000);

  }


  printf( "DataOutStream:Done...\n" );
  return;
}
