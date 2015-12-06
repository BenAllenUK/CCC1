#include "Worker.h"
#include <platform.h>
#include <xs1.h>
#include <print.h>
#include <stdio.h>

#define WORKER_WAIT_FOR_NEXT_ROUND -1
#define SERVER_CONTINUE 1
#define SERVER_FINISH_ROUND 0
#define WORKER_SENT 1

#define EMPTY -1
#define NOT_EMPTY 0

#define PERFORM_LINE_OPTIMIZATION 1
#define PERFORM_CHAR_OPTIMIZATION 1

typedef unsigned char uchar;
#define  IMHT 128
#define  IMWD 128

void initWorker(int CPUId, streaming chanend c){
    printf("Worker: (%d): Start...\n", CPUId);

    int lineId;
    uchar startLine[IMWD / 8], midLine[IMWD / 8], endLine[IMWD / 8], newLine[IMWD / 8];

    while(1){

        c :> lineId;


        if(lineId==WORKER_WAIT_FOR_NEXT_ROUND){
            continue;
        }
        //read in data
        for(int x = 0; x < IMWD / 8; x++){
            c :> startLine[x];
        }
        for(int x = 0; x < IMWD / 8; x++){
            c :> midLine[x];
        }
        for(int x = 0; x < IMWD / 8; x++){
            c :> endLine[x];
        }
        //clear space result for result
        for(int x = 0; x<IMWD/8; x++){
            newLine[x] = 0;
        }

        for(int x = 0; x<IMWD; x++)
        {
            int l = (x-1+IMWD) % IMWD;

            int r = (x+1) % IMWD;
            int shouldProcessBlock = 1;
            // If we are at a new char then
            if(x % 8 == 0 && PERFORM_CHAR_OPTIMIZATION == 1){
                // Test to see whether any of the neighbours have values in them
                int nextCharIndex = ((x / 8) + 1 ) % (IMWD / 8);
                int verticalNeighbours
                                    = ((startLine[l/8] >> 0) & 1);
                verticalNeighbours += ((midLine[l/8] >> 0) & 1);
                verticalNeighbours += ((endLine[l/8] >> 0) & 1);
                verticalNeighbours += ((startLine[nextCharIndex] >> 7) & 1);
                verticalNeighbours += ((midLine[nextCharIndex] >> 7) & 1);
                verticalNeighbours += ((endLine[nextCharIndex] >> 7) & 1);
                // If neighbours dont have characters in them then
                if(midLine[x/8] == 0 && startLine[x/8] == 0 && endLine[x/8] == 0 && verticalNeighbours == 0){
                    // Skip to next character block
                    x+= 7;
                    shouldProcessBlock = 0;
                }

            }
            // Otherwise we should process this symbol set
            if(shouldProcessBlock == 1){
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
        }
        //send back line
        c <: lineId;

        for(int x = 0; x < IMWD / 8; x++){
            c <: newLine[x];
        }
    }
}
