#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#define assert(expression) \
    do { if(!(expression)) { \
        console_printf("Assertion failed: " _PDCLIB_symbol2string(expression)\
                         ", function ", __func__,                         \
                         ", file " __FILE__ \
                         ", line " _PDCLIB_symbol2string( __LINE__ ) \
                         "." _PDCLIB_endl ); \
        while(1);                          \
      } \
    } while(0)

#include "serial.h"
#include "console.h"
#include "atags.h"
#include "armpte.h"
#include <kevlar/memregions.h>

#define ROUND_UP(N, S) ((((N) + (S) - 1) / (S)) * (S))

#define ARM_SCTLR_M     0x1 /* MMU enable */
#define ARM_SCTLR_V     0x2000 /* vectors base (high vs VBAR) */
#define ARM_SCTLR_VE    0x1000000 /* interrupt vectors enable */


// defined in kevlar linker script
extern char monitor_image_start, monitor_image_data, monitor_image_end, _monitor_start;

static inline uint8_t mycoreid(void)
{
    uint32_t val;
    __asm("mrc p15, 0, %0, c0, c0, 5" : "=r" (val));
    return val & 0xff;
}

static void secure_world_init(uintptr_t ptbase, uintptr_t vbar)
{
    uint32_t reg;

    __asm("mrc p15, 0, %0, c1, c1, 0" : "=r" (reg));
    console_printf("Initial SCR: 0x%lx\n", reg);

    /* setup secure-world page tables */

    /* load the same page table base into both TTBR0 and TTBR1
     * TTBR0 will change in the monitor's context switching code */
    assert((ptbase & 0x3fff) == 0);
    uintptr_t ttbr = ptbase | 0x6a; // XXX: cache pt walks, seems a good idea!
    __asm volatile("mcr p15, 0, %0, c2, c0, 0" :: "r" (ttbr));
    __asm volatile("mcr p15, 0, %0, c2, c0, 1" :: "r" (ttbr));

    /* setup TTBCR for a 2G/2G address split, and enable both TTBR0 and TTBR1 */
    __asm volatile("mcr p15, 0, %0, c2, c0, 2" :: "r" (7));

    /* flush stuff */
    __asm volatile("dsb");
    __asm volatile("isb");
    __asm volatile("mcr p15, 0, r0, c8, c7, 0"); // TLBIALL
    
    /* enable the MMU in the system control register
     * (this should be ok, since we have a 1:1 map for low RAM) */
    __asm volatile("mrc p15, 0, %0, c1, c0, 0" : "=r" (reg));
    reg |= ARM_SCTLR_M;
    // while we're here, ensure that there's no funny business with the VBAR
    reg &= (ARM_SCTLR_V | ARM_SCTLR_VE);
    __asm volatile("mcr p15, 0, %0, c1, c0, 0" : : "r" (reg));

    /* setup secure VBAR and MVBAR */
    __asm volatile("mcr p15, 0, %0, c12, c0, 0" :: "r" (vbar));
    __asm volatile("mcr p15, 0, %0, c12, c0, 1" :: "r" (vbar));

    /* flush again */
    __asm volatile("isb");
}

static volatile bool global_barrier;

static void __attribute__((noreturn)) secondary_main(uint8_t coreid)
{
    while (!global_barrier) __asm volatile("yield");

    /* TODO */
    while (1) {}
}

static void direct_map_section(armpte_short_l1 *l1pt, uintptr_t addr)
{
    uintptr_t idx = addr >> 20;

    l1pt[idx].raw = (armpte_short_l1) {
        .section = {
            .type = 1,
            .ns = 0, // secure-world PA, not that it makes a difference on Pi
            .secbase = idx,
        }
    }.raw;
}

static void map_l2_pages(armpte_short_l2 *l2pt, uintptr_t vaddr, uintptr_t paddr,
                         size_t bytes, bool exec)
{
    for (uintptr_t idx = vaddr >> 12; bytes > 0; idx++) {
        l2pt[idx].raw = (armpte_short_l2) {
            .smallpage = {
                .xn = exec ? 0 : 1,
                .type = 1,
                .b = 0,
                .c = 0,
                .ap01 = 1, //PL1 only
                .tex02 = 0,
                .ap2 = exec ? 1 : 0,
                .s = 0,
                .ng = 0, //?
                .base = paddr >> 12
            }
        }.raw;
        bytes -= 0x1000;
        paddr += 0x1000;
    }
}

void __attribute__((noreturn)) main(void)
{
    uint8_t coreid = mycoreid();
    if (coreid != 0) {
        secondary_main(coreid);
    }

    serial_init();
    serial_putc('H');
    console_puts("ello world\n");

    /* dump ATAGS, and reserve some high RAM for monitor etc. */
    atags_init((void *)0x100);
    atags_dump();

    uintptr_t monitor_physbase, ptbase;
    monitor_physbase = atags_reserve_physmem(KEVLAR_MON_PHYS_RESERVE);

    /* copy the monitor image into place */
    console_printf("Copying monitor to %lx\n", monitor_physbase);
    size_t monitor_image_bytes = &monitor_image_end - &monitor_image_start;
    memcpy((void *)monitor_physbase, &monitor_image_start, monitor_image_bytes);

    console_puts("Constructing page tables\n");

    /* L1 page table must be 16kB-aligned */
    ptbase = monitor_physbase + ROUND_UP(monitor_image_bytes, 16 * 1024);

    armpte_short_l1 *l1pt = (void *)ptbase;
    armpte_short_l2 *l2pt = (void *)(ptbase + 16 * 1024);

    /* direct-map first 1MB of RAM and UART registers using section mappings */
    direct_map_section(l1pt, 0);
    direct_map_section(l1pt, 0x3f200000);

    /* install a second-level page table for the monitor image */
    l1pt[KEVLAR_MON_VBASE >> 20].raw = (armpte_short_l1){
        .pagetable = {
            .type = 1,
            .pxn = 0,
            .ns = 0, // secure world PA, not that it matters on Pi?
            .ptbase = ((uintptr_t)l2pt) >> 10,
        }
    }.raw;

    // text and rodata
    size_t monitor_executable_size = &monitor_image_data - &monitor_image_start;
    map_l2_pages(l2pt, KEVLAR_MON_VBASE, monitor_physbase,
                 monitor_executable_size, true);

    // data and bss
    map_l2_pages(l2pt, KEVLAR_MON_VBASE + monitor_executable_size,
                 monitor_physbase + monitor_executable_size,
                 monitor_image_bytes - monitor_executable_size, false);

    uintptr_t monitor_entry
        = &_monitor_start - &monitor_image_start + KEVLAR_MON_VBASE;
    secure_world_init(ptbase, KEVLAR_MON_VBASE);

    /* call into the monitor's init routine
     * this will return to us in non-secure world */
    console_printf("entering monitor at %lx\n", monitor_entry);
    typedef void entry_func(void);
    ((entry_func *)monitor_entry)();

    console_printf("returned from monitor!\n");

    while (1) {}
}
