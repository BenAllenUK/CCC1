./.build/src/Input.xc.o: ./src/main.xc
./.build/src/ReadWrite.xc.o: ./src/main.xc
./.build/src/Worker.xc.o: ./src/main.xc
./.build/_l_i2c/src/i2c_master_async.xc.o: ./src/main.xc ./src/ReadWrite.xc
./.build/_l_i2c/src/i2c_slave.xc.o: ./src/Input.xc ./src/main.xc ./src/ReadWrite.xc /home/samuel/workspace/lib_i2c/src/i2c_master_single_port.xc ./src/Worker.xc /home/samuel/workspace/lib_i2c/src/i2c_master_ext.xc /home/samuel/workspace/lib_i2c/src/i2c_master_async.xc /home/samuel/workspace/lib_i2c/src/i2c_master.xc
./.build/_l_xassert/src/xassert.xc.o: /home/samuel/workspace/lib_i2c/src/i2c_master_single_port.xc /home/samuel/workspace/lib_i2c/src/i2c_master_async.xc
./.build/_l_i2c/src/i2c_master.xc.o: ./src/Input.xc ./src/main.xc /home/samuel/workspace/lib_i2c/src/i2c_master_async.xc
