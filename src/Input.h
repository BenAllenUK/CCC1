/*
 * Input.h
 *
 *  Created on: Dec 6, 2015
 *      Author: samuel
 */


#ifndef INPUT_H_
#define INPUT_H_
#include "i2c.h"
void accelerometer(client interface i2c_master_if i2c, chanend toDist);
void buttonListener(in port b, chanend toUserAnt);

#endif /* INPUT_H_ */
