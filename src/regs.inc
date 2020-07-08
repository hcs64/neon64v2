// Global register assignments

constant at(1)
constant cycle_balance(2) // v0
constant v1(3)
// args
constant a0(4)
constant a1(5)
constant a2(6)
constant a3(7)
constant t0(8)
constant t1(9)
constant t2(10)
constant t3(11)
constant t4(12)
constant cpu_t0(13)   // t5
constant cpu_t1(14)   // t6
constant cpu_t2(15)   // t7
constant cpu_mpc(16)  // s0
constant cpu_acc(17)  // s1
constant cpu_x(18)    // s2
constant cpu_y(19)    // s3
constant ppu_vaddr(20) // s4
constant ppu_t0(21)   // s5
constant ppu_t1(22)   // s6
constant ppu_t2(23)   // s7
constant t8(24)
constant t9(25)
constant k0(26)
constant k1(27)
constant gp(28)
constant sp(29)
constant s8(30)
constant ra(31)

// The RSP can use these even if they're dedicated on the CPU
constant sp_v0(2)
constant sp_t5(13)
constant sp_t6(14)
constant sp_t7(15)
constant sp_s0(16)
constant sp_s1(17)
constant sp_s2(18)
constant sp_s3(19)
constant sp_s4(20)
constant sp_s5(21)
constant sp_s6(22)
constant sp_s7(23)
