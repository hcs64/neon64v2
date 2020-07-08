#include <stdio.h>
#include <stdint.h>

int main(void) {
  for (int c = 0; c <= 0xff; c++) {
    int d = 0;
    printf("  db 0b");
    for (int i = 0; i < 8; i++) {
      if (i == 4) {
        printf("'");
      }
      printf("%c", c & (1<<i) ? '1' : '0');
    }
    printf("\n");
  }
}
