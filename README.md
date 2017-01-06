# Cellular Automaton Farm
The British mathematician John Horton Conway
devised a cellular automaton named ‘The Game of Life’. The "Game"
resides on a 2-valued 2D matrix, i.e. a binary image, where the
matrix entries (call them cells, picture elements or pixels) can either
be ‘alive’ (value white 255) or ‘dead’ (value black 0). The game
evolution is determined by its initial state and requires no further
input. Every cell interacts with its eight neighbour pixels, that is cells
that are horizontally, vertically, or diagonally adjacent. At each step
in time, the following transitions may occur:
• any live cell with fewer than two live neighbours dies
• any live cell with two or three live neighbours is unaffected
• any live cell with more than three live neighbours dies
• any dead cell with exactly three live neighbours becomes alive
Consider the image to be on a closed domain (pixels on the top row
are connected to pixels at the bottom row, pixels on the right are
connected to pixels on the left and vice versa). A user can only
interact with the Game of Life by creating an initial configuration
and observing how it evolves. Evolving complex, deterministic
systems is an important application of scientific computing, often
making use of parallel architectures and concurrent programs
running on large computing farms. Subjects as diverse as molecular
biology, meteorology, biochemistry and aerospace engineering rely
on simulations of this kind…

Aim: To design and implement a small process
farm on the xCore-200 Explorer board which simulates the ‘Game of
Life’ on an image matrix. The board’s buttons, accelerometer, and
LEDs should be used to control and visualise aspects of the game.
The game matrix should be initialised from a PGM image file and the
user should be able to export the game matrix as PGM image files.
Your solution should make efficient and effective use of the
available parallel hardware of the architecture by implementing
farming and communication of parts of the game matrix across
several cores based on message passing.
