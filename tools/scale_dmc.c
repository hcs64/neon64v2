#include <stdio.h>
#include <stdint.h>
#include <inttypes.h>

const unsigned int NTSC_CPU_DIV = 12;
const unsigned int PAL_CPU_DIV = 16;

uint16_t ntsc[16] = {
  428, 380, 340, 320, 286, 254, 226, 214,
  190, 160, 142, 128, 106,  84,  72,  54
};

uint16_t pal[16] = {
  398, 354, 316, 298, 276, 236, 210, 198,
  176, 148, 132, 118,  98,  78,  66,  50
};

void print_table(uint16_t p[16], unsigned int cpu_div) {
  printf("dmc_rate_table:\n");

  for (unsigned int i = 0; i < 16; ++i) {
    if ((i & 7) == 0) {
      printf("  dh ");
    }

    printf("%5" PRIu16, p[i]);

    if (((i+1)&7) == 0) {
      printf("\n");
    } else {
      printf(",");
    }
  }

  printf("\ndmc_cycle_table:\n");

  for (unsigned int i = 0; i < 16; ++i) {
    if ((i & 7) == 0) {
      printf("  dh ");
    }

    printf("%7" PRIu16, p[i] * cpu_div * 8);

    if (((i+1)&7) == 0) {
      printf("\n");
    } else {
      printf(",");
    }
  }
}

int main(void) {
  printf("// NTSC\n");
  print_table(ntsc, NTSC_CPU_DIV);
  printf("\n\n// PAL\n");
  print_table(pal, PAL_CPU_DIV);
}
