#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>

#define FONT_SIZE (256*8)

int main(int argc, char **argv) {
  FILE *infile, *outfile;

  if (argc != 3) {
    fprintf(stderr, "usage: %s in-font.bin out-font.bin\n", argv[0]);
    return -1;
  }
  infile = fopen(argv[1], "rb");
  if (!infile) {
    perror("input open failed");
    return -1;
  }
  outfile = fopen(argv[2], "wb");
  if (!outfile) {
    perror("output open failed");
    return -1;
  }

  uint8_t *inbytes = calloc(FONT_SIZE, 1);
  uint8_t *outbytes = calloc(FONT_SIZE, 1);
  if (!inbytes || !outbytes) {
    perror("alloc failed");
    return -1;
  }

  if (fread(inbytes, FONT_SIZE, 1, infile) != 1) {
    fprintf(stderr, "read failed\n");
    return -1;
  }
  fclose(infile); infile = NULL;

  // notation: 7aA = #col=7, row=a, Tile=A
  // IN:
  // 7aA,6aA,5aA,4aA,3aA,2aA,1aA,0aA
  // 7bA,6bA,5bA,4bA,3bA,2bA,1bA,0bA
  // 7cA,6cA,5cA,4cA,3cA,2cA,1cA,0cA
  // 7dA,6dA,5dA,4dA,3dA,2dA,1dA,0dA
  // 7eA,6eA,5eA,4eA,3eA,2eA,1eA,0eA
  // 7fA,6fA,5fA,4fA,3fA,2fA,1fA,0fA
  // 7gA,6gA,5gA,4gA,3gA,2gA,1gA,0gA
  // 7hA,6hA,5hA,4hA,3hA,2hA,1hA,0hA
  //
  // 7aB,...
  //
  // 7aC,...
  //
  // 7aD,...
  //
  // OUT:
  // 7aD,7aC,7aB,7aA 6aD,6aC,6aB,6aA
  // 5aD,5aC,5aB,5aA 4aD,4aC,4aB,4aA
  // 3aD,3aC,3aB,3aA 2aD,2aC,2aB,2aA
  // 1aD,1aC,1aB,1aA 0aD,0aC,0aB,0aA
  //
  // ... row a of all other tiles
  //
  // 7bD,7bC,7bB,7bA 6bD,6bC,6bB,6bA
  // 5bD,5bC,5bB,5bA 4bD,4bC,4bB,4bA
  // 3bD,3bC,3bB,3bA 2bD,2bC,2bB,2bA
  // 1bD,1bC,1bB,1bA 0bD,0bC,0bB,0bA
  //
  // ...

  for (unsigned int row = 0; row < 8; row += 1) {
   for (unsigned int i = 0; i < FONT_SIZE; i += 8*4) {
      for (unsigned int col = 0; col < 8; col += 1) {
        for (unsigned int tile = i/8; tile < i/8+4; tile += 1) {
          uint8_t pix = (inbytes[(tile*8)+row]>>col)&1;
          outbytes[(tile/4*4)+((7-col)/2)+(row*256)] |= pix<<((tile%4)+((col%2)*4));
        }
      }
    }
  }

  if (fwrite(outbytes, FONT_SIZE, 1, outfile) != 1 || fclose(outfile) == EOF) {
    fprintf(stderr, "write failed\n");
    return -1;
  }
  outfile =  NULL;

  free(inbytes);
  free(outbytes);
}
