// Modified by Princeton University on June 9th, 2015
/*
* ========== Copyright Header Begin ==========================================
* 
* OpenSPARC T1 Processor File: mulerr_frfce_itlb_data.s
* Copyright (c) 2006 Sun Microsystems, Inc.  All Rights Reserved.
* DO NOT ALTER OR REMOVE COPYRIGHT NOTICES.
* 
* The above named program is free software; you can redistribute it and/or
* modify it under the terms of the GNU General Public
* License version 2 as published by the Free Software Foundation.
* 
* The above named program is distributed in the hope that it will be 
* useful, but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
* General Public License for more details.
* 
* You should have received a copy of the GNU General Public
* License along with this work; if not, write to the Free Software
* Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301, USA.
* 
* ========== Copyright Header End ============================================
*/

#define H_HT0_Corrected_ECC_error_0x63 My_Corrected_ECC_error_trap
#define H_HT0_Data_access_error_0x32 My_Data_Access_Error_Trap

#define MAIN_PAGE_HV_ALSO

#define ITLB_ERRINJ_ENTRY   7

#include "boot.s"

.text
.global  main
.global  My_Data_Access_Error_Trap  
.global  My_Corrected_ECC_error_trap

#include "err_defines.h"

.align 64
main:

  ta    T_CHANGE_HPRIV

  ! Enable FPU
  wr    %g0, 0x4, %fprs

  ! Sparc Error Injection Register should power up 0
  ldxa  [%g0] ASI_SEI, %l1
  cmp   %l1, 0
  bne   test_fail
  nop

  ! Sparc Error Status Register powers up X - Write 1 on each bit to clear
  setx  0xefffffff, %l1, %l2
  stxa  %l2, [%g0] ASI_SES
  ldxa  [%g0] ASI_SES, %l1
  setx  SES_INIT_VALUE, %l3, %l2
  cmp   %l1, %l2
  bne   test_fail
  nop

  ! Enable traps on un-correctable Sparc errors
  call  sub_set_see_nceen
  save

  ! Enable disruting Corrected ECC Trap
  call  sub_set_see_ceen
  save

  ! Error Injection Code Below

  ! Set 1-bit XOR in Sparc Error Injection ECC Mask
  ldxa  [%g0] ASI_SEI, %l1
  mov   0x40, %l2
  or    %l1, %l2, %l1
  stxa  %l1, [%g0] ASI_SEI

  ! Set Single Shot
  call  sub_set_sei_sshot
  save

  ! Set IRF ECC error injection bit
  mov   SEI_FRF, %o0
  call  sub_inject_sei_error
  save

  ! Enable Error Injection
  call  sub_set_sei_en
  save

  ! This will update FRF with ECC Mask
  setx  fpd_data, %l0, %l1
  ldd   [%l1], %f4


  ! Make sure data will be read from the resigter file; otherwise %f4 result is by-passed.
  ! Note that %f4 is not windowed, so writing to %cwp would work.
  wrpr  %g0, %cwp

  faddd %f4, %f4, %f4

  ! An Internal Processor Error Trap should happen here
  setx  EXECUTED, %l1, %l0
  cmp   %o0, %l0
  bne   test_fail
  mov   TT_Corrected_ECC, %l0
  cmp   %o1, %l0
  bne   test_fail

  ! Check Sparc Error Status Register
  mov   SES_FRC, %o1
  mov   0x1D, %o2

  setx  SES_INIT_VALUE, %l2, %l1
  mov   0x1, %l2
  sllx  %l2, %o1, %l2
  or    %l1, %l2, %l1
  mov   0x1, %l2
  sllx  %l2, %o2, %l2
  or    %l1, %l2, %l1

  ! Read Sparc Error Status Register
  ldxa  [%g0] ASI_SES, %l0

  cmp   %l0, %l1
  bne   %xcc, test_fail
  nop

  ! Check Sparc Error Address Register

  mov   0x4, %o0              ! %f4 at Index 4
  sllx  %o0, 4, %o0           ! IRF Index at [9:4]
  mov   0x40, %l0             ! Syndrome - bit 6: parity
  sllx  %l0, 24, %l1          ! Syndrome for even half of register
  or    %o0, %l1, %o0
  sllx  %l0, 16, %l1          ! Syndrome for odd half of register
  or    %o0, %l1, %o0
  setx  0x7f7f03f0, %l0, %o1  ! Mask
  call  sub_check_sparc_error_address
  save


  ! ITLB data parity error Injection Code Below

  ! Clear the error injection register
  mov 	%g0, %l1
  stxa  %l1, [%g0] ASI_SEI

  ! Set Single Shot
  call  sub_set_sei_sshot
  save

  ! Set FRF ECC error injection bit
  mov   SEI_IMD, %o0
  call  sub_inject_sei_error
  save

  ! Enable Error Injection
  call  sub_set_sei_en
  save

 ! Write to DTLB
  call  sub_itlb_write
  save

 ! Read back ITLB entry just written
  mov   ITLB_ERRINJ_ENTRY, %l7
  sllx  %l7, 0x3, %l7
  ldxa  [%l7] ASI_ITLB_TAG_READ, %l6
  setx  0x166000, %l0, %l1
  cmp   %l1, %l6
  bne   test_fail
  nop

error_address:
  ldxa  [%l7] ASI_ITLB_DATA_ACCESS, %l7




  ! There should be trap here - check if it happened
  setx  EXECUTED, %l1, %l0
  cmp   %o0, %l0
  bne   test_fail
  ! Check Trap Type
  mov   TT_Data_Access_Error, %l0
  cmp   %o1, %l0
  bne   test_fail

  ! Check Sparc Error Address Register, The previous error should be overwritten
  mov   ITLB_ERRINJ_ENTRY, %o0
  sllx  %o0, 4, %o0
  mov   0xff0, %o1  ! Mask
  call  sub_check_sparc_error_address
  save

  ! Check Sparc Error Status Register
  mov   0x1, %o0   ! (MEU, MEC, PRIV)
  mov   SES_FRC, %o1
  mov   SES_IMDU, %o2

  setx  SES_INIT_VALUE, %l2, %l1
  sllx  %o0, 29, %o0
  or    %l1, %o0, %l1
  mov   0x1, %l2
  sllx  %l2, %o1, %l2
  or    %l1, %l2, %l1
  mov   0x1, %l2
  sllx  %l2, %o2, %l2
  or    %l1, %l2, %l1

  ! Read Sparc Error Status Register
  ldxa  [%g0] ASI_SES, %l0

  cmp   %l0, %l1
  bne   %xcc, test_fail
  nop




  ba    test_pass
  nop

#include "err_subroutines.s"

sub_itlb_write:

  setx  itlb_entry, %l1, %l2
  ldda  [%l2] ASI_NUCLEUS_QUAD_LDD, %l4  ! Load the entry to write into itlb

  mov   VA_ASI_ITLB_TAG_ACCESS, %l6
  mov   ITLB_ERRINJ_ENTRY, %l7
  sllx  %l7, 0x3, %l7

  stxa  %l4, [%l6] ASI_IMMU      ! Tag portion
  stxa  %l5, [%l7] ASI_ITLB_DATA_ACCESS

  ret
  restore


My_Corrected_ECC_error_trap:
  ! Signal trap taken
  setx  EXECUTED, %l0, %o0
  ! save trap type value
  rdpr  %tt, %o1
  retry

My_Data_Access_Error_Trap:
  ! Signal trap taken
  setx  EXECUTED, %l0, %o0
  ! save trap type value
  rdpr  %tt, %o1
  ! Write ITLB again -- this time there should be no error (single shot error injection)
  call sub_itlb_write
  save
  nop
  retry



/*******************************************************
 * Exit code
 *******************************************************/

test_pass:
ta	T_GOOD_TRAP

test_fail:
ta	T_BAD_TRAP

.data

itlb_entry:
  .xword  0x0000000000166000,  0x8000000100166001

fpd_data:
  ! Floating Point Double data (1.25 * [2 to the 20])
  .xword  0x4130000000000019


test_data:
  .xword  0x1004abba00000000

